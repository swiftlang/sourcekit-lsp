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

package import Foundation

extension FileManager {
  /// Same as `fileExists(atPath:)` but takes a `URL` instead of a `String`.
  package func fileExists(at url: URL) -> Bool {
    guard let filePath = try? url.filePath else {
      return false
    }
    return self.fileExists(atPath: filePath)
  }

  /// Returns `true` if an entry exists in the file system at the given URL and that entry is a directory.
  package func isDirectory(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return self.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
  }

  /// Returns `true` if an entry exists in the file system at the given URL and that entry is a file, ie. not a
  /// directory.
  package func isFile(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return self.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
  }

  /// Same as `createFile(atPath:data:attributes)` but throws an error when file creation fails instead of returning
  /// `false`.
  package func createFile(at url: URL, contents data: Data?, attributes: [FileAttributeKey: Any]? = nil) throws {
    struct FileCreationFailed: Error, CustomStringConvertible {
      let url: URL
      var description: String {
        "Failed to create file at '\(url)'"
      }
    }
    let successful = createFile(atPath: try url.filePath, contents: data, attributes: attributes)
    guard successful else {
      throw FileCreationFailed(url: url)
    }
  }
}
