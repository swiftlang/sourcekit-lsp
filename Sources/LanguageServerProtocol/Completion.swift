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

/// Request for code-completion items at the given document location.
///
/// The server may - or may not - filter and sort the results before returning them. If the server
/// performs server-side filtering, it should set the `isIncomplete` flag on the result. However,
/// since there are no particular rules specified for server-side filtering, the client likely will
/// want to perform its own filtering as well.
///
/// Servers that provide document highlights should set the `completionProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document to perform completion in.
///   - position: The location to perform completion at.
///
/// - Returns: A list of completion items to complete the code at the given position.
public struct CompletionRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/completion"
  public typealias Response = CompletionList

  public var textDocument: TextDocumentIdentifier

  public var position: Position

  // public var context: CompletionContext?

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// List of completion items. If this list has been filtered already, the `isIncomplete` flag
/// indicates that the client should re-query code-completions if the filter text changes.
public struct CompletionList: ResponseType, Hashable {

  /// Whether the list of completions is "complete" or not.
  ///
  /// When this value is `true`, the client should re-query the server when doing further filtering.
  public var isIncomplete: Bool

  /// The resulting completions.
  public var items: [CompletionItem]

  public init(isIncomplete: Bool, items: [CompletionItem]) {
    self.isIncomplete = isIncomplete
    self.items = items
  }
}
