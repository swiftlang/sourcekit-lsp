//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

struct InlayHintCacheEntry {
  let version: Int
  let hints: [InlayHint]
}

struct InFlightInlayHintRefreshTask {
  let id: UUID
  let expectedVersion: Int
  let task: Task<Void, any Error>
}

struct InlayHintState {
  /// Cached inlay hints for each document.
  ///
  /// Each entry stores hints for the full document and the document version they were computed for.
  var cache: [DocumentURI: InlayHintCacheEntry] = [:]

  /// Documents that currently have a background inlay-hint recomputation in progress.
  ///
  /// Used to avoid scheduling multiple concurrent recomputations for the same document.
  var inFlightRefreshTasks: [DocumentURI: InFlightInlayHintRefreshTask] = [:]

  mutating func clear(for uri: DocumentURI) {
    inFlightRefreshTasks.removeValue(forKey: uri)?.task.cancel()
    cache[uri] = nil
  }
}

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

private class IfConfigCollector: SyntaxVisitor {
  private var ifConfigDecls: [IfConfigDeclSyntax] = []
  private let range: Range<AbsolutePosition>?

  init(viewMode: SyntaxTreeViewMode, range: Range<AbsolutePosition>?) {
    self.range = range
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
    if let range, !range.overlaps(node.range) {
      return .skipChildren
    }
    ifConfigDecls.append(node)

    return .visitChildren
  }

  static func collectIfConfigDecls(
    in tree: some SyntaxProtocol,
    range: Range<AbsolutePosition>?
  ) -> [IfConfigDeclSyntax] {
    let visitor = IfConfigCollector(viewMode: .sourceAccurate, range: range)
    visitor.walk(tree)
    return visitor.ifConfigDecls
  }
}

struct ShiftedInlayHint {
  let inlayHint: InlayHint
  let position: AbsolutePosition
  let dataPosition: AbsolutePosition?
  let textEdits: [ShiftedTextEdit]

  func shiftBy(delta: SourceLength) -> ShiftedInlayHint {
    return ShiftedInlayHint(
      inlayHint: inlayHint,
      position: position + delta,
      dataPosition: dataPosition.map { $0 + delta },
      textEdits: textEdits.map { $0.shiftBy(delta: delta) }
    )
  }

  func toInlayHint(postEditSnapshot: DocumentSnapshot) -> InlayHint {
    return InlayHint(
      position: postEditSnapshot.position(of: position),
      label: inlayHint.label,
      kind: inlayHint.kind,
      textEdits: textEdits.map {
        TextEdit(range: postEditSnapshot.positionRange(of: $0.range), newText: $0.textEdit.newText)
      },
      tooltip: inlayHint.tooltip,
      paddingLeft: inlayHint.paddingLeft,
      paddingRight: inlayHint.paddingRight,
      data: {
        if let dataPosition,
          let resolveData = InlayHintResolveData(fromLSPAny: inlayHint.data)
        {
          let newResolveData = InlayHintResolveData(
            uri: resolveData.uri,
            position: postEditSnapshot.position(of: dataPosition),
            version: postEditSnapshot.version
          )
          return newResolveData.encodeToLSPAny()
        } else {
          return nil
        }
      }()
    )
  }
}

extension InlayHint {
  func toShifted(snapshot: DocumentSnapshot) -> ShiftedInlayHint {
    let dataPosition: AbsolutePosition? =
      if let resolveData = InlayHintResolveData(fromLSPAny: data) {
        snapshot.absolutePosition(of: resolveData.position)
      } else {
        nil
      }
    let textEdits =
      self.textEdits?.map { ShiftedTextEdit(textEdit: $0, range: snapshot.absolutePositionRange(of: $0.range)) } ?? []
    return ShiftedInlayHint(
      inlayHint: self,
      position: snapshot.absolutePosition(of: self.position),
      dataPosition: dataPosition,
      textEdits: textEdits
    )
  }
}

struct ShiftedTextEdit {
  let textEdit: TextEdit
  let range: Range<AbsolutePosition>

  func shiftBy(delta: SourceLength) -> ShiftedTextEdit {
    return ShiftedTextEdit(
      textEdit: textEdit,
      range: range.lowerBound + delta..<range.upperBound + delta
    )
  }
}

extension SwiftLanguageService {
  package func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    let uri = req.textDocument.uri
    let currentVersion = try await latestSnapshot(for: uri).version

    if let sourceKitLSPServer = self.sourceKitLSPServer,
      let clientCapabilities = await sourceKitLSPServer.capabilityRegistry?.clientCapabilities,
      !(clientCapabilities.workspace?.inlayHint?.refreshSupport ?? false)
    {
      // The client does not support workspace/inlayHint/refresh.
      // We have to compute inlay hints on every request, because we cannot trigger a refresh when the document changes.
      let snapshot = try await latestSnapshot(for: uri)
      return try await computeTypeInlayHints(for: uri, snapshot: snapshot, range: req.range)
        + computeIfConfigInlayHints(snapshot: snapshot, range: req.range)
    }

    if let cachedEntry = inlayHintState.cache[uri] {
      if cachedEntry.version != currentVersion {
        scheduleInlayHintRefresh(for: uri, expectedVersion: currentVersion)
      }
      let snapshot = try await latestSnapshot(for: uri)
      return try await filterInlayHints(cachedEntry.hints, in: req.range)
        + computeIfConfigInlayHints(snapshot: snapshot, range: req.range)
    }

    // No cached hints are available. Schedule a refresh for the current version and return no hints for now.
    // The client will trigger another request after the refresh completes, because of the InlayHintRefreshRequest sent in the refresh task.
    scheduleInlayHintRefresh(for: uri, expectedVersion: currentVersion)
    return []
  }

  func scheduleInlayHintRefresh(for uri: DocumentURI, expectedVersion: Int) {
    if let inFlightTask = inlayHintState.inFlightRefreshTasks[uri] {
      if inFlightTask.expectedVersion >= expectedVersion {
        return
      }
      inFlightTask.task.cancel()
    }

    let taskID = UUID()
    let task = Task(priority: .medium) { [weak self] in
      guard let self else {
        return
      }
      defer { Task { await self.finishInlayHintRefresh(for: uri, taskID: taskID) } }

      do {
        try Task.checkCancellation()

        let snapshot = try await self.latestSnapshot(for: uri)

        try Task.checkCancellation()

        // We recompute inlay hints for the whole document, even if only a range was requested. This is because edits
        // can affect the validity of inlay hints outside of their edit range (e.g., an edit that changes a variable's
        // type can make type hints for all other variables that use the edited variable stale). Caching and returning
        // inlay hints for only a subrange of the document would add a lot of complexity, because we would need to track
        // which hints are valid for which ranges and versions.
        let updatedHints = try await self.computeTypeInlayHints(for: uri, snapshot: snapshot, range: nil)

        try Task.checkCancellation()

        guard snapshot.version == expectedVersion else {
          return
        }

        let updatedEntry = InlayHintCacheEntry(version: snapshot.version, hints: updatedHints)
        await self.storeInlayHintCache(updatedEntry, for: uri)

        let _ = try await self.sourceKitLSPServer?.sendRequestToClient(InlayHintRefreshRequest())
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        logger.error("Inlay hint refresh failed for \(uri.forLogging): \(error.forLogging)")
        throw error
      }
    }

    inlayHintState.inFlightRefreshTasks[uri] = InFlightInlayHintRefreshTask(
      id: taskID,
      expectedVersion: expectedVersion,
      task: task
    )
  }

  private func finishInlayHintRefresh(for uri: DocumentURI, taskID: UUID) {
    guard let inFlightTask = inlayHintState.inFlightRefreshTasks[uri], inFlightTask.id == taskID else {
      return
    }
    inlayHintState.inFlightRefreshTasks[uri] = nil

    guard let latestVersion = try? documentManager.latestSnapshot(uri).version else {
      return
    }
    if latestVersion > inFlightTask.expectedVersion {
      scheduleInlayHintRefresh(for: uri, expectedVersion: latestVersion)
    }
  }

  private func storeInlayHintCache(_ entry: InlayHintCacheEntry, for uri: DocumentURI) {
    inlayHintState.cache[uri] = entry
  }

  private func computeTypeInlayHints(
    for uri: DocumentURI,
    snapshot: DocumentSnapshot,
    range: Range<Position>?
  ) async throws -> [InlayHint] {
    let infos = try await variableTypeInfos(uri, nil)
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
        let resolveData = InlayHintResolveData(uri: uri, position: variableStart, version: snapshot.version)
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

  private func computeIfConfigInlayHints(
    snapshot: DocumentSnapshot,
    range: Range<Position>?
  ) async throws -> [InlayHint] {
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let absoluteRange = range.map { snapshot.absolutePositionRange(of: $0) }
    let ifConfigDecls = IfConfigCollector.collectIfConfigDecls(in: syntaxTree, range: absoluteRange)
    return ifConfigDecls.compactMap { (ifConfigDecl) -> InlayHint? in
      // Do not show inlay hints for if config clauses that have a `#elseif` of `#else` clause since it is unclear which
      // `#if`, `#elseif`, or `#else` clause the `#endif` now refers to.
      guard let condition = ifConfigDecl.clauses.only?.condition else {
        return nil
      }
      guard !ifConfigDecl.poundEndif.trailingTrivia.contains(where: { $0.isComment }) else {
        // If a comment already exists (eg. because the user inserted it), don't show an inlay hint.
        return nil
      }
      let hintPosition = snapshot.position(of: ifConfigDecl.poundEndif.endPositionBeforeTrailingTrivia)
      let label = " // \(condition.trimmedDescription)"
      return InlayHint(
        position: hintPosition,
        label: .string(label),
        kind: .type,  // For the lack of a better kind, pretend this comment is a type
        textEdits: [TextEdit(range: Range(hintPosition), newText: label)],
        tooltip: .string("Condition of this conditional compilation clause")
      )
    }
  }

  private func filterInlayHints(_ hints: [InlayHint], in range: Range<Position>?) -> [InlayHint] {
    guard let range else {
      return hints
    }

    func binarySearchFirst(where predicate: (InlayHint) -> Bool) -> Int {
      var low = 0
      var high = hints.count
      while low < high {
        let mid = (low + high) / 2
        if predicate(hints[mid]) {
          high = mid
        } else {
          low = mid + 1
        }
      }
      return low
    }

    let lowerBoundIndex = binarySearchFirst(where: { $0.position >= range.lowerBound })
    let upperBoundIndex = binarySearchFirst(where: { $0.position >= range.upperBound })
    return Array(hints[lowerBoundIndex..<upperBoundIndex])
  }

  func shiftCachedInlayHints(
    for uri: DocumentURI,
    edits: [SourceEdit],
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot
  ) {
    guard let cachedEntry = inlayHintState.cache[uri] else {
      return
    }

    var currentHints = cachedEntry.hints.map { $0.toShifted(snapshot: preEditSnapshot) }
    for edit in edits {
      let delta = SourceLength(utf8Length: edit.replacement.utf8.count) - edit.range.length

      let previousHints = currentHints
      currentHints = []

      for hint in previousHints {
        if hint.position < edit.range.lowerBound {
          currentHints.append(hint)
        } else if edit.range.lowerBound <= hint.position && hint.position < edit.range.upperBound {
          // This hint is affected by the edit. We drop it, which will cause it to be recomputed in the next inlay hint refresh.
        } else {
          currentHints.append(hint.shiftBy(delta: delta))
        }
      }
    }

    let shiftedHints = currentHints.map { $0.toInlayHint(postEditSnapshot: postEditSnapshot) }

    inlayHintState.cache[uri] = InlayHintCacheEntry(version: postEditSnapshot.version, hints: shiftedHints)
  }
}
