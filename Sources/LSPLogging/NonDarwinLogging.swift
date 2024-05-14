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

// MARK: - Log settings

public enum LogConfig {
  /// The globally set log level
  fileprivate static let logLevel: NonDarwinLogLevel = {
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

  /// The globally set privacy level
  fileprivate static let privacyLevel: NonDarwinLogPrivacy = {
    guard let envVar = ProcessInfo.processInfo.environment["SOURCEKITLSP_LOG_PRIVACY_LEVEL"] else {
      return .private
    }
    return NonDarwinLogPrivacy(envVar) ?? .private
  }()
}

/// A type that is API-compatible to `OSLogType` for all uses within
/// sourcekit-lsp.
///
/// This is used on platforms that don't have OSLog.
///
/// For documentation of the different log levels see
/// https://developer.apple.com/documentation/os/oslogtype.
public enum NonDarwinLogLevel: Comparable, CustomStringConvertible, Sendable {
  case debug
  case info
  case `default`
  case error
  case fault

  public init?(_ value: String) {
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

  public init?(_ value: Int) {
    switch value {
    case 0: self = .fault
    case 1: self = .error
    case 2: self = .default
    case 3: self = .info
    case 4: self = .debug
    default: return nil
    }
  }

  public var description: String {
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
public enum NonDarwinLogPrivacy: Comparable, Sendable {
  case `public`
  case `private`
  case sensitive

  init?(_ value: String) {
    switch value.lowercased() {
    case "sensitive": self = .sensitive
    case "private": self = .private
    case "public": self = .public
    default: break
    }

    switch Int(value) {
    case 0: self = .public
    case 1: self = .private
    case 2: self = .sensitive
    default: break
    }

    return nil
  }
}

// MARK: String interpolation

/// A type that is API-compatible to `OSLogInterpolation` for all uses within
/// sourcekit-lsp.
///
/// This is used on platforms that don't have OSLog.
public struct NonDarwinLogInterpolation: StringInterpolationProtocol, Sendable {
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

  public init(literalCapacity: Int, interpolationCount: Int) {
    self.pieces = []
    pieces.reserveCapacity(literalCapacity + interpolationCount)
  }

  public mutating func appendLiteral(_ literal: String) {
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

  public mutating func appendInterpolation(_ message: StaticString, privacy: NonDarwinLogPrivacy = .public) {
    append(description: message.description, redactedDescription: "<private>", privacy: privacy)
  }

  @_disfavoredOverload  // Prefer to use the StaticString overload when possible.
  public mutating func appendInterpolation(
    _ message: some CustomStringConvertible & Sendable,
    privacy: NonDarwinLogPrivacy = .private
  ) {
    append(description: message.description, redactedDescription: "<private>", privacy: privacy)
  }

  public mutating func appendInterpolation(
    _ message: some CustomLogStringConvertibleWrapper & Sendable,
    privacy: NonDarwinLogPrivacy = .private
  ) {
    append(description: message.description, redactedDescription: message.redactedDescription, privacy: privacy)
  }

  public mutating func appendInterpolation(_ type: Any.Type, privacy: NonDarwinLogPrivacy = .public) {
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
public struct NonDarwinLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
  fileprivate let value: NonDarwinLogInterpolation

  public init(stringInterpolation: NonDarwinLogInterpolation) {
    self.value = stringInterpolation
  }

  public init(stringLiteral value: String) {
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

/// The queue on which we log messages.
///
/// A global queue since we create and discard loggers all the time.
private let loggingQueue: DispatchQueue = DispatchQueue(label: "loggingQueue", qos: .utility)

/// A logger that is designed to be API-compatible with `os.Logger` for all uses
/// in sourcekit-lsp.
///
/// This logger is used to log messages to stderr on platforms where OSLog is
/// not available.
public struct NonDarwinLogger: Sendable {
  private let subsystem: String
  private let category: String
  private let logLevel: NonDarwinLogLevel
  private let privacyLevel: NonDarwinLogPrivacy
  private let logHandler: @Sendable (String) -> Void

  /// - Parameters:
  ///   - subsystem: See os.Logger
  ///   - category: See os.Logger
  ///   - logLevel: The level to log at. All messages with a lower log level
  ///     will be ignored
  ///   - privacyLevel: The privacy level to log at. Any interpolation segments
  ///     with a higher privacy level will be masked.
  ///   - logHandler: The function that actually logs the message.
  public init(
    subsystem: String,
    category: String,
    logLevel: NonDarwinLogLevel? = nil,
    privacyLevel: NonDarwinLogPrivacy? = nil,
    logHandler: @escaping @Sendable (String) -> Void = { fputs($0 + "\n", stderr) }
  ) {
    self.subsystem = subsystem
    self.category = category
    self.logLevel = logLevel ?? LogConfig.logLevel
    self.privacyLevel = privacyLevel ?? LogConfig.privacyLevel
    self.logHandler = logHandler
  }

  /// Logs the given message at the given level.
  ///
  /// Logging is performed asynchronously to allow the execution of the main
  /// program to finish as quickly as possible.
  public func log(
    level: NonDarwinLogLevel,
    _ message: @autoclosure @escaping @Sendable () -> NonDarwinLogMessage
  ) {
    guard level >= self.logLevel else { return }
    let date = Date()
    loggingQueue.async {
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
      logHandler(
        """
        [\(subsystem):\(category)] \(level) \(dateFormatter.string(from: date))
        \(message)
        ---
        """
      )
    }
  }

  /// Log a message at the `debug` level.
  public func debug(_ message: NonDarwinLogMessage) {
    log(level: .debug, message)
  }

  /// Log a message at the `info` level.
  public func info(_ message: NonDarwinLogMessage) {
    log(level: .info, message)
  }

  /// Log a message at the `default` level.
  public func log(_ message: NonDarwinLogMessage) {
    log(level: .default, message)
  }

  /// Log a message at the `error` level.
  public func error(_ message: NonDarwinLogMessage) {
    log(level: .error, message)
  }

  /// Log a message at the `fault` level.
  public func fault(_ message: NonDarwinLogMessage) {
    log(level: .fault, message)
  }

  /// Wait for all log messages to be written.
  ///
  /// Useful for testing to make sure all asynchronous log calls have actually
  /// written their data.
  @_spi(Testing)
  public static func flush() {
    loggingQueue.sync {}
  }

  public func makeSignposter() -> NonDarwinSignposter {
    return NonDarwinSignposter()
  }
}

// MARK: - Signposter

public struct NonDarwinSignpostID: Sendable {}

public struct NonDarwinSignpostIntervalState: Sendable {}

/// A type that is API-compatible to `OSLogMessage` for all uses within sourcekit-lsp.
///
/// Since non-Darwin platforms don't have signposts, the type just has no-op operations.
public struct NonDarwinSignposter: Sendable {
  public func makeSignpostID() -> NonDarwinSignpostID {
    return NonDarwinSignpostID()
  }

  public func beginInterval(
    _ name: StaticString,
    id: NonDarwinSignpostID,
    _ message: NonDarwinLogMessage
  ) -> NonDarwinSignpostIntervalState {
    return NonDarwinSignpostIntervalState()
  }

  public func emitEvent(_ name: StaticString, id: NonDarwinSignpostID, _ message: NonDarwinLogMessage = "") {}

  public func endInterval(_ name: StaticString, _ state: NonDarwinSignpostIntervalState, _ message: StaticString) {}
}
