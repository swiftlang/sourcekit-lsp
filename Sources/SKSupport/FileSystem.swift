//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import struct TSCBasic.AbsolutePath

/// The home directory of the current user (same as returned by Foundation's `NSHomeDirectory` method).
public var homeDirectoryForCurrentUser: AbsolutePath {
  return AbsolutePath(NSHomeDirectory())
}

extension AbsolutePath {

  /// Inititializes an absolute path from a string, expanding a leading `~` to `homeDirectoryForCurrentUser` first.
  public init(expandingTilde path: String) {
    if path.first == "~" {
      self.init(homeDirectoryForCurrentUser, String(path.dropFirst(2)))
    } else {
      self.init(path)
    }
  }
}

/// The directory to write generated module interfaces
public var defaultDirectoryForGeneratedInterfaces: AbsolutePath {
  return AbsolutePath(NSTemporaryDirectory()).appending(component: "GeneratedInterfaces")
}
