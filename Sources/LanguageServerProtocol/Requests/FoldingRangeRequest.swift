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
  public var startUTF16Index: Int?

  /// The zero-based line number where the folded range ends.
  public var endLine: Int

  /// The zero-based character offset before the folded range ends.
  /// If not defined, defaults to the length of the end line.
  public var endUTF16Index: Int?

  /// Describes the kind of the folding range such as `comment' or 'region'. The kind
  /// is used to categorize folding ranges and used by commands like 'Fold all comments'.
  public var kind: FoldingRangeKind?

  /// The text that the client should show when the specified range is
  /// collapsed. If not defined or not supported by the client, a default
  /// will be chosen by the client.
  public var collapsedText: String?

  public init(
    startLine: Int,
    startUTF16Index: Int? = nil,
    endLine: Int,
    endUTF16Index: Int? = nil,
    kind: FoldingRangeKind? = nil,
    collapsedText: String? = nil
  )
  {
    self.startLine = startLine
    self.startUTF16Index = startUTF16Index
    self.endLine = endLine
    self.endUTF16Index = endUTF16Index
    self.kind = kind
    self.collapsedText = collapsedText
  }
}

extension FoldingRange: Codable {
  private enum CodingKeys: String, CodingKey {
    case startLine
    case startUTF16Index = "startCharacter"
    case endLine
    case endUTF16Index = "endCharacter"
    case kind
  }
}

extension FoldingRange: Comparable {

  public static func <(lhs: FoldingRange, rhs: FoldingRange) -> Bool {
    return lhs.comparableKey < rhs.comparableKey
  }

  private var comparableKey: (Int, Int, Int, Int, String) {
    return (
      startLine,
      startUTF16Index ?? Int.max,
      endLine, endUTF16Index ?? Int.max,
      kind?.rawValue ?? "")
  }
}
