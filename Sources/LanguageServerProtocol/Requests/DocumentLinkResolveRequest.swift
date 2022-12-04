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

/// The document links request is sent from the client to the server to request the location of links in a document.
public struct DocumentLinkResolveRequest: RequestType {
  public static let method: String = "documentLink/resolve"
  public typealias Response = DocumentLink

  public var documentLink: DocumentLink

  public init(documentLink: DocumentLink) {
    self.documentLink = documentLink
  }

  public init(from decoder: Decoder) throws {
    self.documentLink = try DocumentLink(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try self.documentLink.encode(to: encoder)
  }
}
