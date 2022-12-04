//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A set of predefined position encoding kinds.
public struct PositionEncodingKind: RawRepresentable, Codable, Hashable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Character offsets count UTF-8 code units.
  public static let utf8: PositionEncodingKind = PositionEncodingKind(rawValue: "utf-8")

  /// Character offsets count UTF-16 code units.
  ///
  /// This is the default and must always be supported
  /// by servers
  public static let utf16: PositionEncodingKind = PositionEncodingKind(rawValue: "utf-16")

   /// Character offsets count UTF-32 code units.
   ///
   /// Implementation note: these are the same as Unicode code points,
   /// so this `PositionEncodingKind` may also be used for an
   /// encoding-agnostic representation of character offsets.
  public static let utf32: PositionEncodingKind = PositionEncodingKind(rawValue: "utf-32")
}
