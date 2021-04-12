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

public struct DocumentSemanticTokensRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/semanticTokens/full"
  public typealias Response = DocumentSemanticTokensResponse?

  /// The document to fetch semantic tokens for.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

public struct DocumentSemanticTokensResponse: ResponseType, Hashable {
  /// An optional result identifier which enables supporting clients to request semantic token deltas
  /// subsequent requests.
  public var resultId: String?

  /// Raw tokens data.
  public var data: [UInt32]

  public init(resultId: String? = nil, data: [UInt32]) {
    self.resultId = resultId
    self.data = data
  }
}
