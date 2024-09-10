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

import LanguageServerProtocol

public struct TextDocumentIdentifier: Codable, Sendable, Hashable {
  /// The text document's URI.
  public var uri: URI

  public init(uri: URI) {
    self.uri = uri
  }
}

/// The inverse sources request is sent from the client to the server to query for the list of build targets containing
/// a text document. The server communicates during the initialize handshake whether this method is supported or not.
/// This request can be viewed as the inverse of buildTarget/sources, except it only works for text documents and not
/// directories.
public struct InverseSourcesRequest: RequestType, Hashable {
  public static let method: String = "buildTarget/inverseSources"
  public typealias Response = InverseSourcesResponse

  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

public struct InverseSourcesResponse: ResponseType, Hashable {
  public var targets: [BuildTargetIdentifier]

  public init(targets: [BuildTargetIdentifier]) {
    self.targets = targets
  }
}
