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

/// Edit to a text document, replacing the contents of `range` with `text`.
public struct TextEdit: ResponseType, Hashable {

  /// The range of text to be replaced.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The new text.
  public var newText: String

  public init(range: Range<Position>, newText: String) {
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.newText = newText
  }
}

extension TextEdit: LSPAnyCodable {
  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .dictionary(let rangeDict) = dictionary[CodingKeys.range.stringValue],
          case .string(let newText) = dictionary[CodingKeys.newText.stringValue] else
    {
      return nil
    }
    guard let range = Range<Position>(fromLSPDictionary: rangeDict) else {
      return nil
    }
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.newText = newText
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.range.stringValue: range.encodeToLSPAny(),
      CodingKeys.newText.stringValue: .string(newText)
    ])
  }
}

/// Additional information that describes document changes.
public struct ChangeAnnotation: Codable, Hashable {
  /// A human-readable string describing the actual change. The string
  /// is rendered prominent in the user interface.
  public var label: String

  /// A flag which indicates that user confirmation is needed
  /// before applying the change.
  public var needsConfirmation: Bool? = nil

  /// A human-readable string which is rendered less prominent in
  /// the user interface.
  public var description: String? = nil

  public init(label: String, needsConfirmation: Bool? = nil, description: String? = nil) {
    self.label = label
    self.needsConfirmation = needsConfirmation
    self.description = description
  }
}


/// An identifier referring to a change annotation managed by a workspace
/// edit.
public typealias ChangeAnnotationIdentifier = String

/// A special text edit with an additional change annotation.
///
/// Notionally a subtype of `TextEdit`.
public struct AnnotatedTextEdit: ResponseType, Hashable {

  /// The range of text to be replaced.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The new text.
  public var newText: String

  public var annotationId: ChangeAnnotationIdentifier

  public init(range: Range<Position>, newText: String, annotationId: ChangeAnnotationIdentifier) {
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.newText = newText
    self.annotationId = annotationId
  }
}
