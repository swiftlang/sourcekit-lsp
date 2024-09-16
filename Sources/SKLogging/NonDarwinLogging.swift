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

import SwiftExtensions

#if canImport(Darwin)
import Foundation
#else
// TODO: @preconcurrency needed because stderr is not sendable on Linux https://github.com/swiftlang/swift/issues/75601
@preconcurrency import Foundation
#endif

// MARK: - Log settings

package enum LogConfig {
  /// The globally set log level
  package static let logLevel = ThreadSafeBox<NonDarwinLogLevel>(
    initialValue: {
      if let envVar = ProcessInfo.processInfo.environment["SOURCEKITLSP_LOG_LEVEL"],
        let logLevel = NonDarwinLogLevel(envVar)
      {
        return logLevel
      }
      #if DEBUG
      return .debug
      #else
      return .default
      #endif
    }()
  )

  /// The globally set privacy level
  package static let privacyLevel = ThreadSafeBox<NonDarwinLogPrivacy>(
    initialValue: {
      if let envVar = ProcessInfo.processInfo.environment["SOURCEKITLSP_LOG_PRIVACY_LEVEL"],
        let privacyLevel = NonDarwinLogPrivacy(envVar)
      {
        return privacyLevel
      }
      #if DEBUG
      return .private
      #else
      return .public
      #endif
    }()
  )
}

/// A type that is API-compatible to `OSLogType` for all uses within
/// sourcekit-lsp.
///
/// This is used on platforms that don't have OSLog.
///
/// For documentation of the different log levels see
/// https://developer.apple.com/documentation/os/oslogtype.
package enum NonDarwinLogLevel: Comparable, CustomStringConvertible, Sendable {
  case debug
  case info
  case `default`
  case error
  case fault

  package init?(_ value: String) {
    switch value.lowercased() {
    case "debug": self = .debug
    case "info": self = .info
    case "default": self = .`default`
    case "error": self = .error
    case "fault": self = .fault
    default:
      if let int = Int(value) {
        self.init(int)
      } else {
        return nil
      }
    }
  }

  package init?(_ value: Int) {
    switch value {
    case 0: self = .fault
    case 1: self = .error
    case 2: self = .default
    case 3: self = .info
    case 4: self = .debug
    default: return nil
    }
  }

  package var description: String {
    switch self {
    case .debug:
      return "debug"
    case .info:
      return "info"
    case .default:
      return "default"
    case .error:
      return "error"
    case .fault:
      return "fault"
    }
  }
}

/// A type that is API-compatible to `OSLogPrivacy` for all uses within
/// sourcekit-lsp.
///
/// This is used on platforms that don't have OSLog.
///
/// For documentation of the different privacy levels see
/// https://developer.apple.com/documentation/os/oslogprivacy.
package enum NonDarwinLogPrivacy: Comparable, Sendable {
  case `public`
  case `private`
  case sensitive

  package init?(_ value: String) {
    switch value.lowercased() {
    case "sensitive": self = .sensitive
    case "private": self = .private
    case "public": self = .public
    default: return nil
    }
  }
}

// MARK: String interpolation

/// A type that is API-compatible to `OSLogInterpolation` for all uses within
/// sourcekit-lsp.
///
/// This is used on platforms that don't have OSLog.
package struct NonDarwinLogInterpolation: StringInterpolationProtocol, Sendable {
  private enum LogPiece: Sendable {
    /// A segment of the log message that will always be displayed.
    case string(String)

    /// A segment of the log message that might need to be redacted if the
    /// privacy level is lower than `privacy`.
    case possiblyRedacted(
      description: @Sendable () -> String,
      redactedDescription: @Sendable () -> String,
      privacy: NonDarwinLogPrivacy
    )
  }

  private var pieces: [LogPiece]

  package init(literalCapacity: Int, interpolationCount: Int) {
    self.pieces = []
    pieces.reserveCapacity(literalCapacity + interpolationCount)
  }

  package mutating func appendLiteral(_ literal: String) {
    pieces.append(.string(literal))
  }

  private mutating func append(
    description: @autoclosure @escaping @Sendable () -> String,
    redactedDescription: @autoclosure @escaping @Sendable () -> String,
    privacy: NonDarwinLogPrivacy
  ) {
    if privacy == .public {
      // We are always logging the description. No need to store the redacted description as well.
      pieces.append(.string(description()))
    } else {
      pieces.append(
        .possiblyRedacted(
          description: description,
          redactedDescription: redactedDescription,
          privacy: privacy
        )
      )
    }
  }

  package mutating func appendInterpolation(_ message: StaticString, privacy: NonDarwinLogPrivacy = .public) {
    append(description: message.description, redactedDescription: "<private>", privacy: privacy)
  }

  @_disfavoredOverload  // Prefer to use the StaticString overload when possible.
  package mutating func appendInterpolation(
    _ message: some CustomStringConvertible & Sendable,
    privacy: NonDarwinLogPrivacy = .private
  ) {
    append(description: message.description, redactedDescription: "<private>", privacy: privacy)
  }

  package mutating func appendInterpolation(
    _ message: some CustomLogStringConvertibleWrapper & Sendable,
    privacy: NonDarwinLogPrivacy = .private
  ) {
    append(description: message.description, redactedDescription: message.redactedDescription, privacy: privacy)
  }

  package mutating func appendInterpolation(
    _ message: (some CustomLogStringConvertibleWrapper & Sendable)?,
    privacy: NonDarwinLogPrivacy = .private
  ) {
    if let message {
      self.appendInterpolation(message, privacy: privacy)
    } else {
      self.appendLiteral("<nil>")
    }
  }

  package mutating func appendInterpolation(_ type: Any.Type, privacy: NonDarwinLogPrivacy = .public) {
    append(description: String(reflecting: type), redactedDescription: "<private>", privacy: privacy)
  }

  /// Builds the string that represents the log message, masking all interpolation
  /// segments whose privacy level is greater that `logPrivacyLevel`.
  fileprivate func string(for logPrivacyLevel: NonDarwinLogPrivacy) -> String {
    var result = ""
    for piece in pieces {
      switch piece {
      case .string(let string):
        result += string
      case .possiblyRedacted(description: let description, redactedDescription: let redacted, privacy: let privacy):
        if privacy > logPrivacyLevel {
          result += redacted()
        } else {
          result += description()
        }
      }
    }
    return result
  }
}

/// A type that is API-compatible to `OSLogMessage` for all uses within
/// sourcekit-lsp.
///
/// This is used on platforms that don't have OSLog.
package struct NonDarwinLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
  fileprivate let value: NonDarwinLogInterpolation

  package init(stringInterpolation: NonDarwinLogInterpolation) {
    self.value = stringInterpolation
  }

  package init(stringLiteral value: String) {
    var interpolation = NonDarwinLogInterpolation(literalCapacity: 1, interpolationCount: 0)
    interpolation.appendLiteral(value)
    self.value = interpolation
  }
}

// MARK: - Logger

/// The formatter used to format dates in log messages.
///
/// A global variable because we frequently create new loggers, the creation of
/// a new `DateFormatter` is rather expensive and its the same for all loggers.
private let dateFormatter = {
  let dateFormatter = DateFormatter()
  dateFormatter.timeZone = NSTimeZone.local
  dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
  return dateFormatter
}()

/// Actor that protects `logHandler`
@globalActor
actor LogHandlerActor {
  static var shared: LogHandlerActor = LogHandlerActor()
}

/// The handler that is called to log a message from `NonDarwinLogger` unless `overrideLogHandler` is set on the logger.
@LogHandlerActor
var logHandler: @Sendable (String) async -> Void = { fputs($0 + "\n", stderr) }

/// The queue on which we log messages.
///
/// A global queue since we create and discard loggers all the time.
private let loggingQueue = AsyncQueue<Serial>()

/// A logger that is designed to be API-compatible with `os.Logger` for all uses
/// in sourcekit-lsp.
///
/// This logger is used to log messages to stderr on platforms where OSLog is
/// not available.
///
/// `overrideLogHandler` allows capturing of the logged messages for testing purposes.
package struct NonDarwinLogger: Sendable {
  private let subsystem: String
  private let category: String
  private let logLevel: NonDarwinLogLevel
  fileprivate let privacyLevel: NonDarwinLogPrivacy
  private let overrideLogHandler: (@Sendable (String) -> Void)?

  /// - Parameters:
  ///   - subsystem: See os.Logger
  ///   - category: See os.Logger
  ///   - logLevel: The level to log at. All messages with a lower log level
  ///     will be ignored
  ///   - privacyLevel: The privacy level to log at. Any interpolation segments
  ///     with a higher privacy level will be masked.
  ///   - logHandler: The function that actually logs the message.
  package init(
    subsystem: String,
    category: String,
    logLevel: NonDarwinLogLevel? = nil,
    privacyLevel: NonDarwinLogPrivacy? = nil,
    overrideLogHandler: (@Sendable (String) -> Void)? = nil
  ) {
    self.subsystem = subsystem
    self.category = category
    self.logLevel = logLevel ?? LogConfig.logLevel.value
    self.privacyLevel = privacyLevel ?? LogConfig.privacyLevel.value
    self.overrideLogHandler = overrideLogHandler
  }

  /// Logs the given message at the given level.
  ///
  /// Logging is performed asynchronously to allow the execution of the main
  /// program to finish as quickly as possible.
  package func log(
    level: NonDarwinLogLevel,
    _ message: @autoclosure @escaping @Sendable () -> NonDarwinLogMessage
  ) {
    guard level >= self.logLevel else { return }
    let date = Date()
    loggingQueue.async(priority: .utility) { @LogHandlerActor in
      // Truncate log message after 10.000 characters to avoid flooding the log with huge log messages (eg. from a
      // sourcekitd response). 10.000 characters was chosen because it seems to fit the result of most sourcekitd
      // responses that are not generated interface or global completion results (which are a lot bigger).
      var message = message().value.string(for: self.privacyLevel)
      if message.utf8.count > 10_000 {
        // Check for UTF-8 byte length first because that's faster since it doesn't need to count UTF-8 characters.
        // Truncate using `.prefix` to avoid cutting of in the middle of a UTF-8 multi-byte character.
        message = message.prefix(10_000) + "..."
      }
      // Start each log message with `[org.swift.sourcekit-lsp` so that it’s easy to split the log to the different messages
      await (overrideLogHandler ?? logHandler)(
        """
        [\(subsystem):\(category)] \(level) \(dateFormatter.string(from: date))
        \(message)
        ---
        """
      )
    }
  }

  /// Log a message at the `debug` level.
  package func debug(_ message: NonDarwinLogMessage) {
    log(level: .debug, message)
  }

  /// Log a message at the `info` level.
  package func info(_ message: NonDarwinLogMessage) {
    log(level: .info, message)
  }

  /// Log a message at the `default` level.
  package func log(_ message: NonDarwinLogMessage) {
    log(level: .default, message)
  }

  /// Log a message at the `error` level.
  package func error(_ message: NonDarwinLogMessage) {
    log(level: .error, message)
  }

  /// Log a message at the `fault` level.
  package func fault(_ message: NonDarwinLogMessage) {
    log(level: .fault, message)
  }

  /// Wait for all log messages to be written.
  ///
  /// Useful for testing to make sure all asynchronous log calls have actually
  /// written their data.
  package static func flush() async {
    await loggingQueue.async {}.value
  }

  package func makeSignposter() -> NonDarwinSignposter {
    return NonDarwinSignposter(logger: self)
  }
}

// MARK: - Signposter

package struct NonDarwinSignpostID: Sendable {
  fileprivate let id: UInt32
}

package struct NonDarwinSignpostIntervalState: Sendable {
  fileprivate let id: NonDarwinSignpostID
}

private let nextSignpostID = AtomicUInt32(initialValue: 0)

/// A type that is API-compatible to `OSLogMessage` for all uses within sourcekit-lsp.
///
/// Since non-Darwin platforms don't have signposts, the type just has no-op operations.
package struct NonDarwinSignposter: Sendable {
  private let logger: NonDarwinLogger

  fileprivate init(logger: NonDarwinLogger) {
    self.logger = logger
  }

  package func makeSignpostID() -> NonDarwinSignpostID {
    return NonDarwinSignpostID(id: nextSignpostID.fetchAndIncrement())
  }

  package func beginInterval(
    _ name: StaticString,
    id: NonDarwinSignpostID,
    _ message: NonDarwinLogMessage
  ) -> NonDarwinSignpostIntervalState {
    logger.log(level: .debug, "Signpost \(id.id) begin: \(name) - \(message.value.string(for: logger.privacyLevel))")
    return NonDarwinSignpostIntervalState(id: id)
  }

  package func emitEvent(_ name: StaticString, id: NonDarwinSignpostID, _ message: NonDarwinLogMessage = "") {
    logger.log(level: .debug, "Signpost \(id.id) event: \(name) - \(message.value.string(for: logger.privacyLevel))")
  }

  package func endInterval(
    _ name: StaticString,
    _ state: NonDarwinSignpostIntervalState,
    _ message: StaticString = ""
  ) {
    logger.log(level: .debug, "Signpost \(state.id.id) end: \(name) - \(message)")
  }
}
