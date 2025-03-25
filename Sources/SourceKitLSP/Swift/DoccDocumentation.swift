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

#if canImport(DocCDocumentation)
import DocCDocumentation
import Foundation
package import LanguageServerProtocol
import SemanticIndex
import SwiftExtensions
import SwiftSyntax

extension SwiftLanguageService {
  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.workspaceNotOpen(req.textDocument.uri)
    }
    let documentationManager = workspace.doccDocumentationManager
    guard let position = req.position else {
      throw ResponseError.invalidParams("A position must be provided for Swift files")
    }
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.workspaceNotOpen(req.textDocument.uri)
    }
    let moduleName = await workspace.buildSystemManager.moduleName(for: req.textDocument.uri)
    let catalogURL = await workspace.buildSystemManager.doccCatalog(for: req.textDocument.uri)

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
    // Locate the documentation extension and include it in the request if one exists
    let markupExtensionFile = try? await findMarkupExtensionFile(
      workspace: workspace,
      documentationManager: documentationManager,
      catalogURL: catalogURL,
      for: symbolUSR
    )
    return try await documentationManager.renderDocCDocumentation(
      symbolUSR: symbolUSR,
      symbolGraph: symbolGraph,
      overrideDocComments: nearestDocumentableSymbol.documentationComments,
      markupFile: markupExtensionFile,
      moduleName: moduleName,
      catalogURL: catalogURL
    )
  }

  private func findMarkupExtensionFile(
    workspace: Workspace,
    documentationManager: DocCDocumentationManager,
    catalogURL: URL?,
    for symbolUSR: String
  ) async throws -> String? {
    guard let catalogURL else {
      return nil
    }
    let catalogIndex = try await documentationManager.catalogIndex(for: catalogURL)
    guard let index = workspace.index(checkedFor: .deletedFiles),
      let symbolLink = await documentationManager.symbolLink(forUSR: symbolUSR, in: index),
      let markupExtensionFileURL = catalogIndex.documentationExtension(for: symbolLink)
    else {
      return nil
    }
    return try? documentManager.latestSnapshotOrDisk(
      DocumentURI(markupExtensionFileURL),
      language: .markdown
    )?.text
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
