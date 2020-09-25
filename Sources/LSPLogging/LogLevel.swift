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

#if canImport(os)
import os
#endif

public enum LogLevel: Int, Equatable {
  case error = 0
  case warning = 1
  case info = 2
  case debug = 3

  public static let `default`: LogLevel = .info
}

extension LogLevel: Comparable {
  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}

extension LogLevel: CustomStringConvertible {

  public var description: String {
    switch self {
    case .error:
      return "error"
    case .warning:
      return "warning"
    case .info:
      return "info"
    case .debug:
      return "debug"
    }
  }
}

extension LogLevel {
  public init?(argument: String) {
    switch argument {
    case "error":
      self = .error
    case "warning":
      self = .warning
    case "info":
      self = .info
    case "debug":
      self = .debug
    default:

      // Also accept a numerical log level, for parity with SOURCEKIT_LOGGING environment variable.
      guard let value = Int(argument) else {
        return nil
      }

      if let level = LogLevel(rawValue: value) {
        self = level
      } else if value > LogLevel.debug.rawValue  {
        self = .debug
      } else {
        return nil
      }
    }
  }

}

#if canImport(os)
extension LogLevel {
  @available(OSX 10.12, *)
  public var osLogType: OSLogType {
    switch self {
    case .debug:
      return .debug
    case .info:
      return .info
    case .warning:
      return .default
    case .error:
      return .error
    }
  }
}
#endif
