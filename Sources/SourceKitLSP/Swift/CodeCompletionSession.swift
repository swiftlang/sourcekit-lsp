//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd
import Dispatch
import Foundation
import LanguageServerProtocol
import SKLogging
import SKOptions
import SKUtilities
import SourceKitD
import SwiftExtensions
import SwiftParser
@_spi(SourceKitLSP) import SwiftRefactor
import SwiftSyntax

/// Data that is attached to a `CompletionItem`.
private struct CompletionItemData: LSPAnyCodable {
  let id: Int?

  init(id: Int?) {
    self.id = id
  }

  init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    if case .int(let id) = dictionary["id"] {
      self.id = id
    } else {
      self.id = nil
    }
  }

  func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [:]
    if let id {
      dict["id"] = .int(id)
    }
    return .dictionary(dict)
  }
}

/// Represents a code-completion session for a given source location that can be efficiently
/// re-filtered by calling `update()`.
///
/// The first call to `update()` opens the session with sourcekitd, which computes the initial
/// completions. Subsequent calls to `update()` will re-filter the original completions. Finally,
/// before creating a new completion session, you must call `close()`. It is an error to create a
/// new completion session with the same source location before closing the original session.
///
/// At the sourcekitd level, this uses `codecomplete.open`, `codecomplete.update` and
/// `codecomplete.close` requests.
class CodeCompletionSession {
  // MARK: - Public static API

  /// The queue on which all code completion requests are executed.
  ///
  /// This is needed because sourcekitd has a single, global code completion
  /// session and we need to make sure that multiple code completion requests
  /// don't race each other.
  ///
  /// Technically, we would only need one queue for each sourcekitd and different
  /// sourcekitd could serve code completion requests simultaneously.
  ///
  /// But it's rare to open multiple sourcekitd instances simultaneously and
  /// even rarer to interact with them at the same time, so we have a global
  /// queue for now to simplify the implementation.
  private static let completionQueue = AsyncQueue<Serial>()

  /// The code completion session for each sourcekitd instance.
  ///
  /// `sourcekitd` has a global code completion session, that's why we need to
  /// have a global mapping from `sourcekitd` to its currently active code
  /// completion session.
  ///
  /// - Important: Must only be accessed on `completionQueue`.
  /// `nonisolated(unsafe)` fine because this is guarded by `completionQueue`.
  private static nonisolated(unsafe) var completionSessions: [ObjectIdentifier: CodeCompletionSession] = [:]

  /// Gets the code completion results for the given parameters.
  ///
  /// If a code completion session that is compatible with the parameters
  /// already exists, this just performs an update to the filtering. If it does
  /// not, this opens a new code completion session with `sourcekitd` and gets
  /// the results.
  ///
  /// - Parameters:
  ///   - sourcekitd: The `sourcekitd` instance from which to get code
  ///     completion results
  ///   - snapshot: The document in which to perform completion.
  ///   - completionPosition: The position at which to perform completion.
  ///     This is the position at which the code completion token logically
  ///     starts. For example when completing `foo.ba|`, then the completion
  ///     position should be after the `.`.
  ///   - completionUtf8Offset: Same as `completionPosition` but as a UTF-8
  ///     offset within the buffer.
  ///   - cursorPosition: The position at which the cursor is positioned. E.g.
  ///     when completing `foo.ba|`, this is after the `a` (see
  ///     `completionPosition` for comparison)
  ///   - compileCommand: The compiler arguments to use.
  ///   - options: Further options that can be sent from the editor to control
  ///     completion.
  ///   - clientSupportsSnippets: Whether the editor supports LSP snippets.
  ///   - filterText: The text by which to filter code completion results.
  ///   - mustReuse: If `true` and there is an active session in this
  ///     `sourcekitd` instance, cancel the request instead of opening a new
  ///     session.
  ///     This is set to `true` when triggering a filter from incomplete results
  ///     so that clients can rely on results being delivered quickly when
  ///     getting updated results after updating the filter text.
  /// - Returns: The code completion results for those parameters.
  static func completionList(
    sourcekitd: any SourceKitD,
    snapshot: DocumentSnapshot,
    options: SourceKitLSPOptions,
    indentationWidth: Trivia?,
    completionPosition: Position,
    cursorPosition: Position,
    compileCommand: SwiftCompileCommand?,
    clientSupportsSnippets: Bool,
    filterText: String
  ) async throws -> CompletionList {
    let task = completionQueue.asyncThrowing {
      if let session = completionSessions[ObjectIdentifier(sourcekitd)], session.state == .open {
        let isCompatible =
          session.snapshot.uri == snapshot.uri
          && session.position == completionPosition
          && session.compileCommand == compileCommand
          && session.clientSupportsSnippets == clientSupportsSnippets

        if isCompatible {
          return try await session.update(
            filterText: filterText,
            position: cursorPosition,
            in: snapshot
          )
        }

        // The sessions aren't compatible. Close the existing session and open
        // a new one below.
        await session.close()
      }
      let session = CodeCompletionSession(
        sourcekitd: sourcekitd,
        snapshot: snapshot,
        options: options,
        indentationWidth: indentationWidth,
        position: completionPosition,
        compileCommand: compileCommand,
        clientSupportsSnippets: clientSupportsSnippets
      )
      completionSessions[ObjectIdentifier(sourcekitd)] = session
      return try await session.open(filterText: filterText, position: cursorPosition, in: snapshot)
    }

    return try await task.valuePropagatingCancellation
  }

  /// Close all code completion sessions for the given files.
  ///
  /// This should only be necessary to do if the dependencies have updated. In all other cases `completionList` will
  /// decide whether an existing code completion session can be reused.
  static func close(sourcekitd: any SourceKitD, uris: Set<DocumentURI>) {
    completionQueue.async {
      if let session = completionSessions[ObjectIdentifier(sourcekitd)], uris.contains(session.uri),
        session.state == .open
      {
        await session.close()
      }
    }
  }

  // MARK: - Implementation

  private let sourcekitd: any SourceKitD
  private let snapshot: DocumentSnapshot
  private let options: SourceKitLSPOptions
  /// The inferred indentation width of the source file the completion is being performed in
  private let indentationWidth: Trivia?
  private let position: Position
  private let compileCommand: SwiftCompileCommand?
  private let clientSupportsSnippets: Bool
  private var state: State = .closed

  private enum State {
    case closed
    case open
  }

  private nonisolated var uri: DocumentURI { snapshot.uri }
  private nonisolated var keys: sourcekitd_api_keys { return sourcekitd.keys }

  private init(
    sourcekitd: any SourceKitD,
    snapshot: DocumentSnapshot,
    options: SourceKitLSPOptions,
    indentationWidth: Trivia?,
    position: Position,
    compileCommand: SwiftCompileCommand?,
    clientSupportsSnippets: Bool
  ) {
    self.sourcekitd = sourcekitd
    self.options = options
    self.indentationWidth = indentationWidth
    self.snapshot = snapshot
    self.position = position
    self.compileCommand = compileCommand
    self.clientSupportsSnippets = clientSupportsSnippets
  }

  private func open(
    filterText: String,
    position cursorPosition: Position,
    in snapshot: DocumentSnapshot
  ) async throws -> CompletionList {
    logger.info("Opening code completion session: \(self.description) filter=\(filterText)")
    guard snapshot.version == self.snapshot.version else {
      throw ResponseError(code: .invalidRequest, message: "open must use the original snapshot")
    }

    let sourcekitdPosition = snapshot.sourcekitdPosition(of: self.position)
    let req = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.codeCompleteOpen,
      keys.line: sourcekitdPosition.line,
      keys.column: sourcekitdPosition.utf8Column,
      keys.name: uri.pseudoPath,
      keys.sourceFile: uri.pseudoPath,
      keys.sourceText: snapshot.text,
      keys.codeCompleteOptions: optionsDictionary(filterText: filterText),
    ])

    let dict = try await sourcekitd.send(
      req,
      timeout: options.sourcekitdRequestTimeoutOrDefault,
      fileContents: snapshot.text
    )
    self.state = .open

    guard let completions: SKDResponseArray = dict[keys.results] else {
      return CompletionList(isIncomplete: false, items: [])
    }

    try Task.checkCancellation()

    return await self.completionsFromSKDResponse(
      completions,
      in: snapshot,
      completionPos: self.position,
      requestPosition: cursorPosition,
      isIncomplete: true
    )
  }

  private func update(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot
  ) async throws -> CompletionList {
    logger.info("Updating code completion session: \(self.description) filter=\(filterText)")
    let sourcekitdPosition = snapshot.sourcekitdPosition(of: self.position)
    let req = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.codeCompleteUpdate,
      keys.line: sourcekitdPosition.line,
      keys.column: sourcekitdPosition.utf8Column,
      keys.name: uri.pseudoPath,
      keys.sourceFile: uri.pseudoPath,
      keys.codeCompleteOptions: optionsDictionary(filterText: filterText),
    ])

    let dict = try await sourcekitd.send(
      req,
      timeout: options.sourcekitdRequestTimeoutOrDefault,
      fileContents: snapshot.text
    )
    guard let completions: SKDResponseArray = dict[keys.results] else {
      return CompletionList(isIncomplete: false, items: [])
    }

    return await self.completionsFromSKDResponse(
      completions,
      in: snapshot,
      completionPos: self.position,
      requestPosition: position,
      isIncomplete: true
    )
  }

  private func optionsDictionary(
    filterText: String
  ) -> SKDRequestDictionary {
    let dict = sourcekitd.dictionary([
      // Sorting and priority options.
      keys.hideUnderscores: 0,
      keys.hideLowPriority: 0,
      keys.hideByName: 0,
      keys.addInnerOperators: 0,
      keys.topNonLiteral: 0,
      // Filtering options.
      keys.filterText: filterText,
      keys.requestLimit: 200,
      keys.useNewAPI: 1,
    ])
    return dict
  }

  private func close() async {
    switch self.state {
    case .closed:
      // Already closed, nothing to do.
      break
    case .open:
      let sourcekitdPosition = snapshot.sourcekitdPosition(of: self.position)
      let req = sourcekitd.dictionary([
        keys.request: sourcekitd.requests.codeCompleteClose,
        keys.line: sourcekitdPosition.line,
        keys.column: sourcekitdPosition.utf8Column,
        keys.sourceFile: snapshot.uri.pseudoPath,
        keys.name: snapshot.uri.pseudoPath,
      ])
      logger.info("Closing code completion session: \(self.description)")
      _ = try? await sourcekitd.send(req, timeout: options.sourcekitdRequestTimeoutOrDefault, fileContents: nil)
      self.state = .closed
    }
  }

  // MARK: - Helpers

  private func expandClosurePlaceholders(insertText: String) -> String? {
    guard insertText.contains("<#") && insertText.contains("->") else {
      // Fast path: There is no closure placeholder to expand
      return nil
    }

    let strippedPrefix: String
    let exprToExpand: String
    if insertText.starts(with: "?.") {
      strippedPrefix = "?."
      exprToExpand = String(insertText.dropFirst(2))
    } else {
      strippedPrefix = ""
      exprToExpand = insertText
    }

    var parser = Parser(exprToExpand)
    let expr = ExprSyntax.parse(from: &parser)
    guard let call = OutermostFunctionCallFinder.findOutermostFunctionCall(in: expr),
      let expandedCall = ExpandEditorPlaceholdersToLiteralClosures.refactor(
        syntax: call,
        in: ExpandEditorPlaceholdersToLiteralClosures.Context(
          format: .custom(
            ClosureCompletionFormat(indentationWidth: indentationWidth),
            allowNestedPlaceholders: true
          )
        )
      )
    else {
      return nil
    }

    let bytesToExpand = Array(exprToExpand.utf8)

    var expandedBytes: [UInt8] = []
    // Add the prefix that we stripped off to allow expression parsing
    expandedBytes += strippedPrefix.utf8
    // Add any part of the expression that didn't end up being part of the function call
    expandedBytes += bytesToExpand[0..<call.position.utf8Offset]
    // Add the expanded function call excluding the added `indentationOfLine`
    expandedBytes += expandedCall.syntaxTextBytes
    // Add any trailing text that didn't end up being part of the function call
    expandedBytes += bytesToExpand[call.endPosition.utf8Offset...]
    return String(bytes: expandedBytes, encoding: .utf8)
  }

  private func completionsFromSKDResponse(
    _ completions: SKDResponseArray,
    in snapshot: DocumentSnapshot,
    completionPos: Position,
    requestPosition: Position,
    isIncomplete: Bool
  ) async -> CompletionList {
    let sourcekitd = self.sourcekitd
    let keys = sourcekitd.keys

    let completionItems = completions.compactMap { (value: SKDResponseDictionary) -> CompletionItem? in
      guard let name: String = value[keys.description],
        var insertText: String = value[keys.sourceText]
      else {
        return nil
      }

      var filterName: String? = value[keys.name]
      let typeName: String? = value[sourcekitd.keys.typeName]
      let utf8CodeUnitsToErase: Int = value[sourcekitd.keys.numBytesToErase] ?? 0

      if let closureExpanded = expandClosurePlaceholders(insertText: insertText) {
        insertText = closureExpanded
      }

      let text = rewriteSourceKitPlaceholders(in: insertText, clientSupportsSnippets: clientSupportsSnippets)
      let isInsertTextSnippet = clientSupportsSnippets && text != insertText

      let textEdit: TextEdit?
      let edit = self.computeCompletionTextEdit(
        completionPos: completionPos,
        requestPosition: requestPosition,
        utf8CodeUnitsToErase: utf8CodeUnitsToErase,
        newText: text,
        snapshot: snapshot
      )
      textEdit = edit

      if utf8CodeUnitsToErase != 0, filterName != nil, let textEdit = textEdit {
        // To support the case where the client is doing prefix matching on the TextEdit range,
        // we need to prepend the deleted text to filterText.
        // This also works around a behaviour in VS Code that causes completions to not show up
        // if a '.' is being replaced for Optional completion.
        let filterPrefix = snapshot.text[snapshot.indexRange(of: textEdit.range.lowerBound..<completionPos)]
        filterName = filterPrefix + filterName!
      }

      // Map SourceKit's not_recommended field to LSP's deprecated
      let notRecommended = (value[sourcekitd.keys.notRecommended] ?? 0) != 0

      let sortText: String?
      if let semanticScore: Double = value[sourcekitd.keys.semanticScore],
        let textMatchScore: Double = value[sourcekitd.keys.textMatchScore]
      {
        let score = semanticScore * textMatchScore
        // sourcekitd returns numeric completion item scores with a higher score being better. LSP's sort text is
        // lexicographical. Map the numeric score to a lexicographically sortable score by subtracting it from 5_000.
        // This gives us a valid range of semantic scores from -5_000 to 5_000 that can be sorted correctly
        // lexicographically. This should be sufficient as semantic scores are typically single-digit.
        var lexicallySortableScore = 5_000 - score
        if lexicallySortableScore < 0 {
          logger.fault(
            "score out-of-bounds: \(score, privacy: .public), semantic: \(semanticScore, privacy: .public), textual: \(textMatchScore, privacy: .public)"
          )
          lexicallySortableScore = 0
        }
        if lexicallySortableScore >= 10_000 {
          logger.fault(
            "score out-of-bounds: \(score, privacy: .public), semantic: \(semanticScore, privacy: .public), textual: \(textMatchScore, privacy: .public)"
          )
          lexicallySortableScore = 9_999.99999999
        }
        sortText = String(format: "%013.8f", lexicallySortableScore) + "-\(name)"
      } else {
        sortText = nil
      }

      let data = CompletionItemData(id: value[keys.identifier] as Int?)

      let kind: sourcekitd_api_uid_t? = value[sourcekitd.keys.kind]
      return CompletionItem(
        label: name,
        kind: kind?.asCompletionItemKind(sourcekitd.values) ?? .value,
        detail: typeName,
        documentation: nil,
        deprecated: notRecommended,
        sortText: sortText,
        filterText: filterName,
        insertText: text,
        insertTextFormat: isInsertTextSnippet ? .snippet : .plain,
        textEdit: textEdit.map(CompletionItemEdit.textEdit),
        data: data.encodeToLSPAny()
      )
    }

    // TODO: Only compute documentation if the client doesn't support `completionItem/resolve`
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1935)
    let withDocumentation = await completionItems.asyncMap { item in
      var item = item

      if let itemId = CompletionItemData(fromLSPAny: item.data)?.id {
        let req = sourcekitd.dictionary([
          keys.request: sourcekitd.requests.codeCompleteDocumentation,
          keys.identifier: itemId,
        ])
        let documentationResponse = try? await sourcekitd.send(req, timeout: .seconds(1), fileContents: snapshot.text)
        if let docString: String = documentationResponse?[keys.docBrief] {
          item.documentation = .markupContent(MarkupContent(kind: .markdown, value: docString))
        }
      }

      return item
    }

    return CompletionList(isIncomplete: isIncomplete, items: withDocumentation)
  }

  private func computeCompletionTextEdit(
    completionPos: Position,
    requestPosition: Position,
    utf8CodeUnitsToErase: Int,
    newText: String,
    snapshot: DocumentSnapshot
  ) -> TextEdit {
    let textEditRangeStart = computeCompletionTextEditStart(
      completionPos: completionPos,
      requestPosition: requestPosition,
      utf8CodeUnitsToErase: utf8CodeUnitsToErase,
      snapshot: snapshot
    )
    return TextEdit(range: textEditRangeStart..<requestPosition, newText: newText)
  }

  private func computeCompletionTextEditStart(
    completionPos: Position,
    requestPosition: Position,
    utf8CodeUnitsToErase: Int,
    snapshot: DocumentSnapshot
  ) -> Position {
    // Compute the TextEdit
    if utf8CodeUnitsToErase == 0 {
      // Nothing to delete. Fast path and avoid UTF-8/UTF-16 conversions
      return completionPos
    } else if utf8CodeUnitsToErase == 1 {
      // Fast path: Erasing a single UTF-8 byte code unit means we are also need to erase exactly one UTF-16 code unit, meaning we don't need to process the file contents
      if completionPos.utf16index >= 1 {
        // We can delete the character.
        return Position(line: completionPos.line, utf16index: completionPos.utf16index - 1)
      } else {
        // Deleting the character would cross line boundaries. This is not supported by LSP.
        // Fall back to ignoring utf8CodeUnitsToErase.
        // If we discover that multi-lines replacements are often needed, we can add an LSP extension to support multi-line edits.
        return completionPos
      }
    }

    // We need to delete more than one text character. Do the UTF-8/UTF-16 dance.
    assert(completionPos.line == requestPosition.line)
    // Construct a string index for the edit range start by subtracting the UTF-8 code units to erase from the completion position.
    guard let line = snapshot.lineTable.line(at: completionPos.line) else {
      logger.fault("Code completion position is in out-of-range line \(completionPos.line)")
      return completionPos
    }
    guard
      let deletionStartStringIndex = line.utf8.index(
        snapshot.index(of: completionPos),
        offsetBy: -utf8CodeUnitsToErase,
        limitedBy: line.utf8.startIndex
      )
    else {
      // Deleting the character would cross line boundaries. This is not supported by LSP.
      // Fall back to ignoring utf8CodeUnitsToErase.
      // If we discover that multi-lines replacements are often needed, we can add an LSP extension to support multi-line edits.
      logger.fault("UTF-8 code units to erase \(utf8CodeUnitsToErase) is before start of line")
      return completionPos
    }

    // Compute the UTF-16 offset of the deletion start range.
    let deletionStartUtf16Offset = line.utf16.distance(from: line.startIndex, to: deletionStartStringIndex)
    precondition(deletionStartUtf16Offset >= 0)

    return Position(line: completionPos.line, utf16index: deletionStartUtf16Offset)
  }
}

extension CodeCompletionSession: CustomStringConvertible {
  nonisolated var description: String {
    "\(uri.pseudoPath):\(position)"
  }
}

fileprivate class OutermostFunctionCallFinder: SyntaxAnyVisitor {
  /// Once a `FunctionCallExprSyntax` has been visited, that syntax node.
  var foundCall: FunctionCallExprSyntax?

  private func shouldVisit(_ node: some SyntaxProtocol) -> Bool {
    if foundCall != nil {
      return false
    }
    return true
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    guard shouldVisit(node) else {
      return .skipChildren
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard shouldVisit(node) else {
      return .skipChildren
    }
    foundCall = node
    return .skipChildren
  }

  /// Find the innermost `FunctionCallExprSyntax` that contains `position`.
  static func findOutermostFunctionCall(
    in tree: some SyntaxProtocol
  ) -> FunctionCallExprSyntax? {
    let finder = OutermostFunctionCallFinder(viewMode: .sourceAccurate)
    finder.walk(tree)
    return finder.foundCall
  }
}
