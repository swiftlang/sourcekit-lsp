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

/// Denotes a change in build settings for a single file.
public enum FileBuildSettingsChange {

  /// The `BuildSystem` has no `FileBuildSettings` for the file.
  case removedOrUnavailable

  /// The `FileBuildSettings` have been modified or are newly available.
  case modified(FileBuildSettings)

  /// The `BuildSystem` is providing fallback arguments which may not be correct.
  case fallback(FileBuildSettings)
}
