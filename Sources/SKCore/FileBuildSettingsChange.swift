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

extension FileBuildSettingsChange {
  public var newSettings: FileBuildSettings? {
    switch self {
    case .removedOrUnavailable:
      return nil
    case .modified(let settings):
      return settings
    case .fallback(let settings):
      return settings
    }
  }

  /// Whether the change represents fallback arguments.
  public var isFallback: Bool {
    switch self {
    case .removedOrUnavailable:
      return false
    case .modified(_):
      return false
    case .fallback(_):
      return true
    }
  }

  public init(_ settings: FileBuildSettings?, fallback: Bool = false) {
    if let settings = settings {
      self = fallback ? .fallback(settings) : .modified(settings)
    } else {
      self = .removedOrUnavailable
    }
  }
}
