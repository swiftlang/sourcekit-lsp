//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// High level categorization of a file state.
public struct SourceKitFileState: RawRepresentable, Codable, Hashable {

  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  // MARK: - File states v1

  /// Components are still initializing (e.g. waiting for a response from the
  /// build system).
  public static let initializing = SourceKitFileState(rawValue: "initializing")

  /// Language server working (e.g. building AST).
  public static let working = SourceKitFileState(rawValue: "working")

  /// Language server ready (e.g. AST available).
  public static let ready = SourceKitFileState(rawValue: "ready")
}
