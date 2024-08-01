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

import LanguageServerProtocol
import SKSupport

package extension DocumentSnapshot {
  /// Creates a `DocumentSnapshot` with the file contents from disk.
  ///
  /// Throws an error if the file could not be read.
  /// Returns `nil` if the `uri` is not a file URL.
  init?(withContentsFromDisk uri: DocumentURI, language: Language) throws {
    guard let url = uri.fileURL else {
      return nil
    }
    try self.init(withContentsFromDisk: url, language: language)
  }

  /// Creates a `DocumentSnapshot` with the file contents from disk.
  ///
  /// Throws an error if the file could not be read.
  init(withContentsFromDisk url: URL, language: Language) throws {
    let contents = try String(contentsOf: url, encoding: .utf8)
    self.init(uri: DocumentURI(url), language: language, version: 0, lineTable: LineTable(contents))
  }
}
