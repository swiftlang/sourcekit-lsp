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

import Dispatch
import LSPLogging
import LanguageServerProtocol
import SourceKitD

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
actor CodeCompletionSession {
  private unowned let server: SwiftLanguageServer
  private let snapshot: DocumentSnapshot
  let utf8StartOffset: Int
  private let position: Position
  private let compileCommand: SwiftCompileCommand?
  private var state: State = .closed

  private enum State {
    case closed
    case open
  }

  nonisolated var uri: DocumentURI { snapshot.uri }

  init(
    server: SwiftLanguageServer,
    snapshot: DocumentSnapshot,
    utf8Offset: Int,
    position: Position,
    compileCommand: SwiftCompileCommand?
  ) {
    self.server = server
    self.snapshot = snapshot
    self.utf8StartOffset = utf8Offset
    self.position = position
    self.compileCommand = compileCommand
  }

  /// Retrieve completions for the given `filterText`, opening or updating the session.
  ///
  /// - parameters:
  ///   - filterText: The text to use for fuzzy matching the results.
  ///   - position: The position at the end of the existing text (typically right after the end of
  ///               `filterText`), which determines the end of the `TextEdit` replacement range
  ///               in the resulting completions.
  ///   - snapshot: The current snapshot that the `TextEdit` replacement in results will be in.
  ///   - options: The completion options, such as the maximum number of results.
  func update(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    switch self.state {
    case .closed:
      self.state = .open
      return try await self.open(filterText: filterText, position: position, in: snapshot, options: options)
    case .open:
      return try await self.updateImpl(filterText: filterText, position: position, in: snapshot, options: options)
    }
  }

  private func open(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    logger.info("Opening code completion session: \(self, privacy: .private) filter=\(filterText)")
    guard snapshot.version == self.snapshot.version else {
      throw ResponseError(code: .invalidRequest, message: "open must use the original snapshot")
    }

    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_open
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.sourcefile] = uri.pseudoPath
    req[keys.sourcetext] = snapshot.text
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)
    if let compileCommand = compileCommand {
      req[keys.compilerargs] = compileCommand.compilerArgs
    }

    let dict = try await server.sourcekitd.send(req)

    guard let completions: SKDResponseArray = dict[keys.results] else {
      return CompletionList(isIncomplete: false, items: [])
    }

    try Task.checkCancellation()

    return self.completionsFromSKDResponse(
      completions,
      in: snapshot,
      completionPos: self.position,
      requestPosition: position,
      isIncomplete: true
    )
  }

  private func updateImpl(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    // FIXME: Assertion for prefix of snapshot matching what we started with.

    logger.info("Updating code completion session: \(self, privacy: .private) filter=\(filterText)")
    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_update
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)

    let dict = try await server.sourcekitd.send(req)
    guard let completions: SKDResponseArray = dict[keys.results] else {
      return CompletionList(isIncomplete: false, items: [])
    }

    return self.completionsFromSKDResponse(
      completions,
      in: snapshot,
      completionPos: self.position,
      requestPosition: position,
      isIncomplete: true
    )
  }

  private func optionsDictionary(
    filterText: String,
    options: SKCompletionOptions
  ) -> SKDRequestDictionary {
    let dict = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    // Sorting and priority options.
    dict[keys.codecomplete_hideunderscores] = 0
    dict[keys.codecomplete_hidelowpriority] = 0
    dict[keys.codecomplete_hidebyname] = 0
    dict[keys.codecomplete_addinneroperators] = 0
    dict[keys.codecomplete_callpatternheuristics] = 0
    dict[keys.codecomplete_showtopnonliteralresults] = 0
    // Filtering options.
    dict[keys.codecomplete_filtertext] = filterText
    if let maxResults = options.maxResults {
      dict[keys.codecomplete_requestlimit] = maxResults
    }
    return dict
  }

  private func sendClose(_ server: SwiftLanguageServer) {
    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_close
    req[keys.offset] = self.utf8StartOffset
    req[keys.name] = self.snapshot.uri.pseudoPath
    logger.info("Closing code completion session: \(self, privacy: .private)")
    _ = try? server.sourcekitd.sendSync(req)
  }

  func close() async {
    // Temporary back-reference to server to keep it alive during close().
    let server = self.server

    switch self.state {
    case .closed:
      // Already closed, nothing to do.
      break
    case .open:
      self.sendClose(server)
      self.state = .closed
    }
  }

  // MARK: - Helpers

  private func completionsFromSKDResponse(
    _ completions: SKDResponseArray,
    in snapshot: DocumentSnapshot,
    completionPos: Position,
    requestPosition: Position,
    isIncomplete: Bool
  ) -> CompletionList {
    var result = CompletionList(isIncomplete: isIncomplete, items: [])

    completions.forEach { (i, value) -> Bool in
      guard let name: String = value[server.keys.description] else {
        return true  // continue
      }

      var filterName: String? = value[server.keys.name]
      let insertText: String? = value[server.keys.sourcetext]
      let typeName: String? = value[server.keys.typename]
      let docBrief: String? = value[server.keys.doc_brief]

      let completionCapabilities = server.capabilityRegistry.clientCapabilities.textDocument?.completion
      let clientSupportsSnippets = completionCapabilities?.completionItem?.snippetSupport == true
      let text = insertText.map {
        rewriteSourceKitPlaceholders(inString: $0, clientSupportsSnippets: clientSupportsSnippets)
      }
      let isInsertTextSnippet = clientSupportsSnippets && text != insertText

      let textEdit: TextEdit?
      if let text = text {
        let utf8CodeUnitsToErase: Int = value[server.keys.num_bytes_to_erase] ?? 0

        textEdit = self.computeCompletionTextEdit(
          completionPos: completionPos,
          requestPosition: requestPosition,
          utf8CodeUnitsToErase: utf8CodeUnitsToErase,
          newText: text,
          snapshot: snapshot
        )

        if utf8CodeUnitsToErase != 0, filterName != nil, let textEdit = textEdit {
          // To support the case where the client is doing prefix matching on the TextEdit range,
          // we need to prepend the deleted text to filterText.
          // This also works around a behaviour in VS Code that causes completions to not show up
          // if a '.' is being replaced for Optional completion.
          let startIndex = snapshot.lineTable.stringIndexOf(
            line: textEdit.range.lowerBound.line,
            utf16Column: textEdit.range.lowerBound.utf16index
          )!
          let endIndex = snapshot.lineTable.stringIndexOf(
            line: completionPos.line,
            utf16Column: completionPos.utf16index
          )!
          let filterPrefix = snapshot.text[startIndex..<endIndex]
          filterName = filterPrefix + filterName!
        }
      } else {
        textEdit = nil
      }

      // Map SourceKit's not_recommended field to LSP's deprecated
      let notRecommended = (value[server.keys.not_recommended] as Int?).map({ $0 != 0 })

      let kind: sourcekitd_uid_t? = value[server.keys.kind]
      result.items.append(
        CompletionItem(
          label: name,
          kind: kind?.asCompletionItemKind(server.values) ?? .value,
          detail: typeName,
          documentation: docBrief != nil ? .markupContent(MarkupContent(kind: .markdown, value: docBrief!)) : nil,
          deprecated: notRecommended ?? false,
          sortText: nil,
          filterText: filterName,
          insertText: text,
          insertTextFormat: isInsertTextSnippet ? .snippet : .plain,
          textEdit: textEdit.map(CompletionItemEdit.textEdit)
        )
      )

      return true
    }

    return result
  }

  private func computeCompletionTextEdit(
    completionPos: Position,
    requestPosition: Position,
    utf8CodeUnitsToErase: Int,
    newText: String,
    snapshot: DocumentSnapshot
  ) -> TextEdit {
    let textEditRangeStart: Position

    // Compute the TextEdit
    if utf8CodeUnitsToErase == 0 {
      // Nothing to delete. Fast path and avoid UTF-8/UTF-16 conversions
      textEditRangeStart = completionPos
    } else if utf8CodeUnitsToErase == 1 {
      // Fast path: Erasing a single UTF-8 byte code unit means we are also need to erase exactly one UTF-16 code unit, meaning we don't need to process the file contents
      if completionPos.utf16index >= 1 {
        // We can delete the character.
        textEditRangeStart = Position(line: completionPos.line, utf16index: completionPos.utf16index - 1)
      } else {
        // Deleting the character would cross line boundaries. This is not supported by LSP.
        // Fall back to ignoring utf8CodeUnitsToErase.
        // If we discover that multi-lines replacements are often needed, we can add an LSP extension to support multi-line edits.
        textEditRangeStart = completionPos
      }
    } else {
      // We need to delete more than one text character. Do the UTF-8/UTF-16 dance.
      assert(completionPos.line == requestPosition.line)
      // Construct a string index for the edit range start by subtracting the UTF-8 code units to erase from the completion position.
      let line = snapshot.lineTable[completionPos.line]
      let completionPosStringIndex = snapshot.lineTable.stringIndexOf(
        line: completionPos.line,
        utf16Column: completionPos.utf16index
      )!
      let deletionStartStringIndex = line.utf8.index(completionPosStringIndex, offsetBy: -utf8CodeUnitsToErase)

      // Compute the UTF-16 offset of the deletion start range. If the start lies in a previous line, this will be negative
      let deletionStartUtf16Offset = line.utf16.distance(from: line.startIndex, to: deletionStartStringIndex)

      // Check if we are only deleting on one line. LSP does not support deleting over multiple lines.
      if deletionStartUtf16Offset >= 0 {
        // We are only deleting characters on the same line. Construct the corresponding text edit.
        textEditRangeStart = Position(line: completionPos.line, utf16index: deletionStartUtf16Offset)
      } else {
        // Deleting the character would cross line boundaries. This is not supported by LSP.
        // Fall back to ignoring utf8CodeUnitsToErase.
        // If we discover that multi-lines replacements are often needed, we can add an LSP extension to support multi-line edits.
        textEditRangeStart = completionPos
      }
    }

    return TextEdit(range: textEditRangeStart..<requestPosition, newText: newText)
  }
}

extension CodeCompletionSession: CustomStringConvertible {
  nonisolated var description: String {
    "\(uri.pseudoPath):\(position)"
  }
}
