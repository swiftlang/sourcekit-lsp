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

public struct DocumentSemanticTokensRangeRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/semanticTokens/range"
  public typealias Response = DocumentSemanticTokensResponse?

  /// The document to fetch semantic tokens for.
  public var textDocument: TextDocumentIdentifier

  /// The range to fetch semantic tokens for.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  public init(textDocument: TextDocumentIdentifier, range: Range<Position>) {
    self.textDocument = textDocument
    self.range = range
  }
}
