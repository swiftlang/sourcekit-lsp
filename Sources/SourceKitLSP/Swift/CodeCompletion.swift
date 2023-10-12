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

import Foundation
import LSPLogging
import LanguageServerProtocol
import SourceKitD

extension SwiftLanguageServer {

  public func completion(_ req: CompletionRequest) async throws -> CompletionList {
    guard let snapshot = documentManager.latestSnapshot(req.textDocument.uri) else {
      logger.error("failed to find snapshot for url \(req.textDocument.uri.forLogging)")
      return CompletionList(isIncomplete: true, items: [])
    }

    guard let completionPos = adjustCompletionLocation(req.position, in: snapshot) else {
      logger.error("invalid completion position \(req.position, privacy: .public)")
      return CompletionList(isIncomplete: true, items: [])
    }

    guard let offset = snapshot.utf8Offset(of: completionPos) else {
      logger.error(
        "invalid completion position \(req.position, privacy: .public) (adjusted: \(completionPos, privacy: .public)"
      )
      return CompletionList(isIncomplete: true, items: [])
    }

    let options = req.sourcekitlspOptions ?? serverOptions.completionOptions

    return try await completionWithServerFiltering(
      offset: offset,
      completionPos: completionPos,
      snapshot: snapshot,
      request: req,
      options: options
    )
  }

  private func completionWithServerFiltering(
    offset: Int,
    completionPos: Position,
    snapshot: DocumentSnapshot,
    request req: CompletionRequest,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    guard let start = snapshot.indexOf(utf8Offset: offset),
      let end = snapshot.index(of: req.position)
    else {
      logger.error("invalid completion position \(req.position, privacy: .public)")
      return CompletionList(isIncomplete: true, items: [])
    }

    let filterText = String(snapshot.text[start..<end])

    let session: CodeCompletionSession
    if req.context?.triggerKind == .triggerFromIncompleteCompletions {
      guard let currentSession = currentCompletionSession else {
        logger.error("triggerFromIncompleteCompletions with no existing completion session")
        throw ResponseError.serverCancelled
      }
      guard currentSession.uri == snapshot.uri, currentSession.utf8StartOffset == offset else {
        logger.error(
          """
            triggerFromIncompleteCompletions with incompatible completion session; expected \
            \(currentSession.uri.forLogging)@\(currentSession.utf8StartOffset), \
            but got \(snapshot.uri.forLogging)@\(offset)
          """
        )
        throw ResponseError.serverCancelled
      }
      session = currentSession
    } else {
      // FIXME: even if trigger kind is not from incomplete, we could to detect a compatible
      // location if we also check that the rest of the snapshot has not changed.
      session = CodeCompletionSession(
        server: self,
        snapshot: snapshot,
        utf8Offset: offset,
        position: completionPos,
        compileCommand: await buildSettings(for: snapshot.uri)
      )

      await currentCompletionSession?.close()
      currentCompletionSession = session
    }

    return try await session.update(filterText: filterText, position: req.position, in: snapshot, options: options)
  }

   /// Adjust completion position to the start of identifier characters.
  private func adjustCompletionLocation(_ pos: Position, in snapshot: DocumentSnapshot) -> Position? {
    guard pos.line < snapshot.lineTable.count else {
      // Line out of range.
      return nil
    }
    let lineSlice = snapshot.lineTable[pos.line]
    let startIndex = lineSlice.startIndex

    let identifierChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    guard var loc = lineSlice.utf16.index(startIndex, offsetBy: pos.utf16index, limitedBy: lineSlice.endIndex) else {
      // Column out of range.
      return nil
    }
    while loc != startIndex {
      let prev = lineSlice.index(before: loc)
      if !identifierChars.contains(lineSlice.unicodeScalars[prev]) {
        break
      }
      loc = prev
    }

    // ###aabccccccdddddd
    // ^  ^- loc  ^-requestedLoc
    // `- startIndex

    let adjustedOffset = lineSlice.utf16.distance(from: startIndex, to: loc)
    return Position(line: pos.line, utf16index: adjustedOffset)
  }
}
