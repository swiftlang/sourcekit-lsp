//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// An experimental feature that can be enabled by passing `--experimental-feature` to `sourcekit-lsp` on the command
/// line. The raw value of this feature is how it is named on the command line.
public enum ExperimentalFeature: String, Codable, Sendable, CaseIterable {
  /// Enable background indexing.
  case backgroundIndexing = "background-indexing"

  /// Show the files that are currently being indexed / the targets that are currently being prepared in the work done
  /// progress.
  ///
  /// This is an option because VS Code tries to render a multi-line work done progress into a single line text field in
  /// the status bar, which looks broken. But at the same time, it is very useful to get a feeling about what's
  /// currently happening indexing-wise.
  case showActivePreparationTasksInProgress = "show-active-preparation-tasks-in-progress"
}
