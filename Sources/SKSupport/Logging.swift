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

import Basic
import Foundation

#if canImport(os)
import os // os_log
#endif

public enum LogLevel: Int, Equatable {
  case error = 0
  case warning = 1
  case info = 2
  case debug = 3

  public static let `default`: LogLevel = .info
}

/// Log the given message.
///
/// If `level >= Logger.shared.currentLevel`, it will be emitted. However, the converse is not necessarily true: on platforms that provide `os_log`, the message may be emitted by `os_log` according to its own rules about log level.
///
/// Additional message handlers set on `Logger.shared` will only be called if `level >= Logger.shared.currentLevel`.
///
/// - parameter message: The message to print.
/// - parameter level: The `LogLevel` of the message, used to determine whether it is emitted.
public func log(_ message: String, level: LogLevel = .default) {
  Logger.shared.log(message, level: level)
}

/// Log a message that is produced asynchronously by a callback, which is useful for logging messages that are expensive to compute and can be safely produced asynchronously. The callback is guaranteed to be called exactly once.
///
/// - parameter level: The `LogLevel` of the message, used to determine whether it is emitted.
/// - parameter messageProducer: The async callback to produce the message.
/// - parameter currentLevel: The current log level is provided to the callback, which can be used to avoid expensive processing, for example by reducing the verbosity.
public func logAsync(level: LogLevel = .default, messageProducer: @escaping (_ currentLevel: LogLevel) -> String?) {
  let logger = Logger.shared
  logger.logQueue.async {
    if let message = messageProducer(Logger.shared.currentLevel) {
      // Use `async: false` since we're already async'd on `logQueue` and we want to preserve ordering.
      logger.log(message, level: level, async: false)
    }
  }
}

/// Like `try?`, but logs the error on failure.
public func orLog<R>(_ prefix: String = "", level: LogLevel = .default, block: () throws -> R?) -> R? {
  do {
    return try block()
  } catch {
    log("\(prefix)\(prefix.isEmpty ? "" : " ")\(error)", level: level)
    return nil
  }
}

public protocol LogHandler: AnyObject {
  func handle(_ message: String, level: LogLevel)
}

/// Logging state for `log(_:_:level:)`.
public final class Logger {

  /// The shared logger instance.
  public internal(set)
  static var shared: Logger = .init()

  let logQueue: DispatchQueue = DispatchQueue(label: "log-queue", qos: .utility)

  /// - note: This is separate from the logging queue to make it as fast as possible. Ideally we'd use a relaxed atomic.
  let logLevelQueue: DispatchQueue = DispatchQueue(label: "log-level-queue", qos: .userInitiated)

  var _currentLevel: LogLevel = .warning

  var disableOSLog: Bool = false

  var disableNSLog: Bool = false

  /// The current logging level.
  public var currentLevel: LogLevel {
    get { return logLevelQueue.sync { _currentLevel } }
    set { logLevelQueue.sync { _currentLevel = newValue } }
  }

  var handlers: [LogHandler] = []

  public func addLogHandler(_ handler: LogHandler) {
    logQueue.async {
      self.handlers.append(handler)
    }
  }

  @discardableResult
  public func addLogHandler(_ handler: @escaping (String, LogLevel) -> ()) -> AnyLogHandler {
    let obj = AnyLogHandler(handler)
    addLogHandler(obj)
    return obj
  }

  public func removeLogHandler(_ handler: LogHandler) {
    logQueue.async {
      self.handlers.removeAll(where: { $0 === handler })
    }
  }

  public func setLogLevel(environmentVariable: String) {
    if let string = Process.env[environmentVariable], let value = Int(string) {
      if let level = LogLevel(rawValue: value) {
        currentLevel = level
      } else if value > LogLevel.debug.rawValue  {
        currentLevel = LogLevel.debug
      }
    }
  }

  public func log(_ message: String, level: LogLevel, async: Bool = true) {

    let currentLevel = self.currentLevel

    var usedOSLog = false
#if canImport(os)
    if !disableOSLog, #available(OSX 10.12, *) {
      // If os_log is available, we call it unconditionally since it has its own log-level handling that we respect.
      os_log("%@", type: level.osLogType, message)
      usedOSLog = true
    }
#endif

    if level > currentLevel {
      return
    }

    let logImpl = { self.logImpl(message, level: level, usedOSLog: usedOSLog) }

    if async {
      logQueue.async {
        logImpl()
      }
    } else {
      logImpl()
    }
  }

  private func logImpl(_ message: String, level: LogLevel, usedOSLog: Bool) {

    if !self.disableNSLog && !usedOSLog {
      // Fallback to NSLog if os_log isn't available.
      NSLog(message)
    }

    for handler in self.handlers {
      handler.handle(message, level: level)
    }
  }
}

public class AnyLogHandler: LogHandler {

  let handler: (String, LogLevel) -> ()

  public init(_ handler: @escaping (String, LogLevel) -> ()) {
    self.handler = handler
  }

  public func handle(_ message: String, level: LogLevel) {
    handler(message, level)
  }
}

extension LogLevel: Comparable {
  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    return lhs.rawValue < rhs.rawValue
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
