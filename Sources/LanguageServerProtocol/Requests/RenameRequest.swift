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

/// Request to compute a workspace range to rename a symbol. The change is then performed client side.
///
/// Looks up the symbol at the given position and returns the range of the symbol the user is renaming,
/// or null if there is no symbol to be renamed at the given position
///
/// Servers that allow renaming should set the `renameProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document in which the selected symbol is.
///   - position: The document location at which the selected symbol is.
///   - newName: The new name of the symbol.
///
/// - Returns: A workspace edit
public struct RenameRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/rename"
  public typealias Response = WorkspaceEdit?

  /// The document in which the selected symbol is.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which the selected symbol is.
  public var position: Position

  /// The new name of the symbol. If the given name is not valid the request must return
  /// a ResponseError with an appropriate message set.
  public var newName: String

  public init(textDocument: TextDocumentIdentifier, position: Position, newName: String) {
    self.textDocument = textDocument
    self.position = position
    self.newName = newName
  }
}
