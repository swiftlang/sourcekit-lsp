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

public struct DidChangeActiveDocumentNotification: LSPNotification {
  public static let method: String = "window/didChangeActiveDocument"

  /// The document that is being displayed in the active editor  or `null` to indicate that either no document is active
  /// or that the currently open document is not handled by SourceKit-LSP.
  public var textDocument: TextDocumentIdentifier?

  public init(textDocument: TextDocumentIdentifier?) {
    self.textDocument = textDocument
  }
}
