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

/// Standardize the URL.
///
/// This normalizes escape sequences in file URLs, like `%40` --> `@`.
/// But for non-file URLs, has no effect.
fileprivate func standardize(url: URL) -> URL {
  guard url.isFileURL else { return url }

  // This has the side-effect of removing trailing slashes from file URLs
  // on Linux, so we may need to add it back.
  let standardized = url.standardizedFileURL
  if url.absoluteString.hasSuffix("/") && !standardized.absoluteString.hasSuffix("/") {
    return URL(fileURLWithPath: standardized.path, isDirectory: true)
  }
  return standardized
}

public struct DocumentURI: Codable, Hashable {
  /// The URL that store the URIs value
  private let storage: URL

  public var fileURL: URL? {
    if storage.isFileURL {
      return storage
    } else {
      return nil
    }
  }

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
      return storage.path
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
  public init(string: String) {
    guard let url = URL(string: string) else {
      fatalError("Failed to construct DocumentURI from '\(string)'")
    }
    self.init(standardize(url: url))
  }

  public init(_ url: URL) {
    self.storage = url
    assert(self.storage.scheme != nil, "Received invalid URI without a scheme '\(self.storage.absoluteString)'")
  }

  public init(from decoder: Decoder) throws {
    self.init(string: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    try storage.absoluteString.encode(to: encoder)
  }
}
