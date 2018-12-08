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

import struct Foundation.URL

/// Convenience alias so that you don't need to add Foundation import to use.
public typealias URL = Foundation.URL

/// Unique identifier for a document.
public struct TextDocumentIdentifier: Hashable {

  /// A URL that uniquely identifies the document.
  public var url: URL

  public init(_ url: URL) {
    self.url = url
  }
}

// Encode using the key "uri" to match LSP.
extension TextDocumentIdentifier: Codable {
  private enum CodingKeys: String, CodingKey {
    case url = "uri"
  }
}
