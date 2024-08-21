//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

struct FailedToConstructDocumentURIFromStringError: Error, CustomStringConvertible {
  let string: String

  var description: String {
    return "Failed to construct DocumentURI from '\(string)'"
  }
}

public struct DocumentURI: Codable, Hashable, Sendable {
  /// The URL that store the URIs value
  private let storage: URL

  public var description: String {
    return storage.description
  }

  public var fileURL: URL? {
    if storage.isFileURL {
      return storage
    } else {
      return nil
    }
  }

  /// The URL representation of the URI. Note that this URL can have an arbitrary scheme and might
  /// not represent a file URL.
  public var arbitrarySchemeURL: URL { storage }

  /// The document's URL scheme, if present.
  public var scheme: String? {
    return storage.scheme
  }

  /// Returns a filepath if the URI is a URL. If the URI is not a URL, returns
  /// the full URI as a fallback.
  /// This value is intended to be used when interacting with sourcekitd which
  /// expects a file path but is able to handle arbitrary strings as well in a
  /// fallback mode that drops semantic functionality.
  public var pseudoPath: String {
    if storage.isFileURL {
      return storage.withUnsafeFileSystemRepresentation {
        String(cString: $0!)
      }
    } else {
      return storage.absoluteString
    }
  }

  /// Returns the URI as a string.
  public var stringValue: String {
    return storage.absoluteString
  }

  /// Construct a DocumentURI from the given URI string, automatically parsing
  ///  it either as a URL or an opaque URI.
  public init(string: String) throws {
    guard let url = URL(string: string) else {
      throw FailedToConstructDocumentURIFromStringError(string: string)
    }
    self.init(url)
  }

  public init(_ url: URL) {
    self.storage = url
    assert(self.storage.scheme != nil, "Received invalid URI without a scheme '\(self.storage.absoluteString)'")
  }

  public init(filePath: String, isDirectory: Bool) {
    self.init(URL(fileURLWithPath: filePath, isDirectory: isDirectory))
  }

  public init(from decoder: Decoder) throws {
    let string = try decoder.singleValueContainer().decode(String.self)
    guard let url = URL(string: string) else {
      throw FailedToConstructDocumentURIFromStringError(string: string)
    }
    if url.query() != nil, var urlComponents = URLComponents(string: url.absoluteString) {
      // See comment in `encode(to:)`
      urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery!.removingPercentEncoding
      if let rewrittenQuery = urlComponents.url {
        self.init(rewrittenQuery)
        return
      }
    }
    self.init(url)
  }

  /// Equality check to handle escape sequences in file URLs.
  public static func == (lhs: DocumentURI, rhs: DocumentURI) -> Bool {
    return lhs.storage.scheme == rhs.storage.scheme && lhs.pseudoPath == rhs.pseudoPath
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.storage.scheme)
    hasher.combine(self.pseudoPath)
  }

  private static let additionalQueryEncodingCharacterSet = CharacterSet(charactersIn: "?=&%").inverted

  public func encode(to encoder: Encoder) throws {
    let urlToEncode: URL
    if let query = storage.query(percentEncoded: true), var components = URLComponents(string: storage.absoluteString) {
      // The URI standard RFC 3986 is ambiguous about whether percent encoding and their represented characters are
      // considered equivalent. VS Code considers them equivalent and treats them the same:
      //
      // vscode.Uri.parse("x://a?b=xxxx%3Dyyyy").toString() -> 'x://a?b%3Dxxxx%3Dyyyy'
      // vscode.Uri.parse("x://a?b=xxxx%3Dyyyy").toString(/*skipEncoding=*/true) -> 'x://a?b=xxxx=yyyy'
      //
      // This causes issues because SourceKit-LSP's macro expansion URLs encoded by URLComponents use `=` to denote the
      // separation of a key and a value in the outer query. The value of the `parent` key may itself contain query
      // items, which use the escaped form '%3D'. Simplified, such a URL may look like
      // scheme://host?parent=scheme://host?line%3D2
      // But after running this through VS Code's URI type `=` and `%3D` get canonicalized and are indistinguishable.
      // To avoid this ambiguity, always percent escape the characters we use to distinguish URL query parameters,
      // producing the following URL.
      // scheme://host?parent%3Dscheme://host%3Fline%253D2
      components.percentEncodedQuery =
        query
        .addingPercentEncoding(withAllowedCharacters: Self.additionalQueryEncodingCharacterSet)
      if let componentsUrl = components.url {
        urlToEncode = componentsUrl
      } else {
        urlToEncode = self.storage
      }
    } else {
      urlToEncode = self.storage
    }
    try urlToEncode.absoluteString.encode(to: encoder)
  }
}
