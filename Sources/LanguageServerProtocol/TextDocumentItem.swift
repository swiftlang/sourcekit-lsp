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

/// The content and metadata of a text document.
public struct TextDocumentItem: Hashable {

      public var url: URL

      public var language: Language

      /// The version number of this document, which increases after each edit.
      public var version: Int

      /// The content of the document.
      public var text: String

      public init(url: URL, language: Language, version: Int, text: String) {
            self.url = url
            self.language = language
            self.version = version
            self.text = text
      }
}

extension TextDocumentItem: Codable {
      private enum CodingKeys: String, CodingKey {
            case url = "uri"
            case language = "languageId"
            case version
            case text
      }
}
