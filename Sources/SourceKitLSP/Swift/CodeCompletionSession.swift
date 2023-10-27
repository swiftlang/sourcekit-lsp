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
import SKSupport

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
  /// Modification of code completion sessions should only happen on
  /// `completionQueue`.
  private static var completionSessions: [ObjectIdentifier: CodeCompletionSession] = [:]
  
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
    completionPosition: Position,
    completionUtf8Offset: Int,
    cursorPosition: Position,
    compileCommand: SwiftCompileCommand?,
    options: SKCompletionOptions,
    clientSupportsSnippets: Bool,
    filterText: String,
    mustReuse: Bool
  ) async throws -> CompletionList {
    let task = completionQueue.asyncThrowing {
      if let session = completionSessions[ObjectIdentifier(sourcekitd)], session.state == .open {
        let isCompatible = session.snapshot.uri == snapshot.uri &&
        session.utf8StartOffset == completionUtf8Offset &&
        session.position == completionPosition &&
        session.compileCommand == compileCommand &&
        session.clientSupportsSnippets == clientSupportsSnippets

        if isCompatible {
          return try await session.update(filterText: filterText, position: cursorPosition, in: snapshot, options: options)
        }
        
        if mustReuse {
          logger.error(
            """
              triggerFromIncompleteCompletions with incompatible completion session; expected \
              \(session.uri.forLogging)@\(session.utf8StartOffset), \
              but got \(snapshot.uri.forLogging)@\(completionUtf8Offset)
            """
          )
          throw ResponseError.serverCancelled
        }
        // The sessions aren't compatible. Close the existing session and open
        // a new one below.
        await session.close()
      }
      if mustReuse {
        logger.error("triggerFromIncompleteCompletions with no existing completion session")
        throw ResponseError.serverCancelled
      }
      let session = CodeCompletionSession(
        sourcekitd: sourcekitd,
        snapshot: snapshot,
        utf8Offset: completionUtf8Offset,
        position: completionPosition,
        compileCommand: compileCommand,
        clientSupportsSnippets: clientSupportsSnippets
      )
      completionSessions[ObjectIdentifier(sourcekitd)] = session
      return try await session.open(filterText: filterText, position: cursorPosition, in: snapshot, options: options)
    }

    return try await task.valuePropagatingCancellation
  }

  // MARK: - Implementation

  private let sourcekitd: any SourceKitD
  private let snapshot: DocumentSnapshot
  private let utf8StartOffset: Int
  private let position: Position
  private let compileCommand: SwiftCompileCommand?
  private let clientSupportsSnippets: Bool
  private var state: State = .closed

  private enum State {
    case closed
    case open
  }

  private nonisolated var uri: DocumentURI { snapshot.uri }
  private nonisolated var keys: sourcekitd_keys { return sourcekitd.keys }

  private init(
    sourcekitd: any SourceKitD,
    snapshot: DocumentSnapshot,
    utf8Offset: Int,
    position: Position,
    compileCommand: SwiftCompileCommand?,
    clientSupportsSnippets: Bool
  ) {
    self.sourcekitd = sourcekitd
    self.snapshot = snapshot
    self.utf8StartOffset = utf8Offset
    self.position = position
    self.compileCommand = compileCommand
    self.clientSupportsSnippets = clientSupportsSnippets
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

    let req = SKDRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = sourcekitd.requests.codecomplete_open
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.sourcefile] = uri.pseudoPath
    req[keys.sourcetext] = snapshot.text
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)
    if let compileCommand = compileCommand {
      req[keys.compilerargs] = compileCommand.compilerArgs
    }

    let dict = try await sourcekitd.send(req)
    self.state = .open

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

  private func update(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    // FIXME: Assertion for prefix of snapshot matching what we started with.

    logger.info("Updating code completion session: \(self, privacy: .private) filter=\(filterText)")
    let req = SKDRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = sourcekitd.requests.codecomplete_update
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)

    let dict = try await sourcekitd.send(req)
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
    let dict = SKDRequestDictionary(sourcekitd: sourcekitd)
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

  private func close() async {
    switch self.state {
    case .closed:
      // Already closed, nothing to do.
      break
    case .open:
      let req = SKDRequestDictionary(sourcekitd: sourcekitd)
      req[keys.request] = sourcekitd.requests.codecomplete_close
      req[keys.offset] = self.utf8StartOffset
      req[keys.name] = self.snapshot.uri.pseudoPath
      logger.info("Closing code completion session: \(self, privacy: .private)")
      _ = try? await sourcekitd.send(req)
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

    completions.forEach { (i: Int, value: SKDResponseDictionary) -> Bool in
      guard let name: String = value[keys.description] else {
        return true  // continue
      }

      var filterName: String? = value[keys.name]
      let insertText: String? = value[keys.sourcetext]
      let typeName: String? = value[sourcekitd.keys.typename]
      let docBrief: String? = value[sourcekitd.keys.doc_brief]

      let text = insertText.map {
        rewriteSourceKitPlaceholders(inString: $0, clientSupportsSnippets: clientSupportsSnippets)
      }
      let isInsertTextSnippet = clientSupportsSnippets && text != insertText

      let textEdit: TextEdit?
      if let text = text {
        let utf8CodeUnitsToErase: Int = value[sourcekitd.keys.num_bytes_to_erase] ?? 0

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
      let notRecommended = (value[sourcekitd.keys.not_recommended] as Int?).map({ $0 != 0 })

      let kind: sourcekitd_uid_t? = value[sourcekitd.keys.kind]
      result.items.append(
        CompletionItem(
          label: name,
          kind: kind?.asCompletionItemKind(sourcekitd.values) ?? .value,
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
