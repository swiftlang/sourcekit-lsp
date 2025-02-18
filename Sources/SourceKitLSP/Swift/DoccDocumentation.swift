//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(SwiftDocC)
import Foundation
import SemanticIndex
import SwiftExtensions
import SwiftSyntax

#if compiler(>=6)
package import LanguageServerProtocol
#else
import LanguageServerProtocol
#endif

extension SwiftLanguageService {
  private var documentationManager: DocumentationManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentationManager
    }
  }

  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let position = req.position else {
      throw ResponseError.invalidParams("A position must be provided for Swift files")
    }
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.workspaceNotOpen(req.textDocument.uri)
    }
    let buildInformation = await workspace.doccBuildInformation(for: req.textDocument.uri)

    var externalIDsToConvert: [String]? = nil
    var overridingDocumentationComments: [String: [String]] = [:]
    var symbolGraphs: [Data] = []
    var markupFiles: [Data] = []
    // Search for the nearest documentable symbol at this location
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    guard
      let nearestDocumentableSymbol = DocumentableSymbol.findNearestSymbol(
        syntaxTree: syntaxTree,
        position: snapshot.absolutePosition(of: position)
      )
    else {
      throw ResponseError.requestFailed(doccDocumentationError: .noDocumentation)
    }
    // Retrieve the symbol graph as well as information about the symbol
    let symbolPosition = await adjustPositionToStartOfIdentifier(
      snapshot.position(of: nearestDocumentableSymbol.position),
      in: snapshot
    )
    let (cursorInfo, _, symbolGraph) = try await cursorInfo(
      req.textDocument.uri,
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
    // Locate the documentation extension and include it in the request if one exists
    if let index = workspace.index(checkedFor: .deletedFiles),
      let symbolLink = index.doccSymbolLink(forUSR: symbolUSR),
      let documentationExtensionURL = buildInformation.catalogIndex?.documentationExtension(for: symbolLink),
      let documentationExtensionSnapshot = try? documentManager.latestSnapshotOrDisk(
        DocumentURI(documentationExtensionURL),
        language: .markdown
      ),
      let documentationExtensionContents = documentationExtensionSnapshot.text.data(using: .utf8)
    {
      markupFiles.append(documentationExtensionContents)
    }
    return try await documentationManager.convertDocumentation(
      workspace: workspace,
      buildInformation: buildInformation,
      externalIDsToConvert: externalIDsToConvert,
      symbolGraphs: symbolGraphs,
      overridingDocumentationComments: overridingDocumentationComments,
      markupFiles: markupFiles
    )
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
