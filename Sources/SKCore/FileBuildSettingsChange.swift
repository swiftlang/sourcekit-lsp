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

  /// The `FileBuildSettings` have been modified.
  case modified(FileBuildSettings)
}

extension FileBuildSettingsChange {
  public var newSettings: FileBuildSettings? {
    switch self {
    case .removedOrUnavailable:
      return nil
    case .modified(let settings):
      return settings
    }
  }

  public init(_ settings: FileBuildSettings?) {
    if let settings = settings {
      self = .modified(settings)
    } else {
      self = .removedOrUnavailable
    }
  }
}
