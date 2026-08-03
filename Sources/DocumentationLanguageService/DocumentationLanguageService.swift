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

  /// In-flight debounce tasks for `publishSymbolLinkDiagnostics`, keyed by document.
  /// Cancel-and-replace on every edit so we don't run diagnostics on every keystroke, and so an
  /// older, now-stale run can never race a newer one and publish outdated results.
  private var inFlightPublishDiagnosticsTasks: [DocumentURI: Task<Void, Never>] = [:]

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
    schedulePublishSymbolLinkDiagnostics(for: snapshot.uri)
  }

  package func closeDocument(_ notification: DidCloseTextDocumentNotification) async {
    cancelInFlightPublishDiagnosticsTask(for: notification.textDocument.uri)
    inFlightPublishDiagnosticsTasks[notification.textDocument.uri] = nil
    await sourceKitLSPServer?.clearDiagnostics(for: notification.textDocument.uri, from: .documentation)
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
    schedulePublishSymbolLinkDiagnostics(for: postEditSnapshot.uri)
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
      try await resolveOccurrence(
        for: symbolLink,
        workspace: workspace,
        index: index,
        onDiskDocumentManager: onDiskDocumentManager
      )
    }

    guard let targetLocation = occurrence?.location.lspLocation else {
      logger.debug("No definition occurrence found in the index for symbol link '\(clickedSymbol)'")
      return nil
    }
    return .locations([targetLocation])
  }

  /// Walks the Markdown/DocC AST looking for a symbol link that contains a given source position.
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

    /// Resolves a click inside a multi-component link like ``Sloth/energy`` to just the component under the cursor and
    ///  everything before it: clicking `Sloth` goes to `Sloth`;
    /// clicking `energy` goes to `Sloth/energy`. Without this, any click inside the link — including on
    /// the first component — would always navigate to the full, most-nested destination.
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
    let startLine: Int
    let startColumn: Int
  }

  private enum DocTriviaGroup {
    case lines(lines: [DocCCommentLine])
    case block(text: String, startLine: Int, startColumn: Int)
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

  /// The inverse of `utf8Offset(inLine:forUTF16Offset:)`
  private func utf16Offset(inLine line: String, forUTF8Offset utf8Offset: Int) -> Int {
    let utf8View = line.utf8
    guard
      let utf8Index = utf8View.index(utf8View.startIndex, offsetBy: utf8Offset, limitedBy: utf8View.endIndex),
      let stringIndex = utf8Index.samePosition(in: line)
    else {
      return line.utf16.count
    }
    return line.utf16.distance(from: line.startIndex, to: stringIndex)
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
      groups.append(.lines(lines: pendingLines))
      pendingLines.removeAll()
    }

    for piece in trivia.pieces {
      defer { offset += piece.sourceLength.utf8Length }
      switch piece {
      case .docLineComment(let text):
        if newlinesSinceLastDoc > 1 { flushPendingLines() }
        let position = snapshot.positionOf(utf8Offset: offset)
        pendingLines.append(DocCCommentLine(text: text, startLine: position.line, startColumn: position.utf16index))
        newlinesSinceLastDoc = 0
      case .docBlockComment(let text):
        flushPendingLines()
        let position = snapshot.positionOf(utf8Offset: offset)
        groups.append(.block(text: text, startLine: position.line, startColumn: position.utf16index))
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
  ) -> (strippedLines: [StrippedLine], lineIndex: Int, targetColumn: Int)? {
    switch group {
    case .lines(let lines):
      guard let lineIndex = lines.firstIndex(where: { $0.startLine == cursorPosition.line }) else {
        return nil
      }
      let strippedLines = stripLineCommentDelimiters(lines)
      let rawLine = lines[lineIndex].text
      let relativeUTF16 = cursorPosition.utf16index - lines[lineIndex].startColumn
      let utf8Rel = utf8Offset(inLine: rawLine, forUTF16Offset: relativeUTF16)
      let targetColumn = max(1, utf8Rel - strippedLines[lineIndex].strippedPrefixCount + 1)

      return (strippedLines, lineIndex, targetColumn)

    case .block(let text, let startLine, let startColumn):
      let strippedLines = stripBlockCommentDelimiters(text)
      let lineIndex = cursorPosition.line - startLine
      guard strippedLines.indices.contains(lineIndex) else {
        return nil
      }

      let rawLines = text.components(separatedBy: "\n")
      let rawLine = rawLines[lineIndex]
      let columnBase = lineIndex == 0 ? startColumn : 0
      let relativeUTF16 = cursorPosition.utf16index - columnBase
      let utf8Rel = utf8Offset(inLine: rawLine, forUTF16Offset: relativeUTF16)
      let targetColumn = max(1, utf8Rel - strippedLines[lineIndex].strippedPrefixCount + 1)

      return (strippedLines, lineIndex, targetColumn)
    }
  }

  private func extractSymbolFromDocComment(snapshot: DocumentSnapshot, at position: Position) -> String? {
    let sourceFile = SwiftParser.Parser.parse(source: snapshot.text)
    let absolutePosition = snapshot.absolutePosition(of: position)

    guard let token = sourceFile.token(at: absolutePosition) else {
      return nil
    }

    let cursorPosition = snapshot.positionOf(utf8Offset: absolutePosition.utf8Offset)
    let groups = docCommentGroups(in: token.leadingTrivia, tokenStart: token.position, snapshot: snapshot)

    for group in groups {
      guard let (strippedLines, lineIndex, targetColumn) = resolveTarget(for: group, cursorPosition: cursorPosition)
      else {
        continue
      }

      let combinedText = strippedLines.map(\.text).joined(separator: "\n")
      let target = Markdown.SourceLocation(line: lineIndex + 1, column: targetColumn, source: nil)
      let document = Markdown.Document(parsing: combinedText, options: [.parseSymbolLinks])
      var locator = SymbolLocator(target: target)
      locator.visit(document)
      return locator.found
    }
    return nil
  }

  /// Resolves a DocC symbol link to its definition occurrence via the index, fetching the symbol graph on demand
  private func resolveOccurrence(
    for symbolLink: DocCSymbolLink,
    workspace: Workspace,
    index: CheckedIndex,
    onDiskDocumentManager: OnDiskDocumentManager
  ) async throws -> SymbolOccurrence? {
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

  // MARK: - Symbol link diagnostics

  private struct SymbolLinkReference {
    let symbol: String
    let range: Markdown.SourceRange
  }

  /// Walks a Markdown/DocC AST collecting every symbol link and its range.
  private struct SymbolLinkCollector: MarkupWalker {
    var found: [SymbolLinkReference] = []

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
      if let range = symbolLink.range, let destination = symbolLink.destination {
        found.append(SymbolLinkReference(symbol: destination, range: range))
      }
    }
  }

  /// Maps a Markdown source location to an LSP position in the original source file.
  private struct MappedLine {
    let text: String
    let absoluteLine: Int
    let absoluteColumnBase: Int
    let strippedPrefixCount: Int
  }

  private func mappedLines(for group: DocTriviaGroup) -> [MappedLine] {
    switch group {
    case .lines(let lines):
      let strippedLines = stripLineCommentDelimiters(lines)
      return zip(lines, strippedLines).map { raw, stripped in
        MappedLine(
          text: stripped.text,
          absoluteLine: raw.startLine,
          absoluteColumnBase: raw.startColumn,
          strippedPrefixCount: stripped.strippedPrefixCount
        )
      }

    case .block(let text, let startLine, let startColumn):
      let strippedLines = stripBlockCommentDelimiters(text)
      return strippedLines.enumerated().map { index, stripped in
        MappedLine(
          text: stripped.text,
          absoluteLine: startLine + index,
          absoluteColumnBase: index == 0 ? startColumn : 0,
          strippedPrefixCount: stripped.strippedPrefixCount
        )
      }
    }
  }

  private func position(for location: Markdown.SourceLocation, in lines: [MappedLine]) -> Position? {
    let index = location.line - 1
    guard lines.indices.contains(index) else { return nil }
    let line = lines[index]
    let utf16OffsetInStripped = utf16Offset(inLine: line.text, forUTF8Offset: location.column - 1)
    let absoluteUTF16 = line.absoluteColumnBase + line.strippedPrefixCount + utf16OffsetInStripped
    return Position(line: line.absoluteLine, utf16index: absoluteUTF16)
  }

  /// Collects every symbol link inside one doc-comment trivia group
  private func symbolLinks(in group: DocTriviaGroup) -> [(symbol: String, range: Range<Position>)] {
    let lines = mappedLines(for: group)
    let combinedText = lines.map(\.text).joined(separator: "\n")

    let document = Markdown.Document(parsing: combinedText, options: [.parseSymbolLinks])
    var collector = SymbolLinkCollector()
    collector.visit(document)

    return collector.found.compactMap { link in
      guard
        let start = position(for: link.range.lowerBound, in: lines),
        let end = position(for: link.range.upperBound, in: lines)
      else {
        return nil
      }
      return (link.symbol, start..<end)
    }
  }

  private func collectSymbolLinksInSwiftDocComments(
    _ snapshot: DocumentSnapshot
  ) -> [(symbol: String, range: Range<Position>)] {
    let sourceFile = SwiftParser.Parser.parse(source: snapshot.text)
    var results: [(symbol: String, range: Range<Position>)] = []

    for token in sourceFile.tokens(viewMode: .sourceAccurate) {
      let groups = docCommentGroups(in: token.leadingTrivia, tokenStart: token.position, snapshot: snapshot)
      for group in groups {
        results.append(contentsOf: symbolLinks(in: group))
      }
    }
    return results
  }

  private func collectSymbolLinksInMarkdown(_ text: String) -> [(symbol: String, range: Range<Position>)] {
    let lines = text.components(separatedBy: "\n")
    let document = Markdown.Document(parsing: text, options: [.parseSymbolLinks, .parseBlockDirectives])
    var collector = SymbolLinkCollector()
    collector.visit(document)

    func position(for location: Markdown.SourceLocation) -> Position? {
      let lineIndex = location.line - 1
      guard lines.indices.contains(lineIndex) else { return nil }
      let utf16Col = utf16Offset(inLine: lines[lineIndex], forUTF8Offset: location.column - 1)
      return Position(line: lineIndex, utf16index: utf16Col)
    }

    return collector.found.compactMap { link in
      guard let start = position(for: link.range.lowerBound), let end = position(for: link.range.upperBound) else {
        return nil
      }
      return (link.symbol, start..<end)
    }
  }

  private func collectSymbolLinks(in snapshot: DocumentSnapshot) -> [(symbol: String, range: Range<Position>)] {
    switch snapshot.language {
    case .swift:
      return collectSymbolLinksInSwiftDocComments(snapshot)
    case .markdown, .tutorial:
      return collectSymbolLinksInMarkdown(snapshot.text)
    default:
      return []
    }
  }

  private func cancelInFlightPublishDiagnosticsTask(for uri: DocumentURI) {
    inFlightPublishDiagnosticsTasks[uri]?.cancel()
  }

  private func schedulePublishSymbolLinkDiagnostics(for uri: DocumentURI) {
    cancelInFlightPublishDiagnosticsTask(for: uri)
    inFlightPublishDiagnosticsTasks[uri] = Task(priority: .medium) { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(500))
      } catch {
        return  // cancelled by a newer edit
      }
      await self?.publishSymbolLinkDiagnostics(for: uri)
    }
  }

  private func symbolLinkDiagnostics(for snapshot: DocumentSnapshot) async -> [Diagnostic]? {
    guard let sourceKitLSPServer else { return nil }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: snapshot.uri) else { return nil }

    await workspace.semanticIndexManagerTask.value?.waitForUpToDateIndex()
    guard !Task.isCancelled else { return nil }
    guard let index = await workspace.index(checkedFor: .deletedFiles) else { return nil }

    let symbolLinks = collectSymbolLinks(in: snapshot)

    return await sourceKitLSPServer.withOnDiskDocumentManager { onDiskDocumentManager in
      var diagnostics: [Diagnostic] = []
      for link in symbolLinks {
        guard !Task.isCancelled else { break }
        guard let symbolLink = DocCSymbolLink(linkString: link.symbol) else {
          diagnostics.append(
            Diagnostic(
              range: link.range,
              severity: .error,
              source: "DocC",
              message: "Failed to parse DocC symbol link '\(link.symbol)'"
            )
          )
          continue
        }
        do {
          let occurrence = try await resolveOccurrence(
            for: symbolLink,
            workspace: workspace,
            index: index,
            onDiskDocumentManager: onDiskDocumentManager
          )
          if occurrence == nil {
            diagnostics.append(
              Diagnostic(
                range: link.range,
                severity: .error,
                source: "DocC",
                message: "No symbol link resolved for '\(link.symbol)'"
              )
            )
          }
        } catch {
          logger.debug("Failed to resolve DocC symbol link '\(link.symbol)': \(error.forLogging)")
          continue
        }
      }
      return diagnostics
    }
  }

  private func publishSymbolLinkDiagnostics(for uri: DocumentURI) async {
    guard let sourceKitLSPServer else { return }
    guard let snapshot = try? self.documentManager.latestSnapshot(uri) else { return }

    // Pull diagnostics are the first preference; only push if the client can't pull diagnostics for this document's language
    let clientSupportsPull =
      await sourceKitLSPServer.capabilityRegistry?.clientSupportsPullDiagnostics(for: snapshot.language) ?? false
    guard !clientSupportsPull else { return }

    guard !Task.isCancelled else { return }
    guard let diagnostics = await symbolLinkDiagnostics(for: snapshot) else { return }
    guard !Task.isCancelled else { return }

    await sourceKitLSPServer.publishDiagnostics(diagnostics, for: uri, from: .documentation)
  }

  package func documentDiagnostic(_ req: DocumentDiagnosticsRequest) async throws -> DocumentDiagnosticReport {
    switch try? ReferenceDocumentURL(from: req.textDocument.uri) {
    case .generatedInterface:
      // Generated interfaces don't have diagnostics associated with them.
      return .full(RelatedFullDocumentDiagnosticReport(items: []))
    case .macroExpansion, nil: break
    }

    guard let snapshot = try? self.documentManager.latestSnapshot(req.textDocument.uri) else {
      return .full(RelatedFullDocumentDiagnosticReport(items: []))
    }

    try Task.checkCancellation()

    let diagnostics = await symbolLinkDiagnostics(for: snapshot) ?? []
    return .full(RelatedFullDocumentDiagnosticReport(items: diagnostics))
  }
}
