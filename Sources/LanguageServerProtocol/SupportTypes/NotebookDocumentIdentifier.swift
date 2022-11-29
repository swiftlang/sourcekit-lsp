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

/// A literal to identify a notebook document in the client.
public struct NotebookDocumentIdentifier: Hashable, Codable {

  /// The notebook document's URI.
  public var uri: DocumentURI

  public init(_ uri: DocumentURI) {
    self.uri = uri
  }
}
