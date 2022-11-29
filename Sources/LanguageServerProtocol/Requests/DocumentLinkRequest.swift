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
public struct DocumentLinkRequest: RequestType {
  public static let method: String = "textDocument/documentLink"
  public typealias Response = [DocumentLink]?

  /// The document to provide document links for.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

/// A document link is a range in a text document that links to an internal or
/// external resource, like another text document or a web site.
public struct DocumentLink: ResponseType, Hashable {
  /// The range this link applies to.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// The uri this link points to. If missing a resolve request is sent later.
  public var target: DocumentURI?

  /// The tooltip text when you hover over this link.
  ///
  /// If a tooltip is provided, is will be displayed in a string that includes
  /// instructions on how to trigger the link, such as `{0} (ctrl + click)`.
  /// The specific instructions vary depending on OS, user settings, and
  /// localization.
  public var tooltip: String?

  /// A data entry field that is preserved on a document link between a
  /// DocumentLinkRequest and a DocumentLinkResolveRequest.
  public var data: LSPAny?

  public init(range: Range<Position>, target: DocumentURI? = nil, tooltip: String? = nil, data: LSPAny? = nil) {
    self.range = range
    self.target = target
    self.tooltip = tooltip
    self.data = data
  }
}
