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

public struct DocumentSemanticTokenRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/semanticTokens"
  public typealias Response = DocumentSemanticTokenResponse?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

public struct DocumentSemanticTokenResponse: ResponseType, Hashable {
  public var data: [Int]

  public init(data: [Int]) {
    self.data = data
  }
}
