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
import BuildServerIntegration
import DocCDocumentation
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import SemanticIndex
import SKLogging
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
    var moduleName: String? = nil
    var catalogURL: URL? = nil
    if let target = await workspace.buildServerManager.canonicalTarget(for: req.textDocument.uri) {
      moduleName = await workspace.buildServerManager.moduleName(for: target)
      catalogURL = await workspace.buildServerManager.doccCatalog(for: target)
    }

    // Search for the nearest documentable symbol at this location
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    guard
      let nearestDocumentableSymbol = DocumentableSymbol.findNearestSymbol(
        syntaxTree: syntaxTree,
        position: snapshot.absolutePosition(of: position)
      )
    else {
      throw ResponseError.requestFailed(doccDocumentationError: .noDocumentableSymbols)
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
    let markupExtensionFile = await orLog("Finding markup extension file for symbol \(symbolUSR)") {
      try await findMarkupExtensionFile(
        workspace: workspace,
        documentationManager: documentationManager,
        catalogURL: catalogURL,
        for: symbolUSR,
        fetchSymbolGraph: { symbolLocation in
          try await withSnapshotFromDiskOpenedInSourcekitd(
            uri: symbolLocation.documentUri,
            fallbackSettingsAfterTimeout: false
          ) { (snapshot, compileCommand) in
            let (_, _, symbolGraph) = try await self.cursorInfo(
              snapshot,
              compileCommand: compileCommand,
              Range(snapshot.position(of: symbolLocation)),
              includeSymbolGraph: true
            )
            return symbolGraph
          }
        }
      )
    }
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
    for symbolUSR: String,
    fetchSymbolGraph: @Sendable (SymbolLocation) async throws -> String?
  ) async throws -> String? {
    guard let catalogURL else {
      return nil
    }
    let catalogIndex = try await documentationManager.catalogIndex(for: catalogURL)
    guard let index = workspace.index(checkedFor: .deletedFiles),
      let symbolInformation = try await index.doccSymbolInformation(
        ofUSR: symbolUSR,
        fetchSymbolGraph: fetchSymbolGraph
      ),
      let markupExtensionFileURL = catalogIndex.documentationExtension(for: symbolInformation)
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
          .split(whereSeparator: \.isNewline)
          .map { String($0).trimmingCharacters(in: .whitespaces) }
      default:
        return []
      }
    }
  }

  init?(node: any SyntaxProtocol) {
    if let namedDecl = node.asProtocol(NamedDeclSyntax.self) {
      self = DocumentableSymbol(node: namedDecl, position: namedDecl.name.positionAfterSkippingLeadingTrivia)
    } else if let initDecl = node.as(InitializerDeclSyntax.self) {
      self = DocumentableSymbol(node: initDecl, position: initDecl.initKeyword.positionAfterSkippingLeadingTrivia)
    } else if let deinitDecl = node.as(DeinitializerDeclSyntax.self) {
      self = DocumentableSymbol(node: deinitDecl, position: deinitDecl.deinitKeyword.positionAfterSkippingLeadingTrivia)
    } else if let functionDecl = node.as(FunctionDeclSyntax.self) {
      self = DocumentableSymbol(node: functionDecl, position: functionDecl.name.positionAfterSkippingLeadingTrivia)
    } else if let subscriptDecl = node.as(SubscriptDeclSyntax.self) {
      self = DocumentableSymbol(
        node: subscriptDecl.subscriptKeyword,
        position: subscriptDecl.subscriptKeyword.positionAfterSkippingLeadingTrivia
      )
    } else if let variableDecl = node.as(VariableDeclSyntax.self) {
      guard let identifier = variableDecl.bindings.only?.pattern.as(IdentifierPatternSyntax.self) else {
        return nil
      }
      self = DocumentableSymbol(node: variableDecl, position: identifier.positionAfterSkippingLeadingTrivia)
    } else if let enumCaseDecl = node.as(EnumCaseDeclSyntax.self) {
      guard let name = enumCaseDecl.elements.only?.name else {
        return nil
      }
      self = DocumentableSymbol(node: enumCaseDecl, position: name.positionAfterSkippingLeadingTrivia)
    } else {
      return nil
    }
  }

  static func findNearestSymbol(syntaxTree: SourceFileSyntax, position: AbsolutePosition) -> DocumentableSymbol? {
    let token: TokenSyntax
    if let tokenAtPosition = syntaxTree.token(at: position) {
      token = tokenAtPosition
    } else if position >= syntaxTree.endPosition, let lastToken = syntaxTree.lastToken(viewMode: .sourceAccurate) {
      // token(at:) returns nil if position is at the end of the document.
      token = lastToken
    } else if position < syntaxTree.position, let firstToken = syntaxTree.firstToken(viewMode: .sourceAccurate) {
      // No case in practice where this happens but good to cover anyway
      token = firstToken
    } else {
      return nil
    }
    // Check if the current token is within a valid documentable symbol
    if let symbol = token.ancestorOrSelf(mapping: { DocumentableSymbol(node: $0) }) {
      return symbol
    }
    // Walk forward through the tokens until we find a documentable symbol
    var previousToken: TokenSyntax? = token
    while let nextToken = previousToken?.nextToken(viewMode: .sourceAccurate) {
      if let symbol = nextToken.ancestorOrSelf(mapping: { DocumentableSymbol(node: $0) }) {
        return symbol
      }
      previousToken = nextToken
    }
    // Walk backwards through the tokens until we find a documentable symbol
    previousToken = token
    while let nextToken = previousToken?.previousToken(viewMode: .sourceAccurate) {
      if let symbol = nextToken.ancestorOrSelf(mapping: { DocumentableSymbol(node: $0) }) {
        return symbol
      }
      previousToken = nextToken
    }
    // We couldn't find anything
    return nil
  }
}
#endif
