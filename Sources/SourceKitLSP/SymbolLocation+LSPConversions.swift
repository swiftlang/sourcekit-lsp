//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import IndexStoreDB
package import LanguageServerProtocol

extension SymbolLocation {
  /// The LSP `DocumentURI` corresponding to this index location's file path, or `nil` if `path` is empty.
  package var uri: DocumentURI? {
    guard !path.isEmpty else { return nil }
    return DocumentURI(filePath: self.path, isDirectory: false)
  }

  /// The 0-based LSP `Position` corresponding to this 1-based index location.
  package var lspPosition: Position {
    Position(
      line: max(0, line - 1),
      // Technically, we always need to convert UTF-8 columns to UTF-16 columns, which requires
      // reading the file. In practice, they are almost always the same. We chose to avoid hitting
      // the file system even if it means that we might report an incorrect column.
      utf16index: max(0, utf8Column - 1)
    )
  }

  /// The LSP `Location` corresponding to this index location, or `nil` if `path` is empty.
  package var lspLocation: Location? {
    guard let uri = uri else { return nil }
    return Location(uri: uri, range: Range(lspPosition))
  }
}
