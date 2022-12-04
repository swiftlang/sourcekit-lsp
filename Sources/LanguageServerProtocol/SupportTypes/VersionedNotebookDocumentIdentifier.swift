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

/// Unique identifier for a document.
public struct VersionedNotebookDocumentIdentifier: Codable, Hashable {

  /// The version number of this notebook document.
  public var version: Int

  /// The notebook document's URI.
  public var uri: DocumentURI

  public init(version: Int, uri: DocumentURI) {
    self.version = version
    self.uri = uri
  }
}
