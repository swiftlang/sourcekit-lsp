//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Which log level to use (from https://developer.apple.com/wwdc20/10168?time=604)
///  - Debug: Useful only during debugging (only logged during debugging)
///  - Info: Helpful but not essential for troubleshooting (not persisted, logged to memory)
///  - Notice/log (Default): Essential for troubleshooting
///  - Error: Error seen during execution
///  - Fault: Bug in program

import Foundation

/// The subsystem that should be used for any logging by default.
public let subsystem = "org.swift.sourcekit-lsp"

#if canImport(os) && !SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER
import os  // os_log

public typealias LogLevel = os.OSLogType
public typealias Logger = os.Logger
public typealias Signposter = OSSignposter

extension os.Logger {
  public func makeSignposter() -> Signposter {
    return OSSignposter(logger: self)
  }
}
#else
public typealias LogLevel = NonDarwinLogLevel
public typealias Logger = NonDarwinLogger
public typealias Signposter = NonDarwinSignposter
#endif

/// The logger that is used to log any messages.
public var logger: Logger {
  Logger(subsystem: subsystem, category: LoggingScope.scope)
}
