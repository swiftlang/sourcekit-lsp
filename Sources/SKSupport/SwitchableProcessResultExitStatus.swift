//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.ProcessResult

/// Same as `ProcessResult.ExitStatus` in tools-support-core but has the same cases on all platforms and is thus easier
/// to switch over
public enum SwitchableProcessResultExitStatus {
  /// The process was terminated normally with a exit code.
  case terminated(code: Int32)
  /// The process was terminated abnormally.
  case abnormal(exception: UInt32)
  /// The process was terminated due to a signal.
  case signalled(signal: Int32)

  /// A description of the exit status that can be used in sentences like `Finished with <exit status description>`.
  public var description: String {
    switch self {
    case .terminated(code: let code):
      "exit code \(code)"
    case .abnormal(exception: let exception):
      "exception \(exception)"
    case .signalled(signal: let signal):
      "signal \(signal)"
    }
  }
}

extension ProcessResult.ExitStatus {
  public var exhaustivelySwitchable: SwitchableProcessResultExitStatus {
    #if os(Windows)
    switch self {
    case .terminated(let code):
      return .terminated(code: code)
    case .abnormal(let exception):
      return .abnormal(exception: exception)
    }
    #else
    switch self {
    case .terminated(let code):
      return .terminated(code: code)
    case .signalled(let signal):
      return .signalled(signal: signal)
    }
    #endif
  }
}
