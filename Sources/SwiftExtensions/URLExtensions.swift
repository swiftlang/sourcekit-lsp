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

#if compiler(>=6)
package import Foundation
#else
import Foundation
#endif

enum FilePathError: Error, CustomStringConvertible {
  case noFileSystemRepresentation(URL)
  case noFileURL(URL)

  var description: String {
    switch self {
    case .noFileSystemRepresentation(let url):
      return "\(url.description) cannot be represented as a file system path"
    case .noFileURL(let url):
      return "\(url.description) is not a file URL"
    }
  }
}

extension URL {
  /// Assuming this is a file URL, resolves all symlinks in the path.
  ///
  /// - Note: We need this because `URL.resolvingSymlinksInPath()` not only resolves symlinks but also standardizes the
  ///   path by stripping away `private` prefixes. Since sourcekitd is not performing this standardization, using
  ///   `resolvingSymlinksInPath` can lead to slightly mismatched URLs between the sourcekit-lsp response and the test
  ///   assertion.
  package var realpath: URL {
    get throws {
      #if canImport(Darwin)
      return try self.filePath.withCString { path in
        guard let realpath = Darwin.realpath(path, nil) else {
          return self
        }
        let result = URL(fileURLWithPath: String(cString: realpath))
        free(realpath)
        return result
      }
      #else
      // Non-Darwin platforms don't have the `/private` stripping issue, so we can just use `self.resolvingSymlinksInPath`
      // here.
      return self.resolvingSymlinksInPath()
      #endif
    }
  }

  /// Assuming that this is a file URL, the path with which the file system refers to the file. This is similar to
  /// `path` but has two differences:
  /// - It uses backslashes as the path separator on Windows instead of forward slashes
  /// - It throws an error when called on a non-file URL.
  ///
  /// `filePath` should generally be preferred over `path` when dealing with file URLs.
  package var filePath: String {
    get throws {
      guard self.isFileURL else {
        throw FilePathError.noFileURL(self)
      }
      return try self.withUnsafeFileSystemRepresentation { buffer in
        guard let buffer else {
          throw FilePathError.noFileSystemRepresentation(self)
        }
        return String(cString: buffer)
      }
    }
  }

  package var isRoot: Bool {
    #if os(Windows)
    // FIXME: We should call into Windows' native check to check if this path is a root once https://github.com/swiftlang/swift-foundation/issues/976 is fixed.
    return self.pathComponents.count <= 1
    #else
    // On Linux, we may end up with an string for the path due to https://github.com/swiftlang/swift-foundation/issues/980
    // TODO: Remove the check for "" once https://github.com/swiftlang/swift-foundation/issues/980 is fixed.
    return self.path == "/" || self.path == ""
    #endif
  }

  /// Returns true if the path of `self` starts with the path in `other`.
  package func isDescendant(of other: URL) -> Bool {
    return self.pathComponents.dropLast().starts(with: other.pathComponents)
  }
}
