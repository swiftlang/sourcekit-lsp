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

public struct IsIndexingRequest: LSPRequest {
  public static let method: String = "sourceKit/_isIndexing"
  public typealias Response = IsIndexingResponse

  public init() {}
}

public struct IsIndexingResponse: ResponseType {
  /// Whether SourceKit-LSP is currently performing an indexing task.
  public var indexing: Bool

  public init(indexing: Bool) {
    self.indexing = indexing
  }
}
