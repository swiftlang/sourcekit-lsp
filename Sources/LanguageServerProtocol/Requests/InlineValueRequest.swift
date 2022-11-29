//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct InlineValueContext: Codable, Hashable {
  /// The stack frame (as a DAP Id) where the execution has stopped.
  public var frameId: Int

  /// The document range where execution has stopped.
  /// Typically the end position of the range denotes the line where the
  /// inline values are shown.
  @CustomCodable<PositionRange>
  public var stoppedLocation: Range<Position>

  public init(frameId: Int, stoppedLocation: Range<Position>) {
    self.frameId = frameId
    self.stoppedLocation = stoppedLocation
  }
}

/// The inline value request is sent from the client to the server to compute inline values for a given text document that may be rendered in the editor at the end of lines.
public struct InlineValueRequest: TextDocumentRequest {
  public static var method: String = "textDocument/inlineValue"
  public typealias Response = [InlineValue]?

  /// The text document.
  public var textDocument: TextDocumentIdentifier

  /// The document range for which inline values should be computed.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// Additional information about the context in which inline values were
  /// requested.
  public var context: InlineValueContext

  public init(textDocument: TextDocumentIdentifier, range: Range<Position>, context: InlineValueContext) {
    self.textDocument = textDocument
    self.range = range
    self.context = context
  }
}

/// Provide inline value as text.
public struct InlineValueText: Codable, Hashable {
  /// The document range for which the inline value applies.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The text of the inline value.
  public var text: String

  public init(range: Range<Position>, text: String) {
    self.range = range
    self.text = text
  }
}

/// Provide inline value through a variable lookup.
///
/// If only a range is specified, the variable name will be extracted from
/// the underlying document.
///
/// An optional variable name can be used to override the extracted name.
public struct InlineValueVariableLookup: Codable, Hashable {
  /// The document range for which the inline value applies.
  /// The range is used to extract the variable name from the underlying
  /// document.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// If specified the name of the variable to look up.
  public var variableName: String?

  /// How to perform the lookup.
  public var caseSensitiveLookup: Bool

  public init(range: Range<Position>, variableName: String? = nil, caseSensitiveLookup: Bool) {
    self.range = range
    self.variableName = variableName
    self.caseSensitiveLookup = caseSensitiveLookup
  }
}

/// Provide an inline value through an expression evaluation.
///
/// If only a range is specified, the expression will be extracted from the
/// underlying document.
///
/// An optional expression can be used to override the extracted expression.
public struct InlineValueEvaluatableExpression: Codable, Hashable {
  /// The document range for which the inline value applies.
  /// The range is used to extract the evaluatable expression from the
  /// underlying document.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// If specified the expression overrides the extracted expression.
  public var expression: String?

  public init(range: Range<Position>, expression: String? = nil) {
    self.range = range
    self.expression = expression
  }
}

/// Inline value information can be provided by different means:
/// - directly as a text value (class InlineValueText).
/// - as a name to use for a variable lookup (class InlineValueVariableLookup)
/// - as an evaluatable expression (class InlineValueEvaluatableExpression)
/// The InlineValue types combines all inline value types into one type.
public enum InlineValue: ResponseType, Hashable {
  case text(InlineValueText)
  case variableLookup(InlineValueVariableLookup)
  case evaluatableExpression(InlineValueEvaluatableExpression)

  public init(from decoder: Decoder) throws {
    if let text = try? InlineValueText(from: decoder) {
      self = .text(text)
    } else if let variableLookup = try? InlineValueVariableLookup(from: decoder) {
      self = .variableLookup(variableLookup)
    } else if let evaluatableExpression = try? InlineValueEvaluatableExpression(from: decoder) {
      self = .evaluatableExpression(evaluatableExpression)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected InlineValueText, InlineValueEvaluatableExpression or InlineValueEvaluatableExpression")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .text(let text):
      try text.encode(to: encoder)
    case .variableLookup(let variableLookup):
      try variableLookup.encode(to: encoder)
    case .evaluatableExpression(let evaluatableExpression):
      try evaluatableExpression.encode(to: encoder)
    }
  }
}
