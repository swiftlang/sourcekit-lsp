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

/// Request for documentation information about the symbol at a given location.
///
/// This request looks up the symbol (if any) at a given text document location and returns the
/// documentation markup content for that location, suitable to show in an dialog when hovering over
/// that symbol in an editor.
///
/// Servers that provide document highlights should set the `hoverProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: HoverResponse for the given location, which contains the `MarkupContent`.
public struct HoverRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/hover"
  public typealias Response = HoverResponse?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// Documentation markup contents for a symbol found by the hover request.
public struct HoverResponse: ResponseType, Hashable {

  /// The documentation markup content.
  public var contents: HoverResponseContents

  /// An optional range to visually distinguish during hover.
  public var range: Range<Position>?

  public init(contents: HoverResponseContents, range: Range<Position>?) {
    self.contents = contents
    self.range = range
  }
}

public enum HoverResponseContents: Hashable {
  case markedString(MarkedString)
  case markedStrings([MarkedString])
  case markupContent(MarkupContent)
}

public enum MarkedString: Hashable {
  private struct MarkdownCodeBlock: Codable {
    let language: String
    let value: String
  }

  case markdown(value: String)
  case codeBlock(language: String, value: String)
}

// Needs a custom implementation for range, because `Optional` is the only type that uses
// `encodeIfPresent` in the synthesized conformance, and the
// [LSP specification does not allow `null` in most places](https://github.com/microsoft/language-server-protocol/issues/355).
extension HoverResponse: Codable {
  private enum CodingKeys: String, CodingKey {
    case contents
    case range
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.contents = try container.decode(HoverResponseContents.self, forKey: .contents)
    self.range = try container
      .decodeIfPresent(PositionRange.self, forKey: .range)?
      .wrappedValue
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(contents, forKey: .contents)
    try container.encodeIfPresent(range.map { PositionRange(wrappedValue: $0) }, forKey: .range)
  }
}

extension MarkedString: Codable {
  public init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      self = .markdown(value: value)
    } else if let codeBlock = try? MarkdownCodeBlock(from: decoder) {
      self = .codeBlock(language: codeBlock.language, value: codeBlock.value)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "MarkedString is neither pure string nor code block")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .markdown(value: let value):
      try value.encode(to: encoder)
    case .codeBlock(language: let language, value: let value):
      try MarkdownCodeBlock(language: language, value: value).encode(to: encoder)
    }
  }
}

extension HoverResponseContents: Codable {
  public init(from decoder: Decoder) throws {
    if let value = try? MarkupContent(from: decoder) {
      self = .markupContent(value)
    } else if let value = try? MarkedString(from: decoder) {
      self = .markedString(value)
    } else if let value = try? [MarkedString](from: decoder) {
      self = .markedStrings(value)
    } else if let value = try? MarkupContent(from: decoder) {
      self = .markupContent(value)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "HoverResponseContents is neither MarkedString, nor [MarkedString], nor MarkupContent")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .markedString(let value):
      try value.encode(to: encoder)
    case .markedStrings(let value):
      try value.encode(to: encoder)
    case .markupContent(let value):
      try value.encode(to: encoder)
    }
  }
}
