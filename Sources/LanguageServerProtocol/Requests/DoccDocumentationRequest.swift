//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request that generates documentation for a symbol at a given cursor location **(LSP Extension)**.
///
/// Primarily designed to support live preview of Swift documentation in editors.
///
/// This request looks up the nearest documentable symbol (if any) at a given cursor location within
/// a text document and returns a `DoccDocumentationResponse`. The response contains a string
/// representing single JSON encoded DocC RenderNode. This RenderNode can then be rendered in an
/// editor via https://github.com/swiftlang/swift-docc-render.
///
/// The position may be ommitted for documentation within DocC markdown and tutorial files as they
/// represent a single documentation page. It is only required for generating documentation within
/// Swift files as they usually contain multiple documentable symbols.
///
/// Documentation can fail to be generated for a number of reasons. The most common of which being
/// that no documentable symbol could be found. In such cases the request will fail with a request
/// failed LSP error code (-32803) that contains a human-readable error message. This error message can
/// be displayed within the live preview editor to indicate that something has gone wrong.
///
/// At the moment this request is only available on macOS and Linux. SourceKit-LSP will advertise
/// `textDocument/doccDocumentation` in its experimental server capabilities if it supports it.
///
/// - Parameters:
///   - textDocument: The document to generate documentation for.
///   - position: The cursor position within the document. (optional)
///
/// - Returns: A `DoccDocumentationResponse` for the given location, which may contain an error
///   message if documentation could not be converted. This error message can be displayed to the user
///   in the live preview editor.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP.
/// The client is expected to display the documentation in an editor using swift-docc-render.
public struct DoccDocumentationRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/doccDocumentation"
  public typealias Response = DoccDocumentationResponse

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position?

  public init(textDocument: TextDocumentIdentifier, position: Position? = nil) {
    self.textDocument = textDocument
    self.position = position
  }
}

public struct DoccDocumentationResponse: ResponseType, Equatable {
  public var renderNode: String

  public init(renderNode: String) {
    self.renderNode = renderNode
  }
}
