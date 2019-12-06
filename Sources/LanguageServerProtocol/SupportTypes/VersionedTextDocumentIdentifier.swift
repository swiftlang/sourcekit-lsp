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

  /// The version number of this document, or nil if unknown.
  public var version: Int?

  public init(_ uri: DocumentURI, version: Int?) {
    self.uri = uri
    self.version = version
  }
}
