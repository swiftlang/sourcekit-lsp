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

import BuildServerIntegration
import Foundation
@preconcurrency import IndexStoreDB
package import LanguageServerProtocol
import Markdown
import SKLogging
import SKUtilities
import SemanticIndex
import SourceKitLSP

extension DocumentationLanguageService {
  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.workspaceNotOpen(req.textDocument.uri)
    }
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    var moduleName: String? = nil
    var catalogURL: URL? = nil
    if let target = await workspace.buildServerManager.canonicalTarget(for: req.textDocument.uri) {
      moduleName = await workspace.buildServerManager.moduleName(for: target)
      catalogURL = await workspace.buildServerManager.doccCatalog(for: target)
    }

    switch snapshot.language {
    case .tutorial:
      return try await tutorialDocumentation(
        for: snapshot,
        in: workspace,
        moduleName: moduleName,
        catalogURL: catalogURL
      )
    case .markdown:
      return try await markdownDocumentation(
        for: snapshot,
        in: workspace,
        moduleName: moduleName,
        catalogURL: catalogURL
      )
    case .swift:
      guard let position = req.position else {
        throw ResponseError.invalidParams("A position must be provided for Swift files")
      }

      return try await swiftDocumentation(
        for: snapshot,
        at: position,
        in: workspace,
        moduleName: moduleName,
        catalogURL: catalogURL
      )
    default:
      throw ResponseError.requestFailed(doccDocumentationError: .unsupportedLanguage(snapshot.language))
    }
  }

  private func tutorialDocumentation(
    for snapshot: DocumentSnapshot,
    in workspace: Workspace,
    moduleName: String?,
    catalogURL: URL?
  ) async throws -> DoccDocumentationResponse {
    return try await documentationManager.renderDocCDocumentation(
      tutorialFile: snapshot.text,
      moduleName: moduleName,
      catalogURL: catalogURL
    )
  }

  private func markdownDocumentation(
    for snapshot: DocumentSnapshot,
    in workspace: Workspace,
    moduleName: String?,
    catalogURL: URL?
  ) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    let documentationManager = documentationManager
    guard case .symbol(let symbolName) = MarkdownTitleFinder.find(parsing: snapshot.text) else {
      // This is an article that can be rendered on its own
      return try await documentationManager.renderDocCDocumentation(
        markupFile: snapshot.text,
        moduleName: moduleName,
        catalogURL: catalogURL
      )
    }
    guard let moduleName, symbolName == moduleName else {
      // This is a symbol extension page. Find the symbol so that we can include it in the request.
      guard let index = workspace.index(checkedFor: .deletedFiles) else {
        throw ResponseError.requestFailed(doccDocumentationError: .indexNotAvailable)
      }
      return try await sourceKitLSPServer.withOnDiskDocumentManager { onDiskDocumentManager in
        guard let symbolLink = DocCSymbolLink(linkString: symbolName),
          let symbolOccurrence = try await index.primaryDefinitionOrDeclarationOccurrence(
            ofDocCSymbolLink: symbolLink,
            fetchSymbolGraph: { location in
              return try await sourceKitLSPServer.primaryLanguageService(
                for: location.documentUri,
                workspace.buildServerManager.defaultLanguageInCanonicalTarget(for: location.documentUri),
                in: workspace
              )
              .symbolGraph(forOnDiskContentsAt: location, in: workspace, manager: onDiskDocumentManager)
            }
          )
        else {
          throw ResponseError.requestFailed(doccDocumentationError: .symbolNotFound(symbolName))
        }
        let symbolGraph = try await sourceKitLSPServer.primaryLanguageService(
          for: symbolOccurrence.location.documentUri,
          workspace.buildServerManager.defaultLanguageInCanonicalTarget(for: symbolOccurrence.location.documentUri),
          in: workspace
        ).symbolGraph(forOnDiskContentsAt: symbolOccurrence.location, in: workspace, manager: onDiskDocumentManager)
        return try await documentationManager.renderDocCDocumentation(
          symbolUSR: symbolOccurrence.symbol.usr,
          symbolGraph: symbolGraph,
          markupFile: snapshot.text,
          moduleName: moduleName,
          catalogURL: catalogURL
        )
      }
    }
    // This is a page representing the module itself.
    // Create a dummy symbol graph and tell SwiftDocC to convert the module name.
    // The version information isn't really all that important since we're creating
    // what is essentially an empty symbol graph.
    return try await documentationManager.renderDocCDocumentation(
      symbolUSR: moduleName,
      symbolGraph: emptySymbolGraph(forModule: moduleName),
      markupFile: snapshot.text,
      moduleName: moduleName,
      catalogURL: catalogURL
    )
  }

  private func swiftDocumentation(
    for snapshot: DocumentSnapshot,
    at position: Position,
    in workspace: Workspace,
    moduleName: String?,
    catalogURL: URL?
  ) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    let (symbolGraph, symbolUSR, overrideDocComments) = try await sourceKitLSPServer.primaryLanguageService(
      for: snapshot.uri,
      snapshot.language,
      in: workspace
    ).symbolGraph(for: snapshot, at: position)
    // Locate the documentation extension and include it in the request if one exists
    let markupExtensionFile = await sourceKitLSPServer.withOnDiskDocumentManager {
      [documentationManager, documentManager = try documentManager] onDiskDocumentManager in
      await orLog("Finding markup extension file for symbol \(symbolUSR)") {
        try await Self.findMarkupExtensionFile(
          workspace: workspace,
          documentationManager: documentationManager,
          documentManager: documentManager,
          catalogURL: catalogURL,
          for: symbolUSR,
          fetchSymbolGraph: { location in
            try await sourceKitLSPServer.primaryLanguageService(
              for: location.documentUri,
              snapshot.language,
              in: workspace
            )
            .symbolGraph(forOnDiskContentsAt: location, in: workspace, manager: onDiskDocumentManager)

          }
        )
      }
    }
    return try await documentationManager.renderDocCDocumentation(
      symbolUSR: symbolUSR,
      symbolGraph: symbolGraph,
      overrideDocComments: overrideDocComments,
      markupFile: markupExtensionFile,
      moduleName: moduleName,
      catalogURL: catalogURL
    )
  }

  private static func findMarkupExtensionFile(
    workspace: Workspace,
    documentationManager: DocCDocumentationManager,
    documentManager: DocumentManager,
    catalogURL: URL?,
    for symbolUSR: String,
    fetchSymbolGraph: @Sendable (SymbolLocation) async throws -> String?
  ) async throws -> String? {
    guard let catalogURL else {
      return nil
    }
    let catalogIndex = try await documentationManager.catalogIndex(for: catalogURL)
    guard let index = workspace.index(checkedFor: .deletedFiles) else {
      return nil
    }
    let symbolInformation = try await index.doccSymbolInformation(
      ofUSR: symbolUSR,
      fetchSymbolGraph: fetchSymbolGraph
    )
    guard let markupExtensionFileURL = catalogIndex.documentationExtension(for: symbolInformation) else {
      return nil
    }
    return documentManager.latestSnapshotOrDisk(
      DocumentURI(markupExtensionFileURL),
      language: .markdown
    )?.text
  }
}

struct MarkdownTitleFinder: MarkupVisitor {
  enum Title {
    case plainText(String)
    case symbol(String)
  }

  static func find(parsing text: String) -> Title? {
    let document = Markdown.Document(parsing: text, options: [.parseSymbolLinks])
    var visitor = MarkdownTitleFinder()
    return visitor.visit(document)
  }

  mutating func defaultVisit(_ markup: any Markup) -> Title? {
    for child in markup.children {
      if let value = visit(child) {
        return value
      }
    }
    return nil
  }

  mutating func visitHeading(_ heading: Heading) -> Title? {
    guard heading.level == 1 else {
      return nil
    }
    if let symbolLink = heading.child(at: 0) as? SymbolLink {
      // Remove the surrounding backticks to find the symbol name
      let plainText = symbolLink.plainText
      var startIndex = plainText.startIndex
      if plainText.hasPrefix("``") {
        startIndex = plainText.index(plainText.startIndex, offsetBy: 2)
      }
      var endIndex = plainText.endIndex
      if plainText.hasSuffix("``") {
        endIndex = plainText.index(plainText.endIndex, offsetBy: -2)
      }
      return .symbol(String(plainText[startIndex..<endIndex]))
    }
    return .plainText(heading.plainText)
  }
}
