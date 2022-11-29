//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Represents an inline annotation displayed by the editor in a source file.
public struct InlayHint: ResponseType, Codable, Hashable {
  /// The position within the code that this hint is attached to.
  public var position: Position

  /// The hint's text, e.g. a printed type
  public let label: InlayHintLabel

  /// The hint's kind, used for more flexible client-side styling.
  public let kind: InlayHintKind?

  /// Optional text edits that are performed when accepting this inlay hint.
  public let textEdits: [TextEdit]?

  /// The tooltip text displayed when the inlay hint is hovered.
  public let tooltip: StringOrMarkupContent?

  /// Whether to render padding before the hint.
  public let paddingLeft: Bool?

  /// Whether to render padding after the hint.
  public let paddingRight: Bool?

  /// A data entry field that is present between a `textDocument/inlayHint`
  /// and a `inlayHint/resolve` request.
  public let data: LSPAny?

  public init(
    position: Position,
    label: InlayHintLabel,
    kind: InlayHintKind? = nil,
    textEdits: [TextEdit]? = nil,
    tooltip: StringOrMarkupContent? = nil,
    paddingLeft: Bool? = nil,
    paddingRight: Bool? = nil,
    data: LSPAny? = nil
  ) {
    self.position = position
    self.label = label
    self.kind = kind
    self.textEdits = textEdits
    self.tooltip = tooltip
    self.paddingLeft = paddingLeft
    self.paddingRight = paddingRight
    self.data = data
  }
}

/// A hint's kind, used for more flexible client-side styling.
public struct InlayHintKind: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// A type annotation.
  public static let type: InlayHintKind = InlayHintKind(rawValue: 1)
  /// A parameter label. Note that this case is not used by
  /// Swift, since Swift already has explicit parameter labels.
  public static let parameter: InlayHintKind = InlayHintKind(rawValue: 2)
}

/// A hint's label, either being a single string or a composition of parts.
public enum InlayHintLabel: Codable, Hashable {
  case parts([InlayHintLabelPart])
  case string(String)

  public init(from decoder: Decoder) throws {
    if let parts = try? [InlayHintLabelPart](from: decoder) {
      self = .parts(parts)
    } else if let string = try? String(from: decoder) {
      self = .string(string)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected [InlayHintLabelPart] or String")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case let .parts(parts):
      try parts.encode(to: encoder)
    case let .string(string):
      try string.encode(to: encoder)
    }
  }
}

extension InlayHintLabel: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension InlayHintLabel: ExpressibleByStringInterpolation {
  public init(stringInterpolation interpolation: DefaultStringInterpolation) {
    self = .string(.init(stringInterpolation: interpolation))
  }
}

/// A part of an interactive or composite inlay hint label.
public struct InlayHintLabelPart: Codable, Hashable {
  /// The value of this label part.
  public let value: String

  /// The tooltip to show when the part is hovered.
  public let tooltip: StringOrMarkupContent?

  /// An optional source code location representing this part.
  /// Used by the editor for hover and code navigation, e.g.
  /// by making the part a clickable link to the given position.
  public let location: Location?

  /// An optional command for this label part.
  public let command: Command?

  public init(
    value: String,
    tooltip: StringOrMarkupContent? = nil,
    location: Location? = nil,
    command: Command? = nil
  ) {
    self.value = value
    self.tooltip = tooltip
    self.location = location
    self.command = command
  }
}
