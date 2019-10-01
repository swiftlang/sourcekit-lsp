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
public struct TextDocumentIdentifier: Hashable, LSPAnyCodable {

  /// A URL that uniquely identifies the document.
  public var url: URL

  public init(_ url: URL) {
    self.url = url
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .string(let urlString)? = dictionary[TextDocumentIdentifier.CodingKeys.url.stringValue] else {
      return nil
    }
    guard let url = URL(string: urlString) else {
      return nil
    }
    self.url = url
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary(
      [CodingKeys.url.stringValue: .string(url.absoluteString)]
    )
  }
}

// Encode using the key "uri" to match LSP.
extension TextDocumentIdentifier: Codable {
  public enum CodingKeys: String, CodingKey {
    case url = "uri"
  }
}
