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

/// The document color request is sent from the client to the server to list
/// all color references found in a given text document. Along with the range, 
/// a color value in RGB is returned.
/// Clients can use the result to decorate color references in an editor. 
///
/// - Parameters:
///   - textDocument: The document to search for color references.
///
/// - Returns: A list of color references for the given document.
public struct DocumentColorRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/documentColor"
  public typealias Response = [ColorInformation]

  /// The document in which to search for color references.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

public struct ColorInformation: ResponseType, Hashable {
  /// The range in the document where this color appears.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The actual color value for this color range.
  public var color: Color

  public init(range: Range<Position>, color: Color) {
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.color = color
  }
}

/// Represents a color in RGBA space.
public struct Color: Hashable, Codable {
  /// The red component of this color in the range [0-1].
  public var red: Double
  /// The green component of this color in the range [0-1].
  public var green: Double
  /// The blue component of this color in the range [0-1].
  public var blue: Double
  /// The alpha component of this color in the range [0-1].
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}
