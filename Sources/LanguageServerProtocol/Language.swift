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

/// A source code language identifier, such as "swift", or "objective-c".
public enum Language: String, Codable, Hashable {
  case c
  case cpp // C++, not C preprocessor
  case objective_c = "objective-c"
  case objective_cpp = "objective-cpp"
  case swift

  case unknown

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let str = try container.decode(String.self)
    if let value = Language(rawValue: str) {
      self = value
    } else {
      self = .unknown
    }
  }

  /// Clang-compatible language name suitable for use with `-x <language>`.
  public var xflag: String? {
    switch self {
      case .swift: return "swift"
      case .c: return "c"
      case .cpp: return "c++"
      case .objective_c: return "objective-c"
      case .objective_cpp: return "objective-c++"
      case .unknown: return nil
    }
  }

  /// Clang-compatible language name for a header file. See `xflag`.
  public var xflagHeader: String? {
    return xflag.map { "\($0)-header" }
  }
}
