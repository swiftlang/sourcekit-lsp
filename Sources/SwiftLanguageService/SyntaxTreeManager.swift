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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKUtilities
import SourceKitLSP
@_spi(ExperimentalLanguageFeatures) import SwiftParser
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
  /// - Note: The capacity has been chosen without scientific measurements. The
  ///   feeling is that you rarely work on more than 5 files at once and 5 syntax
  ///   trees don't take up too much memory.
  private var syntaxTreeComputations = LRUCache<DocumentSnapshot.ID, SyntaxTreeComputation>(capacity: 5)

  /// The experimental features to use when parsing files, keyed by document URI.
  ///
  /// When build settings are available for a file, the experimental features enabled in those build settings
  /// (via `-enable-experimental-feature` compiler flags) are stored here and passed to the Swift parser.
  private var experimentalFeaturesPerDocument: [DocumentURI: Parser.ExperimentalFeatures] = [:]

  /// - Important: For testing only
  private var reusedNodeCallback: ReusedNodeCallback?

  /// - Important: For testing only
  func setReusedNodeCallback(_ callback: ReusedNodeCallback?) {
    self.reusedNodeCallback = callback
  }

  /// Set the experimental features to use when parsing the given document.
  ///
  /// This should be called whenever build settings for a document are updated.
  /// The features will be used for subsequent parse operations on that document.
  /// If the features differ from the previously stored ones, any cached syntax trees for the document are invalidated
  /// so that they will be re-parsed with the new features on next access.
  func setExperimentalFeatures(_ features: Parser.ExperimentalFeatures, for uri: DocumentURI) {
    let previousFeatures = experimentalFeaturesPerDocument[uri] ?? []
    if previousFeatures != features {
      experimentalFeaturesPerDocument[uri] = features
      // Invalidate cached syntax trees since they were parsed with different experimental features.
      syntaxTreeComputations.removeAll(where: { $0.uri == uri })
    }
  }

  /// Get the experimental features for the given document URI.
  private func experimentalFeatures(for uri: DocumentURI) -> Parser.ExperimentalFeatures {
    return experimentalFeaturesPerDocument[uri] ?? []
  }

  /// The task that computes the syntax tree for the given document snapshot.
  private func computation(for snapshotID: DocumentSnapshot.ID) -> SyntaxTreeComputation? {
    return syntaxTreeComputations[snapshotID]
  }

  /// Set the task that computes the syntax tree for the given document snapshot.
  private func setComputation(for snapshotID: DocumentSnapshot.ID, computation: SyntaxTreeComputation) {
    // Remove any syntax trees for old versions of this document.
    syntaxTreeComputations.removeAll(where: { $0 < snapshotID })
    syntaxTreeComputations[snapshotID] = computation
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
    let features = experimentalFeatures(for: snapshot.uri)
    let task = Task {
      return Self.parseIncrementally(source: snapshot.text, experimentalFeatures: features, parseTransition: nil)
    }
    setComputation(for: snapshot.id, computation: task)
    return await task.value
  }

  /// Parse a source file incrementally, passing the given experimental features to the parser.
  private static func parseIncrementally(
    source: String,
    experimentalFeatures: Parser.ExperimentalFeatures,
    parseTransition: IncrementalParseTransition?
  ) -> IncrementalParseResult {
    var parser = Parser(source, parseTransition: parseTransition, experimentalFeatures: experimentalFeatures)
    return IncrementalParseResult(
      tree: SourceFileSyntax.parse(from: &parser),
      lookaheadRanges: parser.lookaheadRanges
    )
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
    let features = experimentalFeatures(for: postEditSnapshot.uri)
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
        reusedNodeCallback: self.reusedNodeCallback
      )
      return Self.parseIncrementally(
        source: postEditSnapshot.text,
        experimentalFeatures: features,
        parseTransition: parseTransition
      )
    }
    self.setComputation(for: postEditSnapshot.id, computation: incrementalParseComputation)
  }

  /// Remove all cached syntax trees for the given document, eg. when the document is closed.
  func clearSyntaxTrees(for uri: DocumentURI) {
    syntaxTreeComputations.removeAll(where: { $0.uri == uri })
    experimentalFeaturesPerDocument.removeValue(forKey: uri)
  }
}
