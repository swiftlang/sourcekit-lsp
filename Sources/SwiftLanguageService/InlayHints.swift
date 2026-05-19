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
import SKOptions
import SKUtilities
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

extension SwiftLanguageService {
  package func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    let uri = req.textDocument.uri
    let snapshot = try await latestSnapshot(for: uri)

    if let sourceKitLSPServer = self.sourceKitLSPServer,
      let clientCapabilities = await sourceKitLSPServer.capabilityRegistry?.clientCapabilities,
      !(clientCapabilities.workspace?.inlayHint?.refreshSupport ?? false)
    {
      // The client does not support workspace/inlayHint/refresh.
      // We have to compute inlay hints on every request, because we cannot trigger a refresh when the inlay hints have been recomputed in the background.
      let snapshot = try await latestSnapshot(for: uri)
      async let typeInlayHints = inlayHintManager.computeTypeInlayHints(
        swiftLanguageService: self,
        for: snapshot,
        range: req.range
      )
      return try await typeInlayHints
        + computeIfConfigInlayHints(snapshot: snapshot, range: req.range)
        + computeInferredIsolationInlayHints(snapshot: snapshot, range: req.range)
    }

    if let hints = await inlayHintManager.getCachedInlayHints(
      swiftLanguageService: self,
      for: snapshot,
      range: req.range
    ) {
      return try await hints
        + computeIfConfigInlayHints(snapshot: snapshot, range: req.range)
        + computeInferredIsolationInlayHints(snapshot: snapshot, range: req.range)
    }

    // No cached hints are available. The inlay hint manager has scheduled a refresh task if needed, so we can just
    // return an empty response here. The client will trigger another request after the refresh completes, because of
    // the InlayHintRefreshRequest sent in the refresh task.
    return []
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

  private func computeInferredIsolationInlayHints(
    snapshot: DocumentSnapshot,
    range: Range<Position>?
  ) async throws -> [InlayHint] {
    let inferredIsolationInlays: [InlayHint]
    if options.hasExperimentalFeature(.inferredClosureIsolationInlayHints) {
      // TODO: should we perform the request concurrently with others?
      let inferredIsolationResults = try await inferredIsolations(snapshot.uri, range)
      inferredIsolationInlays = inferredIsolationResults
        .lazy
        .filter { $0.kind == "closure" } // Only kind right now
        .map { info -> InlayHint in
          // Anchor the inlay right after the closure's opening brace.
          // TODO: is there a better way to do this?
          let offset = snapshot.utf8Offset(of: info.range.lowerBound)
          let anchor =  snapshot.positionOf(utf8Offset: offset + 1)

          return InlayHint(
            position: anchor,
            label: .string("\(info.isolation)"),
            kind: .type, // TODO: is this appropriate?
            paddingLeft: true,
          )
        }
    } else {
      inferredIsolationInlays = []
    }

    return inferredIsolationInlays
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
