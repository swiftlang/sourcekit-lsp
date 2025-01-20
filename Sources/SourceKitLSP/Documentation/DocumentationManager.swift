//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(SwiftDocC)
import BuildSystemIntegration
import BuildServerProtocol
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import SemanticIndex
import SwiftDocC
import SwiftExtensions
import SwiftSyntax

package final actor DocumentationManager {
  private weak var sourceKitLSPServer: SourceKitLSPServer?

  private let doccServer: DocCServer

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.doccServer = DocCServer(peer: nil, qualityOfService: .default)
  }

  func convertDocumentation(
    _ documentURI: DocumentURI,
    at position: Position? = nil
  ) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer = sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: documentURI) else {
      throw ResponseError.workspaceNotOpen(documentURI)
    }

    let snapshot = try sourceKitLSPServer.documentManager.latestSnapshot(documentURI)
    let targetId = await workspace.buildSystemManager.canonicalTarget(for: documentURI)
    var moduleName: String? = nil
    if let targetId {
      moduleName = await workspace.buildSystemManager.moduleName(for: documentURI, in: targetId)
    }

    var externalIDsToConvert: [String]?
    var symbolGraphs = [Data]()
    var overridingDocumentationComments = [String: [String]]()
    switch snapshot.language {
    case .swift:
      guard let position else {
        throw ResponseError.invalidParams("A position must be provided for Swift files")
      }
      guard let languageService = await sourceKitLSPServer.languageService(for: documentURI, .swift, in: workspace),
        let swiftLanguageService = languageService as? SwiftLanguageService
      else {
        throw ResponseError.internalError("Unable to find Swift language service for \(documentURI)")
      }
      // Search for the nearest documentable symbol at this location
      let syntaxTree = await swiftLanguageService.syntaxTreeManager.syntaxTree(for: snapshot)
      guard
        let nearestDocumentableSymbol = DocumentableSymbol.findNearestSymbol(
          syntaxTree: syntaxTree,
          position: snapshot.absolutePosition(of: position)
        )
      else {
        throw ResponseError.requestFailed(convertError: .noDocumentation)
      }
      // Retrieve the symbol graph as well as information about the symbol
      let symbolPosition = await swiftLanguageService.adjustPositionToStartOfIdentifier(
        snapshot.position(of: nearestDocumentableSymbol.position),
        in: snapshot
      )
      let (cursorInfo, _, symbolGraph) = try await swiftLanguageService.cursorInfo(
        documentURI,
        Range(symbolPosition),
        includeSymbolGraph: true,
        fallbackSettingsAfterTimeout: false
      )
      guard let symbolGraph,
        let cursorInfo = cursorInfo.first,
        let symbolUSR = cursorInfo.symbolInfo.usr
      else {
        throw ResponseError.internalError("Unable to retrieve symbol graph for the document")
      }
      guard let rawSymbolGraph = symbolGraph.data(using: .utf8) else {
        throw ResponseError.internalError("Unable to encode symbol graph")
      }
      externalIDsToConvert = [symbolUSR]
      symbolGraphs.append(rawSymbolGraph)
      overridingDocumentationComments[symbolUSR] = nearestDocumentableSymbol.documentationComments
    default:
      throw ResponseError.requestFailed(convertError: .noDocumentation)
    }
    // Send the convert request to SwiftDocC and wait for the response
    let convertResponse = try await doccServer.convert(
      externalIDsToConvert: externalIDsToConvert,
      documentPathsToConvert: nil,
      includeRenderReferenceStore: false,
      documentationBundleLocation: nil,
      documentationBundleDisplayName: moduleName ?? "Unknown",
      documentationBundleIdentifier: "unknown",
      symbolGraphs: symbolGraphs,
      overridingDocumentationComments: overridingDocumentationComments,
      emitSymbolSourceFileURIs: false,
      markupFiles: [],
      tutorialFiles: [],
      convertRequestIdentifier: UUID().uuidString
    )
    guard let renderNodeData = convertResponse.renderNodes.first else {
      throw ResponseError.internalError("SwiftDocC did not return any render nodes")
    }
    guard let renderNode = String(data: renderNodeData, encoding: .utf8) else {
      throw ResponseError.internalError("Failed to encode render node from SwiftDocC")
    }
    return DoccDocumentationResponse(renderNode: renderNode)
  }
}

package enum ConvertDocumentationError {
  case noDocumentation

  public var message: String {
    switch self {
    case .noDocumentation:
      return "No documentation could be rendered for the position in this document"
    }
  }
}

fileprivate extension ResponseError {
  static func requestFailed(convertError: ConvertDocumentationError) -> ResponseError {
    return ResponseError.requestFailed(convertError.message)
  }
}

fileprivate struct DocumentableSymbol {
  let position: AbsolutePosition
  let documentationComments: [String]

  init(node: any SyntaxProtocol, position: AbsolutePosition) {
    self.position = position
    self.documentationComments = node.leadingTrivia.flatMap { trivia -> [String] in
      switch trivia {
      case .docLineComment(let comment):
        return [String(comment.dropFirst(3).trimmingCharacters(in: .whitespaces))]
      case .docBlockComment(let comment):
        return comment.dropFirst(3)
          .dropLast(2)
          .split(separator: "\n")
          .map { String($0).trimmingCharacters(in: .whitespaces) }
      default:
        return []
      }
    }
  }
}

fileprivate extension DocumentableSymbol {
  static func findNearestSymbol(syntaxTree: SourceFileSyntax, position: AbsolutePosition) -> DocumentableSymbol? {
    guard let token = syntaxTree.token(at: position) else {
      return nil
    }
    return token.ancestorOrSelf { node in
      if let namedDecl = node.asProtocol(NamedDeclSyntax.self) {
        return DocumentableSymbol(node: namedDecl, position: namedDecl.name.positionAfterSkippingLeadingTrivia)
      } else if let initDecl = node.as(InitializerDeclSyntax.self) {
        return DocumentableSymbol(node: initDecl, position: initDecl.initKeyword.positionAfterSkippingLeadingTrivia)
      } else if let functionDecl = node.as(FunctionDeclSyntax.self) {
        return DocumentableSymbol(node: functionDecl, position: functionDecl.name.positionAfterSkippingLeadingTrivia)
      } else if let variableDecl = node.as(VariableDeclSyntax.self) {
        guard let identifier = variableDecl.bindings.only?.pattern.as(IdentifierPatternSyntax.self) else {
          return nil
        }
        return DocumentableSymbol(node: variableDecl, position: identifier.positionAfterSkippingLeadingTrivia)
      } else if let enumCaseDecl = node.as(EnumCaseDeclSyntax.self) {
        guard let name = enumCaseDecl.elements.only?.name else {
          return nil
        }
        return DocumentableSymbol(node: enumCaseDecl, position: name.positionAfterSkippingLeadingTrivia)
      }
      return nil
    }
  }
}
#endif
