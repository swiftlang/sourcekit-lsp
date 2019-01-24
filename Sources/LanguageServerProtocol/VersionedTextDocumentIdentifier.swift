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

/// A document identifier representing a specific version of the document.
///
/// Notionally a subtype of `TextDocumentIdentifier`.
public struct VersionedTextDocumentIdentifier: Hashable {

      /// A URL that uniquely identifies the document.
      public var url: URL

      /// The version number of this document, or nil if unknown.
      public var version: Int?

      public init(_ url: URL, version: Int?) {
            self.url = url
            self.version = version
      }
}

// Encode using the key "uri" to match LSP.
extension VersionedTextDocumentIdentifier: Codable {
      private enum CodingKeys: String, CodingKey {
            case url = "uri"
            case version
      }
}
