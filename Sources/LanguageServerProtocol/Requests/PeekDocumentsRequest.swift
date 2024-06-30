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

/// Request from the server to the client to show the given documents in a "peeked" editor **(LSP Extension)**
///
/// This request is handled by the client to show the given documents in a
/// "peeked" editor (i.e. inline with / inside the editor canvas). This is
/// similar to VS Code's built-in "editor.action.peekLocations" command.
///
/// - Parameters:
///   - uri: The URI of the text document in which to show the "peeked" editor
/// (default: nil, current document in the active editor handled by the client)
///   - position: The position in the given text document in which to show the
/// "peeked editor" (default: nil, current cursor position in the active editor handled by the client)
///   - locations: The URIs of documents to appear inside the "peeked" editor
///   - multiple: Presentation strategy when having multiple locations (default: "peek")
///
/// - Returns: `PeekDocumentsResponse` which indicates the `success` of the request.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP and clangd.
/// It requires the experimental client capability `"peekDocuments"` to use.
/// It also needs the client to handle the request and present the "peeked" editor.
public struct PeekDocumentsRequest: RequestType {
  public static let method: String = "sourcekit-lsp/peekDocuments"
  public typealias Response = PeekDocumentsResponse

  public var uri: DocumentURI?
  public var position: Position?
  public var locations: [DocumentURI]
  public var multiple: Multiple

  public init(
    uri: DocumentURI? = nil,
    position: Position? = nil,
    locations: [DocumentURI],
    multiple: Multiple = .peek
  ) {
    self.uri = uri
    self.position = position
    self.locations = locations
    self.multiple = multiple
  }
}

/// Response to indicate the `success` of the `PeekDocumentsRequest`
public struct PeekDocumentsResponse: ResponseType {
  public var success: Bool

  public init(success: Bool) {
    self.success = success
  }
}

/// The presentation strategies that can be used when having multiple locations
public enum Multiple: String, Sendable, Codable {
  case peek
  case goto
  case gotoAndPeek
}
