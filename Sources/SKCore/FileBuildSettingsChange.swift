//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Denotes a change in build settings for a single file.
public enum FileBuildSettingsChange {

  /// The `BuildSystem` no longer has `FileBuildSettings` for the file.
  case removed

  /// The `FileBuildSettings` have been modified.
  case modified(FileBuildSettings)
}

public extension FileBuildSettingsChange {
  var newFileBuildSettings: FileBuildSettings? {
    switch self {
    case .removed:
      return nil
    case .modified(let settings):
      return settings
    }
  }
}
