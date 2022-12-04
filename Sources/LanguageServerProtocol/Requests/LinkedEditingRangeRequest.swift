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

public struct LinkedEditingRangeRequest: TextDocumentRequest {
  public static var method: String = "textDocument/linkedEditingRange"
  public typealias Response = LinkedEditingRanges?

  /// The document in which the given symbol is located.
  public var textDocument: TextDocumentIdentifier

  /// The document location of a given symbol.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

public struct LinkedEditingRanges: ResponseType {
   /// A list of ranges that can be renamed together. The ranges must have
   /// identical length and contain identical text content. The ranges cannot
   /// overlap.
  @CustomCodable<PositionRangeArray>
  public var ranges: [Range<Position>]

   /// An optional word pattern (regular expression) that describes valid
   /// contents for the given ranges. If no pattern is provided, the client
   /// configuration's word pattern will be used.
  public var wordPattern: String?

  public init(ranges: [Range<Position>], wordPattern: String? = nil) {
    self.ranges = ranges
    self.wordPattern = wordPattern
  }
}
