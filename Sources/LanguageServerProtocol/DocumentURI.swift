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

public enum DocumentURI: Codable, Hashable {
  case url(URL)
  case other(String)

  /// Returns a filepath if the URI is a URL. If the URI is not a URL, returns
  /// the full URI as a fallback.
  /// This value is intended to be used when interacting with sourcekitd which
  /// expects a file path but is able to handle arbitrary strings as well in a
  /// fallback mode that drops semantic functionality.
  public var pseudoPath: String {
    switch self {
    case .url(let url):
      return url.path
    case .other(let string):
      return string
    }
  }

  /// Returns the URI as a string.
  public var stringValue: String {
    switch self {
    case .url(let url):
      return url.absoluteString
    case .other(let string):
      return string
    }
  }

  /// Construct a DocumentURI from the given URI string, automatically parsing
  ///  it either as a URL or an opaque URI.
  public init(string: String) {
    if string.starts(with: "file:"), let url = URL(string: string) {
      // URL with a 'file:' protocol. Parse using URL(string:)
      self = .url(url)
    } else if string.starts(with: "/") {
      // Absolute path. Technically this not part of the LSP specification
      // but we want to support it anyway.
      // Parse it using URL(fileURLWithPath:)
      self = .url(URL(fileURLWithPath: string))
    } else {
      // Can't parse URI as URL. Use it as an opaque value.
      self = .other(string)
    }
  }

  public init(from decoder: Decoder) throws {
    self.init(string: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .url(let url):
      try url.absoluteString.encode(to: encoder)
    case .other(let string):
      try string.encode(to: encoder)
    }
  }
}
