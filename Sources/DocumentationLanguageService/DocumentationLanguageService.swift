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

import BuildServerIntegration
import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
import Markdown
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax
import SymbolKit
package import ToolchainRegistry

package actor DocumentationLanguageService: LanguageService, Sendable {
  /// The ``SourceKitLSPServer`` instance that created this `DocumentationLanguageService`.
  weak let sourceKitLSPServer: SourceKitLSPServer?

  let documentationManager: DocCDocumentationManager

  var documentManager: DocumentManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentManager
    }
  }

  let workspace: Workspace

  package static var experimentalCapabilities: [String: LSPAny] {
    return [
      DoccDocumentationRequest.method: ["version": 1],
      "definitionProvider": .bool(true),
    ]
  }

  package init(
    sourceKitLSPServer: SourceKitLSPServer,
    toolchain: Toolchain,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    workspace: Workspace
  ) async throws {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.documentationManager = DocCDocumentationManager(buildServerManager: workspace.buildServerManager);
    self.workspace = workspace
  }

  package nonisolated func canHandle(toolchain: Toolchain) -> Bool {
    return true
  }

  package func shutdown() async {
    // Nothing to tear down
  }

  package func addStateChangeHandler(
    handler: @escaping @Sendable (LanguageServerState, LanguageServerState) -> Void
  ) async {
    // There is no underlying language server with which to report state
  }

  package func openDocument(
    _ notification: DidOpenTextDocumentNotification,
    snapshot: DocumentSnapshot
  ) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func closeDocument(_ notification: DidCloseTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func reopenDocument(_ notification: ReopenTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func syntacticTestItems(for snapshot: DocumentSnapshot) async -> [AnnotatedTestItem]? {
    // We know documentation files have no test cases.
    return []
  }

  package func syntacticPlaygrounds(
    for snapshot: DocumentSnapshot,
    in workspace: Workspace
  ) async -> [TextDocumentPlayground] {
    return []
  }

  package func changeDocument(
    _ notification: DidChangeTextDocumentNotification,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot,
    edits: [SwiftSyntax.SourceEdit]
  ) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func symbolInfo(_ req: SymbolInfoRequest) async throws -> [SymbolDetails] {
    return []
  }

  package func definition(_ req: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {

    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let text = snapshot.text

    guard let clickedSymbol = extractSymbolFromText(text, at: req.position) else {
      return nil
    }

    guard
      let targetLocation = await findLocationInSymbolGraphs(
        for: clickedSymbol,
        currentDocumentURI: req.textDocument.uri,
      )
    else {
      return nil
    }

    return .locations([targetLocation])
  }

  /// Walks the Markdown/DocC AST looking for the inline code span or symbol link
  /// that contains a given source position.
  private struct SymbolLocator: MarkupWalker {
    let target: Markdown.SourceLocation
    var found: String?

    init(target: Markdown.SourceLocation) {
      self.target = target
    }

    private func contains(_ range: Markdown.SourceRange?) -> Bool {
      guard let range else { return false }
      return range.lowerBound <= target && target < range.upperBound
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
      if found == nil, let range = inlineCode.range, contains(range) {
        found = inlineCode.code
      }
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
      if found == nil, contains(symbolLink.range), let destination = symbolLink.destination {
        found = destination
      }
    }

    mutating func defaultVisit(_ markup: any Markup) {
      guard found == nil else { return }
      descendInto(markup)
    }
  }

  private func extractSymbolFromText(_ text: String, at position: Position) -> String? {
    // LSP positions are 0-based; swift-markdown SourceLocation is 1-based.
    let target = Markdown.SourceLocation(
      line: position.line + 1,
      column: position.utf16index + 1,
      source: nil
    )

    let document = Markdown.Document(parsing: text, options: [.parseSymbolLinks, .parseBlockDirectives])
    var locator = SymbolLocator(target: target)
    locator.visit(document)

    guard let symbol = locator.found, !symbol.isEmpty else {
      return nil
    }
    return symbol
  }

  private func findLocationInSymbolGraphs(
    for symbolPath: String,
    currentDocumentURI: DocumentURI
  ) async -> Location? {
    //Extract the base symbol name from a path (e.g., "MyModule/Sloth" -> "Sloth")

    let symbolName = symbolPath.components(separatedBy: "/").last ?? symbolPath

    //Identify which specific module owns this active documentation file
    // This lets us target exactly one file instead of scanning everything
    guard let targetID = await self.workspace.buildServerManager.targets(for: currentDocumentURI).first,
      let moduleName = await self.workspace.buildServerManager.moduleName(for: targetID)
    else {
      return nil
    }

    //Directly target only that module's symbol graph JSON file on disk
    let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let targetGraphURL =
      workspaceRoot
      .appendingPathComponent(".build/symbol-graphs")
      .appendingPathComponent("\(moduleName).symbols.json")

    //Decode the single targeted file directly
    guard let data = try? Data(contentsOf: targetGraphURL),
      let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let symbolsArray = jsonObject["symbols"] as? [[String: Any]]
    else {
      return nil
    }

    //Look for the matching symbol name inside symbolArray
    for symbol in symbolsArray {
      if let namesDict = symbol["names"] as? [String: Any],
        let title = namesDict["title"] as? String,
        title == symbolName
      {
        //Read the "location" block
        guard let locationDict = symbol["location"] as? [String: Any],
          let uriString = locationDict["uri"] as? String,
          let positionDict = locationDict["position"] as? [String: Any],
          let line = positionDict["line"] as? Int,
          let character = positionDict["character"] as? Int
        else {
          return nil
        }

        //Convert to an LSP Location object
        if let targetURI = try? DocumentURI(string: uriString) {
          let destinationPosition = Position(line: line, utf16index: character)
          let destinationRange = Range(uncheckedBounds: (lower: destinationPosition, upper: destinationPosition))

          return Location(uri: targetURI, range: destinationRange)
        }
      }
    }
    return nil
  }
}
