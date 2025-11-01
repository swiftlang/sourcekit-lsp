//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A request that returns #Playground macro expansion locations within a file.
///
/// **(LSP Extension)**
public struct DocumentPlaygroundsRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/playgrounds"
  public typealias Response = [PlaygroundItem]

  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}
