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

import Foundation

extension FileManager {
  /// Returns the URLs of all files with the given file extension in the given directory (recursively).
  public func findFiles(withExtension extensionName: String, in directory: URL) -> [URL] {
    var result: [URL] = []
    let enumerator = self.enumerator(at: directory, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
      if url.pathExtension == extensionName {
        result.append(url)
      }
    }
    return result
  }

  /// Returns the URLs of all files with the given file extension in the given directory (recursively).
  public func findFiles(named name: String, in directory: URL) -> [URL] {
    var result: [URL] = []
    let enumerator = self.enumerator(at: directory, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
      if url.lastPathComponent == name {
        result.append(url)
      }
    }
    return result
  }
}
