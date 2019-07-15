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
public struct Language: RawRepresentable, Codable, Equatable, Hashable {
  public typealias LanguageId = String

  public static let c = Language(rawValue: "c")
  public static let cpp = Language(rawValue: "cpp") // C++, not C preprocessor
  public static let objective_c = Language(rawValue: "objective-c")
  public static let objective_cpp = Language(rawValue: "objective-cpp")
  public static let swift = Language(rawValue: "swift")

  public let rawValue: LanguageId
  public init(rawValue: LanguageId) {
    self.rawValue = rawValue
  }

  /// Clang-compatible language name suitable for use with `-x <language>`.
  public var xflag: String? {
    switch self {
      case .swift: return "swift"
      case .c: return "c"
      case .cpp: return "c++"
      case .objective_c: return "objective-c"
      case .objective_cpp: return "objective-c++"
      default: return nil
    }
  }

  /// Clang-compatible language name for a header file. See `xflag`.
  public var xflagHeader: String? {
    return xflag.map { "\($0)-header" }
  }

  public static func ~= (lhs: Language, rhs: Language) -> Bool {
    return lhs.rawValue == rhs.rawValue
  }
}

extension Language: CustomStringConvertible {
  public var description: String {
    return rawValue
  }
}
