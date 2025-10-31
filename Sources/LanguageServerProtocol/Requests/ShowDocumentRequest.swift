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

/// Request from the server to the client to show a document on the client
/// side.
public struct ShowDocumentRequest: LSPRequest {
  public static let method: String = "window/showDocument"
  public typealias Response = ShowDocumentResponse

  /// The uri to show.
  public var uri: DocumentURI

  /// An optional boolean indicates to show the resource in an external
  /// program. To show, for example, `https://www.swift.org/ in the default WEB
  /// browser set `external` to `true`.
  public var external: Bool?

  /// An optional boolean to indicate whether the editor showing the document
  /// should take focus or not. Clients might ignore this property if an
  /// external program is started.
  public var takeFocus: Bool?

  /// An optional selection range if the document is a text document. Clients
  /// might ignore the property if an external program is started or the file
  /// is not a text file.
  public var selection: Range<Position>?

  public init(uri: DocumentURI, external: Bool? = nil, takeFocus: Bool? = nil, selection: Range<Position>? = nil) {
    self.uri = uri
    self.external = external
    self.takeFocus = takeFocus
    self.selection = selection
  }
}

public struct ShowDocumentResponse: Codable, Hashable, ResponseType {
  /// A boolean indicating if the show was successful.
  public var success: Bool

  public init(success: Bool) {
    self.success = success
  }
}
