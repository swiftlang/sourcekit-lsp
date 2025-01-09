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

/// Request for generating documentation for the symbol at a given location **(LSP Extension)**.
///
/// This request looks up the symbol (if any) at a given text document location and returns a
/// ``DoccDocumentationResponse`` for that location. This request is primarily designed for editors
/// to support live preview of Swift documentation.
///
/// - Parameters:
///   - textDocument: The document to render documentation for.
///   - position: The document location at which to lookup symbol information. (optional)
///
/// - Returns: A ``DoccDocumentationResponse`` for the given location, which may contain an error
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
