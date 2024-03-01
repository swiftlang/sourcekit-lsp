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

import SwiftParser
import SwiftSyntax

/// Keeps track of SwiftSyntax trees for document snapshots and computes the
/// SwiftSyntax trees on demand.
actor SyntaxTreeManager {
  /// A task that parses a SwiftSyntax tree from a source file, producing both
  /// the syntax tree and the lookahead ranges that are needed for a subsequent
  /// incremental parse.
  private typealias SyntaxTreeComputation = Task<IncrementalParseResult, Never>

  /// The tasks that compute syntax trees.
  ///
  /// Conceptually, this is a dictionary. To prevent excessive memory usage we
  /// only keep `cacheSize` entries within the array. Older entries are at the
  /// end of the list, newer entries at the front.
  private var syntaxTreeComputations:
    [(
      snapshotID: DocumentSnapshot.ID,
      computation: SyntaxTreeComputation
    )] = []

  /// The number of syntax trees to keep.
  ///
  /// - Note: This has been chosen without scientific measurements. The feeling
  ///   is that you rarely work on more than 5 files at once and 5 syntax trees
  ///   don't take up too much memory.
  private let cacheSize = 5

  /// - Important: For testing only
  private var reusedNodeCallback: ReusedNodeCallback?

  /// - Important: For testing only
  func setReusedNodeCallback(_ callback: ReusedNodeCallback?) {
    self.reusedNodeCallback = callback
  }

  /// The task that computes the syntax tree for the given document snapshot.
  private func computation(for snapshotID: DocumentSnapshot.ID) -> SyntaxTreeComputation? {
    return syntaxTreeComputations.first(where: { $0.snapshotID == snapshotID })?.computation
  }

  /// Set the task that computes the syntax tree for the given document snapshot.
  ///
  /// If we are already storing `cacheSize` many syntax trees, the oldest one
  /// will get discarded.
  private func setComputation(for snapshotID: DocumentSnapshot.ID, computation: SyntaxTreeComputation) {
    syntaxTreeComputations.insert((snapshotID, computation), at: 0)

    // Remove any syntax trees for old versions of this document.
    syntaxTreeComputations.removeAll(where: { $0.snapshotID < snapshotID })

    // If we still have more than `cacheSize` syntax trees, delete the ones that
    // were produced last. We can always re-compute them on-demand.
    while syntaxTreeComputations.count > cacheSize {
      syntaxTreeComputations.removeLast()
    }
  }

  /// Get the SwiftSyntax tree for the given document snapshot.
  func syntaxTree(for snapshot: DocumentSnapshot) async -> SourceFileSyntax {
    return await incrementalParseResult(for: snapshot).tree
  }

  /// Get the `IncrementalParseResult` for the given document snapshot.
  func incrementalParseResult(for snapshot: DocumentSnapshot) async -> IncrementalParseResult {
    if let syntaxTreeComputation = computation(for: snapshot.id) {
      return await syntaxTreeComputation.value
    }
    let task = Task {
      return Parser.parseIncrementally(source: snapshot.text, parseTransition: nil)
    }
    setComputation(for: snapshot.id, computation: task)
    return await task.value
  }

  /// Register that we have made an edit to an old document snapshot.
  ///
  /// If we computed a syntax tree for the pre-edit snapshot, we will perform an
  /// incremental parse to compute the syntax tree for the post-edit snapshot.
  func registerEdit(preEditSnapshot: DocumentSnapshot, postEditSnapshot: DocumentSnapshot, edits: ConcurrentEdits) {
    guard let preEditTreeComputation = computation(for: preEditSnapshot.id) else {
      // We don't have the old tree and thus can't perform an incremental parse.
      // So there's nothing to do. We will perform a full parse once we request
      // the syntax tree for the first time.
      return
    }
    let incrementalParseComputation = Task {
      // Note: It could be the case that the pre-edit tree has not been fully
      // computed yet when we enter this task and we will need to wait for its
      // computation to finish. That is desired because the with very high
      // likelihood it's faster to wait for the pre-edit parse to finish and
      // perform an incremental parse (which should be very fast) than to start
      // a new, full, from-scratch parse.
      let oldParseResult = await preEditTreeComputation.value
      let parseTransition = IncrementalParseTransition(
        previousIncrementalParseResult: oldParseResult,
        edits: edits,
        reusedNodeCallback: reusedNodeCallback
      )
      return Parser.parseIncrementally(source: postEditSnapshot.text, parseTransition: parseTransition)
    }
    self.setComputation(for: postEditSnapshot.id, computation: incrementalParseComputation)
  }
}
