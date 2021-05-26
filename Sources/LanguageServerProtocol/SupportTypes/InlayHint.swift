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

  /// The hint's kind, used for more flexible client-side styling.
  public let category: InlayHintCategory?

  /// The hint's text, e.g. a printed type
  public let label: String

  public init(
    position: Position,
    category: InlayHintCategory? = nil,
    label: String
  ) {
    self.position = position
    self.category = category
    self.label = label
  }
}

/// A hint's kind, used for more flexible client-side styling.
public struct InlayHintCategory: RawRepresentable, Codable, Hashable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// A parameter label. Note that this case is not used by
  /// Swift, since Swift already has explicit parameter labels.
  public static let parameter: InlayHintCategory = InlayHintCategory(rawValue: "parameter")
  /// An inferred type.
  public static let type: InlayHintCategory = InlayHintCategory(rawValue: "type")
}
