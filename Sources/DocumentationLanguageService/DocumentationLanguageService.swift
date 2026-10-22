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
import SKUtilities
import SemanticIndex
package import SourceKitLSP
import SwiftExtensions
import SwiftParser
@_spi(SourceKitLSP) package import SwiftSyntax
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

  package static var experimentalCapabilities: [String: LSPAny] {
    return [
      DoccDocumentationRequest.method: ["version": 1]
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
    self.documentationManager = DocCDocumentationManager(buildServerManager: workspace.buildServerManager)
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

  package func definition(_ req: DefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let clickedSymbol: String?
    switch snapshot.language {
    case .swift:
      clickedSymbol = extractSymbolFromDocComment(snapshot: snapshot, at: req.position)
    case .markdown, .tutorial:
      clickedSymbol = extractSymbolFromText(snapshot.text, at: req.position)
    default:
      return nil
    }

    guard let clickedSymbol else {
      logger.debug("No symbol link found at the cursor position")
      return nil
    }

    guard let symbolLink = DocCSymbolLink(linkString: clickedSymbol) else {
      logger.debug("Failed to parse DocC symbol link from '\(clickedSymbol)'")
      return nil
    }

    guard let sourceKitLSPServer else {
      logger.debug("sourceKit-LSP server could not be resolved")
      return nil
    }

    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      logger.debug("No workspace found for document \(req.textDocument.uri)")
      return nil
    }

    guard let index = await workspace.index(checkedFor: .deletedFiles) else {
      logger.debug("No index available for workspace")
      return nil
    }

    let occurrence = try await sourceKitLSPServer.withOnDiskDocumentManager { onDiskDocumentManager in
      try await index.primaryDefinitionOrDeclarationOccurrence(
        ofDocCSymbolLink: symbolLink,
        fetchSymbolGraph: { location in
          guard let uri = location.uri else { return nil }
          return try await workspace.primaryLanguageService(
            for: uri,
            workspace.buildServerManager.defaultLanguageInCanonicalTarget(for: uri)
          ).symbolGraph(forOnDiskContentsAt: location, in: workspace, manager: onDiskDocumentManager)
        }
      )
    }

    guard let targetLocation = occurrence?.location.lspLocation else {
      logger.debug("No definition occurrence found in the index for symbol link '\(clickedSymbol)'")
      return nil
    }
    return .locations([targetLocation])
  }

  /// Walks the Markdown/DocC AST looking for a symbol link that contains a
  /// given source position, and sets `found` to the link's destination
  /// truncated to the component under the cursor (e.g. `Foo/bar/baz` with
  /// the cursor on `bar` sets `found` to `"Foo/bar"`), not the full destination.
  private struct SymbolLocator: MarkupWalker {
    let target: Markdown.SourceLocation
    var found: String?

    init(target: Markdown.SourceLocation) {
      self.target = target
    }

    private func targetIsContained(by range: Markdown.SourceRange?) -> Bool {
      guard let range else { return false }
      return range.lowerBound <= target && target < range.upperBound
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
      guard
        found == nil,
        targetIsContained(by: symbolLink.range),
        let destination = symbolLink.destination,
        let range = symbolLink.range,
        range.lowerBound.line == target.line
      else {
        return
      }
      // Symbol links are delimited by two backticks (``Foo/bar``),
      // so the destination starts two columns past the start of the link.
      // The offset of the target location relative to the link’s start
      let targetOffsetFromLinkStart = range.lowerBound.column + 2
      let relativeColumn = target.column - targetOffsetFromLinkStart
      guard relativeColumn >= 0 else {
        return
      }
      let components = destination.split(separator: "/")
      var currentLength = 0

      for (index, component) in components.enumerated() {
        let end = currentLength + component.utf8.count
        if relativeColumn < end {
          found = components[0...index].joined(separator: "/")
          return
        }
        currentLength = end + 1  // Skip '/'
      }
      found = destination
    }

    mutating func defaultVisit(_ markup: any Markup) {
      guard found == nil else { return }
      descendInto(markup)
    }
  }

  private func extractSymbolFromText(_ text: String, at position: Position) -> String? {
    let lineTable = LineTable(text)
    let utf8Column = lineTable.utf8ColumnAt(line: position.line, utf16Column: position.utf16index)
  
    // LSP positions are 0-based; swift-markdown SourceLocation is 1-based.
    let target = Markdown.SourceLocation(
      line: position.line + 1,
      column: utf8Column + 1,
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

  private func extractSymbolFromDocComment(snapshot: DocumentSnapshot, at position: Position) -> String? {
    let sourceFile = SwiftParser.Parser.parse(source: snapshot.text)
    let cursor = snapshot.absolutePosition(of: position)
    guard let token = sourceFile.token(at: cursor) else { return nil }

    let candidates = [
      token.leadingTrivia.docCommentLines(startingAt: token.position),
      token.trailingTrivia.docCommentLines(startingAt: token.endPositionBeforeTrailingTrivia),
    ]

    for case let lines? in candidates {
      guard
        let lineIndex = lines.firstIndex(where: {
          $0.position.utf8Offset <= cursor.utf8Offset
            && cursor.utf8Offset <= $0.position.utf8Offset + $0.text.utf8.count
        })
      else { continue }

      let utf8Column = cursor.utf8Offset - lines[lineIndex].position.utf8Offset
      let markdownTarget = Markdown.SourceLocation(line: lineIndex + 1, column: utf8Column + 1, source: nil)

      let text = lines.map(\.text).joined(separator: "\n")
      let document = Markdown.Document(parsing: text, options: [.parseSymbolLinks])
      var locator = SymbolLocator(target: markdownTarget)
      locator.visit(document)
      return locator.found
    }
    return nil
  }
}
