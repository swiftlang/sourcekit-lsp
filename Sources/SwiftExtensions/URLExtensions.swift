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

#if os(Windows)
import WinSDK
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
        defer {
          free(realpath)
        }
        return URL(fileURLWithPath: String(cString: realpath))
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
      return try self.withUnsafeFileSystemRepresentation { filePathPtr in
        guard let filePathPtr else {
          throw FilePathError.noFileSystemRepresentation(self)
        }
        let filePath = String(cString: filePathPtr)
        #if os(Windows)
        // VS Code spells file paths with a lowercase drive letter, while the rest of Windows APIs use an uppercase
        // drive letter. Normalize the drive letter spelling to be uppercase.
        if filePath.first?.isASCII ?? false, filePath.first?.isLetter ?? false, filePath.first?.isLowercase ?? false,
          filePath.count > 1, filePath[filePath.index(filePath.startIndex, offsetBy: 1)] == ":"
        {
          return filePath.first!.uppercased() + filePath.dropFirst()
        }
        #endif
        return filePath
      }
    }
  }

  /// Assuming this URL is a file URL, checks if it looks like a root path. This is a string check, ie. the return
  /// value for a path of `"/foo/.."` would be `false`. An error will be thrown is this is a non-file URL.
  package var isRoot: Bool {
    get throws {
      let checkPath = try filePath
      #if os(Windows)
      return checkPath.withCString(encodedAs: UTF16.self, PathCchIsRoot)
      #else
      return checkPath == "/"
      #endif
    }
  }

  /// Returns true if the path of `self` starts with the path in `other`.
  package func isDescendant(of other: URL) -> Bool {
    return self.pathComponents.dropLast().starts(with: other.pathComponents)
  }
}
