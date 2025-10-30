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

/// New request to modify runtime options of SourceKit-LSP.
//
/// Any options not specified in this request will be left as-is.
public struct SetOptionsRequest: LSPRequest {
  public static let method: String = "workspace/_setOptions"
  public typealias Response = VoidResponse

  /// `true` to pause background indexing or `false` to resume background indexing.
  public var backgroundIndexingPaused: Bool?

  public init(backgroundIndexingPaused: Bool?) {
    self.backgroundIndexingPaused = backgroundIndexingPaused
  }
}
