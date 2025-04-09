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

import Foundation

#if canImport(os) && !SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER
@_exported public import os  // os_log

package typealias LogLevel = os.OSLogType
package typealias Logger = os.Logger
package typealias Signposter = OSSignposter

extension OSSignposter: @retroactive @unchecked Sendable {}
extension OSSignpostID: @retroactive @unchecked Sendable {}
extension OSSignpostIntervalState: @retroactive @unchecked Sendable {}

extension os.Logger {
  package func makeSignposter() -> Signposter {
    return OSSignposter(logger: self)
  }
}
#else
package typealias LogLevel = NonDarwinLogLevel
package typealias Logger = NonDarwinLogger
package typealias Signposter = NonDarwinSignposter
#endif

/// The logger that is used to log any messages.
package var logger: Logger {
  Logger(subsystem: LoggingScope.subsystem, category: LoggingScope.scope)
}
