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

#if canImport(os)
import os
#endif

private func logError(prefix: String, error: Error, level: LogLevel) {
  logger.log(
    level: level,
    "\(prefix, privacy: .public)\(prefix.isEmpty ? "" : " ", privacy: .public)\(error.forLogging)"
  )
}

/// Like `try?`, but logs the error on failure.
public func orLog<R>(
  _ prefix: String,
  level: LogLevel = .error,
  _ block: () throws -> R?
) -> R? {
  do {
    return try block()
  } catch {
    logError(prefix: prefix, error: error, level: level)
    return nil
  }
}

/// Like  ``orLog(_:level:_:)-66i2z`` but allows execution of an `async` body.
///
/// - SeeAlso: ``orLog(_:level:_:)-66i2z``
public func orLog<R>(
  _ prefix: String,
  level: LogLevel = .error,
  _ block: () async throws -> R?
) async -> R? {
  do {
    return try await block()
  } catch {
    logError(prefix: prefix, error: error, level: level)
    return nil
  }
}
