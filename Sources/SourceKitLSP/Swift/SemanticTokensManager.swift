//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// Keeps track of the semantic tokens that sourcekitd has sent us for given
/// document snapshots.
actor SemanticTokensManager {
  private var semanticTokens: [DocumentSnapshot.ID: [SyntaxHighlightingToken]] = [:]

  /// The semantic tokens for the given snapshot or `nil` if no semantic tokens
  /// have been computed yet.
  func semanticTokens(for snapshotID: DocumentSnapshot.ID) -> [SyntaxHighlightingToken]? {
    return semanticTokens[snapshotID]
  }

  /// Set the semantic tokens that sourcekitd has sent us for the given document
  /// snapshot.
  ///
  /// This discards any semantic tokens for any older versions of this document.
  func setSemanticTokens(for snapshotID: DocumentSnapshot.ID, semanticTokens tokens: [SyntaxHighlightingToken]) {
    semanticTokens[snapshotID] = tokens
    // Delete semantic tokens for older versions of this document.
    for key in semanticTokens.keys {
      if key < snapshotID {
        semanticTokens[key] = nil
      }
    }
  }

  /// If we have semantic tokens for `preEditSnapshotID`, shift the tokens
  /// according to `edits` and store these shifted results for `postEditSnapshot`.
  ///
  /// This allows us to maintain semantic tokens after an edit for all the
  /// non-edited regions.
  ///
  /// - Note: The semantic tokens stored from this edit might not be correct if
  ///   the edits affect semantic highlighting for tokens out of the edit region.
  ///   These will be updated when sourcekitd sends us new semantic tokens,
  ///   which are stored in `SemanticTokensManager` by calling `setSemanticTokens`.
  func registerEdit(
    preEditSnapshot preEditSnapshotID: DocumentSnapshot.ID,
    postEditSnapshot postEditSnapshotID: DocumentSnapshot.ID,
    edits: [TextDocumentContentChangeEvent]
  ) {
    guard var semanticTokens = semanticTokens(for: preEditSnapshotID) else {
      return
    }
    for edit in edits {
      // Remove all tokens in the updated range and shift later ones.
      guard let rangeAdjuster = RangeAdjuster(edit: edit) else {
        // We have a full document edit and can't update semantic tokens
        return
      }

      semanticTokens = semanticTokens.compactMap {
        var token = $0
        if let adjustedRange = rangeAdjuster.adjust(token.range) {
          token.range = adjustedRange
          return token
        } else {
          return nil
        }
      }
    }
    setSemanticTokens(for: postEditSnapshotID, semanticTokens: semanticTokens)
  }

  /// Discard any semantic tokens for documents with the given URI.
  ///
  /// This should be called when a document is being closed and the semantic
  /// tokens are thus no longer needed.
  func discardSemanticTokens(for document: DocumentURI) {
    // Delete semantic tokens for older versions of this document.
    for key in semanticTokens.keys {
      if key.uri == document {
        semanticTokens[key] = nil
      }
    }
  }
}
