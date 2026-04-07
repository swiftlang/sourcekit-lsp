//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKUtilities
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

package struct InlayHintResolveData: Codable, LSPAnyCodable {
  package let uri: DocumentURI
  package let position: Position
  package let version: Int

  package init(uri: DocumentURI, position: Position, version: Int) {
    self.uri = uri
    self.position = position
    self.version = version
  }
}

private struct InlayHintCacheEntry {
  let version: Int
  /// Marks hints as position-shifted but semantically stale; trigger a background recompute before treating cache as fully fresh.
  let needsSemanticRefresh: Bool
  /// The cached hints, sorted ascending by their position in the document.
  let hints: [InlayHint]
}

private struct InFlightInlayHintRefreshTask {
  let id: UUID
  let expectedVersion: Int
  let task: Task<(), any Error>
  var sendRefreshRequest: Bool
}

actor InlayHintManager {
  /// Cached inlay hints for each document.
  ///
  /// Each entry stores hints for the full document and the document version they were computed for.
  /// - Note: The capacity has been chosen without scientific measurements. 20 seems like a resonable number of open documents a client may have.
  private var cache = LRUCache<DocumentURI, InlayHintCacheEntry>(capacity: 20)

  /// Documents that currently have a background inlay-hint recomputation in progress.
  ///
  /// Used to avoid scheduling multiple concurrent recomputations for the same document.
  private var inFlightRefreshTasks: [DocumentURI: InFlightInlayHintRefreshTask] = [:]

  func getCachedInlayHints(
    swiftLanguageService service: SwiftLanguageService,
    for snapshot: DocumentSnapshot,
    range: Range<Position>?
  ) -> [InlayHint]? {
    guard let entry = cache[snapshot.uri] else {
      scheduleInlayHintRefresh(swiftLanguageService: service, for: snapshot)
      return nil
    }

    if entry.version != snapshot.version || entry.needsSemanticRefresh {
      // The cached hints are stale. Schedule a refresh and return the stale hints for now. The stale hints are still in the correct position they may just contain outdated type information.
      scheduleInlayHintRefresh(swiftLanguageService: service, for: snapshot)
    }

    return filterInlayHints(entry.hints, in: range)
  }

  private func filterInlayHints(_ hints: [InlayHint], in range: Range<Position>?) -> [InlayHint] {
    guard let range else {
      return hints
    }

    let lowerBoundIndex = hints.binarySearchFirst(where: { $0.position >= range.lowerBound })
    let upperBoundIndex = hints.binarySearchFirst(where: { $0.position >= range.upperBound })
    return Array(hints[lowerBoundIndex..<upperBoundIndex])
  }

  func processEdits(
    for uri: DocumentURI,
    contentChanges: [TextDocumentContentChangeEvent],
    swiftLanguageService service: SwiftLanguageService,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot
  ) {
    // Immediately schedule a refresh of the inlay hints using SourceKit, but don't send a `workspace/inlayHint/refresh`
    // request to the client.
    // If the time between the client sending `textDocument/didChange` and `textDocument/inlayHint` is longer than the
    // time taken to recompute the inlay hints, we have them available immediately when the client requests inlay hints.
    scheduleInlayHintRefresh(swiftLanguageService: service, for: postEditSnapshot, sendRefreshRequest: false)

    guard let cachedEntry = cache[uri] else {
      return
    }

    var currentHints = cachedEntry.hints
    for change in contentChanges {
      guard let range = change.range else {
        // Full document replacement. Invalidate all cached hints for the document, since we don't know how to shift them.
        cache[uri] = nil
        return
      }

      let lineDelta = change.text.count(where: \.isNewline) - (range.upperBound.line - range.lowerBound.line)
      let columnDelta =
        if let lastNewlineIndex = change.text.lastIndex(where: \.isNewline) {
          change.text.utf16.distance(from: change.text.index(after: lastNewlineIndex), to: change.text.endIndex)
        } else {
          change.text.utf16.count
        }

      func shiftedPosition(_ position: Position) -> Position {
        let newUtf16Index =
          if position.line == range.upperBound.line {
            if lineDelta > 0 {
              // The line does change, we thus have to calculate the offset of the hint in the new line
              // This offset has the length of all characters added by the edit after the newline (columnDelta)
              // + the length of the text between the end of the edit and the start of the hint
              columnDelta + position.utf16index - range.upperBound.utf16index
            } else {
              // The line does not change, just add the column delta
              position.utf16index + columnDelta
            }
          } else {
            // The hint is on a different line than the edit, the column doesn't change
            position.utf16index
          }
        return Position(line: position.line + lineDelta, utf16index: newUtf16Index)
      }

      let previousHints = currentHints
      currentHints = []
      let lowerBoundIndex = previousHints.binarySearchFirst(where: { $0.position >= range.lowerBound })
      let upperBoundIndex = previousHints.binarySearchFirst(where: { $0.position >= range.upperBound })

      // Hints before the edit range are unaffected.
      currentHints.append(contentsOf: previousHints[..<lowerBoundIndex])
      // Hints that overlap with the edit range are dropped and will be recomputed in the background.
      // Hints after the edit range need to be shifted by the edit delta.
      let shiftedHints: [InlayHint] = previousHints[upperBoundIndex...].compactMap { hint in
        if hint.position == range.lowerBound,
          hint.position == range.upperBound,
          hint.labelAsString == change.text
        {
          // This change inserts this inlay hint, so we remove the inlay hint
          return nil
        }

        let newPosition = shiftedPosition(hint.position)

        let newTextEdits = hint.textEdits?.map { textEdit in
          return TextEdit(
            range: shiftedPosition(textEdit.range.lowerBound)..<shiftedPosition(textEdit.range.upperBound),
            newText: textEdit.newText
          )
        }

        return InlayHint(
          position: newPosition,
          label: hint.label,
          kind: hint.kind,
          textEdits: newTextEdits,
          tooltip: hint.tooltip,
          paddingLeft: hint.paddingLeft,
          paddingRight: hint.paddingRight,
          data: hint.data
        )
      }
      currentHints.append(contentsOf: shiftedHints)
    }

    cache[uri] = InlayHintCacheEntry(version: postEditSnapshot.version, needsSemanticRefresh: true, hints: currentHints)
  }

  func scheduleInlayHintRefresh(
    swiftLanguageService service: SwiftLanguageService,
    for snapshot: DocumentSnapshot,
    sendRefreshRequest: Bool = true
  ) {
    let uri = snapshot.uri
    if var inFlightTask = inFlightRefreshTasks[uri] {
      if inFlightTask.expectedVersion >= snapshot.version {
        // We already have a task running for a newer version of the document, so we don't need to schedule another one.
        // But we may have to update the `sendRefreshRequest` property, if the already running task did not need a refresh but the new one does
        inFlightTask.sendRefreshRequest = inFlightTask.sendRefreshRequest || sendRefreshRequest
        inFlightRefreshTasks[uri] = inFlightTask
        return
      }
      // Cancel the currently running task for the older version of the document, since we will schedule a new one for the newer version below.
      inFlightTask.task.cancel()
    }

    let taskID = UUID()
    let task = Task(priority: .medium) { [self, service] in
      try await run {
        do {
          try Task.checkCancellation()

          // We recompute inlay hints for the whole document, even if only a range was requested. This is because edits
          // can affect the validity of inlay hints outside of their edit range (e.g., an edit that changes a variable's
          // type can make type hints for all other variables that use the edited variable stale). Caching and returning
          // inlay hints for only a subrange of the document would add a lot of complexity, because we would need to track
          // which hints are valid for which ranges and versions.
          let updatedHints = try await computeTypeInlayHints(swiftLanguageService: service, for: snapshot, range: nil)

          try Task.checkCancellation()

          let updatedEntry = InlayHintCacheEntry(
            version: snapshot.version,
            needsSemanticRefresh: false,
            hints: updatedHints
          )
          cache[uri] = updatedEntry

          guard let inFlightTask = inFlightRefreshTasks[uri], inFlightTask.id == taskID else {
            return
          }

          if inFlightTask.sendRefreshRequest {
            let _ = try await service.sourceKitLSPServer?.sendRequestToClient(InlayHintRefreshRequest())
          }
        } catch is CancellationError {
          return
        } catch {
          logger.error("Inlay hint refresh failed for \(uri.forLogging): \(error.forLogging)")
        }
      } cleanup: {
        guard let inFlightTask = inFlightRefreshTasks[uri], inFlightTask.id == taskID else {
          // This task was already replaced by another one so we should not remove the entry
          return
        }
        inFlightRefreshTasks[uri] = nil
      }
    }

    inFlightRefreshTasks[uri] = InFlightInlayHintRefreshTask(
      id: taskID,
      expectedVersion: snapshot.version,
      task: task,
      sendRefreshRequest: sendRefreshRequest
    )
  }

  func computeTypeInlayHints(
    swiftLanguageService service: SwiftLanguageService,
    for snapshot: DocumentSnapshot,
    range: Range<Position>?
  ) async throws -> [InlayHint] {
    let infos = try await service.variableTypeInfos(snapshot.uri, nil)
    return infos
      .lazy
      .filter { !$0.hasExplicitType }
      .map { info -> InlayHint in
        let position = info.range.upperBound
        let variableStart = info.range.lowerBound
        let label = ": \(info.printedType)"
        let textEdits: [TextEdit]?
        if info.canBeFollowedByTypeAnnotation {
          textEdits = [TextEdit(range: position..<position, newText: label)]
        } else {
          textEdits = nil
        }
        let resolveData = InlayHintResolveData(uri: snapshot.uri, position: variableStart, version: snapshot.version)
        return InlayHint(
          position: position,
          label: .string(label),
          kind: .type,
          textEdits: textEdits,
          data: resolveData.encodeToLSPAny()
        )
      }
      .sorted { $0.position < $1.position }
  }

  func removeCachedInlayHints(for uri: DocumentURI) {
    inFlightRefreshTasks.removeValue(forKey: uri)?.task.cancel()
    cache[uri] = nil
  }
}

private extension InlayHint {
  var labelAsString: String {
    switch self.label {
    case .string(let label):
      return label

    case .parts(let parts):
      return parts.map { $0.value }.joined()
    }
  }
}

private extension Array {
  func binarySearchFirst(where predicate: (Element) -> Bool) -> Int {
    var low = 0
    var high = self.count
    while low < high {
      let mid = (low + high) / 2
      if predicate(self[mid]) {
        high = mid
      } else {
        low = mid + 1
      }
    }
    return low
  }
}
