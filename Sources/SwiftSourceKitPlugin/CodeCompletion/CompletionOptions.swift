//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

struct CompletionOptions {
  private static let defaultMaxResults: Int = 200

  /// Whether the label and type name in the code completion result should be annotated XML or plain text.
  let annotateResults: Bool

  /// Whether object literals should be included in the code completion results.
  let includeObjectLiterals: Bool

  /// Whether initializer calls should be included in top-level completions.
  let addInitsToTopLevel: Bool

  /// If a function has defaulted arguments, whether we should produce two results (one without any defaulted arguments
  /// and one with all defaulted arguments) or only one (with all defaulted arguments).
  let addCallWithNoDefaultArgs: Bool

  /// Whether to include the semantic components computed by completion sorting in the results.
  let includeSemanticComponents: Bool

  init(
    annotateResults: Bool = false,
    includeObjectLiterals: Bool = false,
    addInitsToTopLevel: Bool = false,
    addCallWithNoDefaultArgs: Bool = true,
    includeSemanticComponents: Bool = false
  ) {
    self.annotateResults = annotateResults
    self.includeObjectLiterals = includeObjectLiterals
    self.addInitsToTopLevel = addInitsToTopLevel
    self.addCallWithNoDefaultArgs = addCallWithNoDefaultArgs
    self.includeSemanticComponents = includeSemanticComponents
  }

  //// The maximum number of results we should return if the client requested `input` results.
  static func maxResults(input: Int?) -> Int {
    guard let maxResults = input, maxResults != 0 else {
      return defaultMaxResults
    }
    if maxResults < 0 {
      return Int.max  // unlimited
    }
    return maxResults
  }
}
