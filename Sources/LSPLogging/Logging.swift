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
///  - Notice/log/default: Essential for troubleshooting
///  - Error: Error seen during execution
///    - Used eg. if the user sends an erroneous request or if a request fails
///  - Fault: Bug in program
///    - Used eg. if invariants inside sourcekit-lsp are broken and the error is not due to user-provided input

import Foundation

#if canImport(os) && !SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER
import os  // os_log

public typealias LogLevel = os.OSLogType
public typealias Logger = os.Logger
public typealias Signposter = OSSignposter

#if compiler(<5.11)
extension OSSignposter: @unchecked Sendable {}
extension OSSignpostID: @unchecked Sendable {}
extension OSSignpostIntervalState: @unchecked Sendable {}
#else
extension OSSignposter: @retroactive @unchecked Sendable {}
extension OSSignpostID: @retroactive @unchecked Sendable {}
extension OSSignpostIntervalState: @retroactive @unchecked Sendable {}
#endif

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
  Logger(subsystem: LoggingScope.subsystem, category: LoggingScope.scope)
}
