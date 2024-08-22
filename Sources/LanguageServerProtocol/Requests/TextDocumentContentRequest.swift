//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request from the client to the server asking for contents of a URI having a custom scheme
/// For example: "sourcekit-lsp:"
///
/// - Parameters:
///   - uri: The `DocumentUri` of the custom scheme url for which content is required
///
/// - Returns: `TextDocumentContentResponse` which contains the `content` to be displayed.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP.
/// Enable the experimental client capability `"workspace/textDocumentContent"` so that the server responds with
/// reference document URLs for certain requests or commands whenever possible.
public struct TextDocumentContentRequest: RequestType {
  public static let method: String = "workspace/textDocumentContent"
  public typealias Response = TextDocumentContentResponse

  public var uri: DocumentURI

  public init(uri: DocumentURI) {
    self.uri = uri
  }
}

/// Response containing `text` of `TextDocumentContentRequest`
public struct TextDocumentContentResponse: ResponseType {
  public var text: String

  public init(text: String) {
    self.text = text
  }
}
