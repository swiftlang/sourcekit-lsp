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

import TSCBasic

extension FileSystem {

  /// Creates files from a dictionary of path to contents.
  ///
  /// - parameters:
  ///   - root: The root directory that the paths are relative to.
  ///   - files: Dictionary from path (relative to root) to contents.
  public func createFiles(root: AbsolutePath = .root, files: [String: ByteString]) throws {
    for (path, contents) in files {
      let path = AbsolutePath(path, relativeTo: root)
      try createDirectory(path.parentDirectory, recursive: true)
      try writeFileContents(path, bytes: contents)
    }
  }
}
