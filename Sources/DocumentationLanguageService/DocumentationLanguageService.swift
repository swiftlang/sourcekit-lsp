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
import SemanticIndex
package import SourceKitLSP
import SwiftExtensions
import SwiftParser
package import SwiftSyntax
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

    private func contains(_ range: Markdown.SourceRange?) -> Bool {
      guard let range else { return false }
      return range.lowerBound <= target && target < range.upperBound
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
      guard
        found == nil,
        contains(symbolLink.range),
        let destination = symbolLink.destination,
        let range = symbolLink.range
      else {
        return
      }
      // Symbol links are delimited by two backticks (``Foo/bar``),
      // so the destination starts two columns past the start of the link.
      let destinationStartColumn = range.lowerBound.column + 2
      let relativeColumn = target.column - destinationStartColumn
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
    let lines = text.components(separatedBy: "\n")
    var column = position.utf16index + 1
    if position.line < lines.count {
      column = utf8Offset(inLine: lines[position.line], forUTF16Offset: position.utf16index) + 1
    }
    // LSP positions are 0-based; swift-markdown SourceLocation is 1-based.
    let target = Markdown.SourceLocation(
      line: position.line + 1,
      column: column,
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

  private struct DocCCommentLine {
    let text: String
    let start: Position
  }

  private enum DocTriviaGroup {
    case lines([DocCCommentLine])
    case block(text: String, start: Position)
  }

  /// Converts a UTF-16 offset within `line` into the corresponding UTF-8 byte offset.
  /// Needed because DocumentSnapshot/LSP positions are UTF-16-based but
  /// Markdown.SourceLocation.column is UTF-8-byte-based.
  private func utf8Offset(inLine line: String, forUTF16Offset utf16Offset: Int) -> Int {
    let utf16View = line.utf16
    guard
      let utf16Index = utf16View.index(utf16View.startIndex, offsetBy: utf16Offset, limitedBy: utf16View.endIndex),
      let stringIndex = utf16Index.samePosition(in: line)
    else {
      return line.utf8.count
    }
    return line.utf8.distance(from: line.startIndex, to: stringIndex)
  }

  private func docCommentGroups(
    in trivia: Trivia,
    tokenStart: AbsolutePosition,
    snapshot: DocumentSnapshot
  ) -> [DocTriviaGroup] {
    var groups: [DocTriviaGroup] = []
    var pendingLines: [DocCCommentLine] = []
    var offset = tokenStart.utf8Offset
    var newlinesSinceLastDoc = 0

    func flushPendingLines() {
      guard !pendingLines.isEmpty else { return }
      groups.append(.lines(pendingLines))
      pendingLines.removeAll()
    }

    for piece in trivia.pieces {
      defer { offset += piece.sourceLength.utf8Length }
      switch piece {
      case .docLineComment(let text):
        if newlinesSinceLastDoc > 1 { flushPendingLines() }
        let position = snapshot.positionOf(utf8Offset: offset)
        pendingLines.append(DocCCommentLine(text: text, start: position))
        newlinesSinceLastDoc = 0
      case .docBlockComment(let text):
        flushPendingLines()
        let position = snapshot.positionOf(utf8Offset: offset)
        groups.append(.block(text: text, start: position))
        newlinesSinceLastDoc = 0
      case .newlines(let n), .carriageReturns(let n), .carriageReturnLineFeeds(let n):
        newlinesSinceLastDoc += n
      case .spaces, .tabs:
        break
      default:
        flushPendingLines()
        newlinesSinceLastDoc = 0
      }
    }
    flushPendingLines()
    return groups
  }
  
  /// A line of documentation text after stripping its comment delimiters/prefix.
  /// `strippedPrefixCount` is the number of UTF-16 code units removed from the
  /// beginning of the original line to produce `text`.
  private struct StrippedLine {
    let text: String
    let strippedPrefixCount: Int
  }

  /// Strips `///` and any leading whitespace from each line comment piece.
  private func stripLineCommentDelimiters(
    _ lines: [DocCCommentLine]
  ) -> [StrippedLine] {
    return lines.map { line in
      var text = Substring(line.text)
      var stripped = 0

      if text.hasPrefix("///") {
        text.removeFirst(3)
        stripped += 3
      }
      let beforeIndent = text.utf16.count
      let trimmed = text.drop { $0 == " " || $0 == "\t" }
      stripped += beforeIndent - trimmed.utf16.count
      text = trimmed
      return StrippedLine(text: String(text), strippedPrefixCount: stripped)
    }
  }

  /// Strips `/**`, `*/`, and per-line leading `*`/whitespace from a block comment.
  private func stripBlockCommentDelimiters(_ text: String) -> [StrippedLine] {
    let lines = text.components(separatedBy: "\n")
    return lines.enumerated().map { index, rawLine in
      var line = Substring(rawLine)
      var stripped = 0

      if index == 0, line.hasPrefix("/**") {
        line.removeFirst(3)
        stripped += 3
      }
      if index == lines.count - 1, line.hasSuffix("*/") {
        line.removeLast(2)
      }
      let beforeStar = line.utf16.count
      var afterStar = line.drop { $0 == " " || $0 == "\t" }
      if afterStar.hasPrefix("*") {
        afterStar.removeFirst()
        if afterStar.hasPrefix(" ") { afterStar.removeFirst() }
        stripped += beforeStar - afterStar.utf16.count
        line = afterStar
      }
      let beforeIndent = line.utf16.count
      let trimmed = line.drop { $0 == " " || $0 == "\t" }
      stripped += beforeIndent - trimmed.utf16.count
      line = trimmed
      return StrippedLine(text: String(line), strippedPrefixCount: stripped)
    }
  }

  private func resolveTarget(
    for group: DocTriviaGroup,
    cursorPosition: Position
  ) -> (strippedLines: [StrippedLine], target: Position)? {
    switch group {
    case .lines(let lines):
      guard let lineIndex = lines.firstIndex(where: { $0.start.line == cursorPosition.line }) else {
        return nil
      }
      let strippedLines = stripLineCommentDelimiters(lines)
      let relativeUTF16 = cursorPosition.utf16index - lines[lineIndex].start.utf16index
      let localColumn = max(0, relativeUTF16 - strippedLines[lineIndex].strippedPrefixCount)
      return (strippedLines, Position(line: lineIndex, utf16index: localColumn))

    case .block(let text, let start):
      let strippedLines = stripBlockCommentDelimiters(text)
      let lineIndex = cursorPosition.line - start.line
      guard strippedLines.indices.contains(lineIndex) else { return nil }
      let columnBase = lineIndex == 0 ? start.utf16index : 0
      let relativeUTF16 = cursorPosition.utf16index - columnBase
      let localColumn = max(0, relativeUTF16 - strippedLines[lineIndex].strippedPrefixCount)
      return (strippedLines, Position(line: lineIndex, utf16index: localColumn))
    }
  }

  private func extractSymbolFromDocComment(snapshot: DocumentSnapshot, at position: Position) -> String? {
    let sourceFile = SwiftParser.Parser.parse(source: snapshot.text)
    let absolutePosition = snapshot.absolutePosition(of: position)
    guard let token = sourceFile.token(at: absolutePosition) else { return nil }

    let leadingGroups = docCommentGroups(in: token.leadingTrivia, tokenStart: token.position, snapshot: snapshot)
    let trailingGroups = docCommentGroups(
      in: token.trailingTrivia,
      tokenStart: token.endPositionBeforeTrailingTrivia,
      snapshot: snapshot
    )

    for group in leadingGroups + trailingGroups {
      guard let (strippedLines, target) = resolveTarget(for: group, cursorPosition: position) else { continue }

      let combinedText = strippedLines.map(\.text).joined(separator: "\n")
      let utf8Column = utf8Offset(inLine: strippedLines[target.line].text, forUTF16Offset: target.utf16index) + 1
      let markdownTarget = Markdown.SourceLocation(line: target.line + 1, column: utf8Column, source: nil)

      let document = Markdown.Document(parsing: combinedText, options: [.parseSymbolLinks])
      var locator = SymbolLocator(target: markdownTarget)
      locator.visit(document)
      return locator.found
    }
    return nil
  }
}
