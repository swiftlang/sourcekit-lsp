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

/// A folding range kind.
///
/// In LSP, this is a string, so we don't use a closed set.
public struct FoldingRangeKind: RawRepresentable, Codable, Hashable {

  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Folding range for a comment.
  public static let comment: FoldingRangeKind = FoldingRangeKind(rawValue: "comment")

  /// Folding range for imports or includes.
  public static let imports: FoldingRangeKind = FoldingRangeKind(rawValue: "imports")

  /// Folding range for a region (e.g. C# `#region`).
  public static let region: FoldingRangeKind = FoldingRangeKind(rawValue: "region")
}
