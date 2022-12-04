//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A document identifier representing a specific version of the document.
///
/// Notionally a subtype of `TextDocumentIdentifier`.
public struct VersionedTextDocumentIdentifier: Hashable, Codable {

  /// A URI that uniquely identifies the document.
  public var uri: DocumentURI

  /// The version number of this document.
  ///
  /// The version number of a document will increase after each change,
  /// including undo/redo. The number doesn't need to be consecutive.
  public var version: Int

  public init(_ uri: DocumentURI, version: Int) {
    self.uri = uri
    self.version = version
  }
}

/// An identifier which optionally denotes a specific version of a text document. This information usually flows from the server to the client.
///
/// Notionally a subtype of `TextDocumentIdentifier`.
public struct OptionalVersionedTextDocumentIdentifier: Hashable, Codable {

  /// A URI that uniquely identifies the document.
  public var uri: DocumentURI

  /// The version number of this document. If an optional versioned text document
  /// identifier is sent from the server to the client and the file is not
  /// open in the editor (the server has not received an open notification
  /// before) the server can send `null` to indicate that the version is
  /// known and the content on disk is the master (as specified with document
  /// content ownership).
  ///
  /// The version number of a document will increase after each change,
  /// including undo/redo. The number doesn't need to be consecutive.
  public var version: Int?

  public init(_ uri: DocumentURI, version: Int?) {
    self.uri = uri
    self.version = version
  }
}
