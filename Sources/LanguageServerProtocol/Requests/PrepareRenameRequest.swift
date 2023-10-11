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

/// Request to test the validity of a rename operation at the given location.
///
/// Looks up the symbol at the given position and returns the range of the symbol the user is renaming,
/// or null if there is no symbol to be renamed at the given position
///
/// Servers that provide rename preparation should set `prepareProvider` to true in the `renameProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: A range for the symbol, and optionally a placeholder text of the string content to be renamed.
public struct PrepareRenameRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/prepareRename"
  public typealias Response = PrepareRenameResponse?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

public struct PrepareRenameResponse: ResponseType, Hashable {
  /// The range of the symbol
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// A placeholder text of the string content to be renamed
  public var placeholder: String?

  public init(range: Range<Position>, placeholder: String? = nil) {
    self.range = range
    self.placeholder = placeholder
  }

  public init(from decoder: Decoder) throws {
    // Try decoding as PrepareRenameResponse
    do {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.range = try container.decode(PositionRange.self, forKey: .range).wrappedValue
      self.placeholder = try container.decode(String.self, forKey: .placeholder)
      return
    } catch {}

    // Try decoding as PositionRange
    do {
      self.range = try PositionRange(from: decoder).wrappedValue
      self.placeholder = nil
      return
    } catch {}

    let context = DecodingError.Context(
      codingPath: decoder.codingPath,
      debugDescription: "Expected PrepareRenameResponse or PositionRange"
    )
    throw DecodingError.dataCorrupted(context)
  }

  public func encode(to encoder: Encoder) throws {
    if let placeholder = placeholder {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(_range, forKey: .range)
      try container.encode(placeholder, forKey: .placeholder)
    } else {
      try _range.encode(to: encoder)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case range
    case placeholder
  }
}
