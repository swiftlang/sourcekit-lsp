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


/// The kind of markup (plaintext or markdown).
///
/// In LSP, this is a string, so we don't use a closed set.
public struct MarkupKind: RawRepresentable, Codable, Hashable {
  public var rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let plaintext: MarkupKind = MarkupKind(rawValue: "plaintext")
  public static let markdown: MarkupKind = MarkupKind(rawValue: "markdown")
}

public struct MarkupContent: Codable, Hashable {

  public var kind: MarkupKind

  public var value: String

  public init(kind: MarkupKind, value: String) {
    self.kind = kind
    self.value = value
  }
}
