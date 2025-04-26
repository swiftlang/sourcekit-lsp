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
import BuildSystemIntegration
import DocCDocumentation
import Foundation
@preconcurrency import IndexStoreDB
package import LanguageServerProtocol
import Markdown
import SKUtilities
import SemanticIndex

extension DocumentationLanguageService {
  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.workspaceNotOpen(req.textDocument.uri)
    }
    let documentationManager = workspace.doccDocumentationManager
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    var moduleName: String? = nil
    var catalogURL: URL? = nil
    if let target = await workspace.buildSystemManager.canonicalTarget(for: req.textDocument.uri) {
      moduleName = await workspace.buildSystemManager.moduleName(for: target)
      catalogURL = await workspace.buildSystemManager.doccCatalog(for: target)
    }

    switch snapshot.language {
    case .tutorial:
      return try await documentationManager.renderDocCDocumentation(
        tutorialFile: snapshot.text,
        moduleName: moduleName,
        catalogURL: catalogURL
      )
    case .markdown:
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
        guard let symbolLink = DocCSymbolLink(linkString: symbolName),
          let symbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofDocCSymbolLink: symbolLink)
        else {
          throw ResponseError.requestFailed(doccDocumentationError: .symbolNotFound(symbolName))
        }
        let symbolDocumentUri = symbolOccurrence.location.documentUri
        guard
          let symbolWorkspace = try await workspaceForDocument(uri: symbolDocumentUri),
          let languageService = try await languageService(for: symbolDocumentUri, .swift, in: symbolWorkspace)
            as? SwiftLanguageService
        else {
          throw ResponseError.internalError("Unable to find Swift language service for \(symbolDocumentUri)")
        }
        let symbolGraph = try await languageService.withSnapshotFromDiskOpenedInSourcekitd(
          uri: symbolDocumentUri,
          fallbackSettingsAfterTimeout: false
        ) { snapshot, compileCommand in
          try await languageService.cursorInfo(
            snapshot,
            compileCommand: compileCommand,
            Range(snapshot.position(of: symbolOccurrence.location)),
            includeSymbolGraph: true
          ).symbolGraph
        }
        guard let symbolGraph else {
          throw ResponseError.internalError("Unable to retrieve symbol graph for \(symbolOccurrence.symbol.name)")
        }
        return try await documentationManager.renderDocCDocumentation(
          symbolUSR: symbolOccurrence.symbol.usr,
          symbolGraph: symbolGraph,
          markupFile: snapshot.text,
          moduleName: moduleName,
          catalogURL: catalogURL
        )
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
    default:
      throw ResponseError.requestFailed(doccDocumentationError: .noDocumentation)
    }
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
#endif
