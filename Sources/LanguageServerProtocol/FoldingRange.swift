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

/// Request for returning all folding ranges found in a given text document.
///
/// Searches a document and returns a list of ranges of code that can be folded.
///
/// Servers that provide folding ranges should set the `foldingRanges` server capability.
///
/// - Parameters:
///   - textDocument: The document to search for folding ranges.
///
/// - Returns: A list of folding ranges for the given document.
public struct FoldingRangeRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/foldingRange"
  public typealias Response = [FoldingRange]?

  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

/// A single folding range result.
public struct FoldingRange: ResponseType, Hashable {

  /// The zero-based line number from where the folded range starts.
  public var startLine: Int

  /// The zero-based character offset from where the folded range starts.
  /// If not defined, defaults to the length of the start line.
  public var startCharacter: Int?

  /// The zero-based line number where the folded range ends.
  public var endLine: Int

  /// The zero-based character offset before the folded range ends.
  /// If not defined, defaults to the length of the end line.
  public var endCharacter: Int?

  /// Describes the kind of the folding range such as `comment' or 'region'. The kind
  /// is used to categorize folding ranges and used by commands like 'Fold all comments'.
  public var kind: FoldingRangeKind?

  public init(startLine: Int, startCharacter: Int? = nil, endLine: Int, endCharacter: Int? = nil, kind: FoldingRangeKind? = nil) {
    self.startLine = startLine
    self.startCharacter = startCharacter
    self.endLine = endLine
    self.endCharacter = endCharacter
    self.kind = kind
  }
}
