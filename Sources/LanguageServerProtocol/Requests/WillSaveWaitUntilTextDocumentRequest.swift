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

/// The document will save request is sent from the client to the server before the document is actually saved. The request can return an array of TextEdits which will be applied to the text document before it is saved. Please note that clients might drop results if computing the text edits took too long or if a server constantly fails on this request. This is done to keep the save fast and reliable. If a server has registered for open / close events clients should ensure that the document is open before a willSaveWaitUntil notification is sent since clients can’t change the content of a file without ownership transferal.
public struct WillSaveWaitUntilTextDocumentRequest: RequestType {
  public static let method: String = "textDocument/willSaveWaitUntil"
  public typealias Response = [TextEdit]?

  /// The document that will be saved.
  public var textDocument: TextDocumentIdentifier

  public var reason: TextDocumentSaveReason

  public init(textDocument: TextDocumentIdentifier, reason: TextDocumentSaveReason) {
    self.textDocument = textDocument
    self.reason = reason
  }
}
