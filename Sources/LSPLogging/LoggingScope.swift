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

public final class LoggingScope {
  /// The name of the current logging subsystem or `nil` if no logging scope is set.
  @TaskLocal fileprivate static var _subsystem: String?

  /// The name of the current logging scope or `nil` if no logging scope is set.
  @TaskLocal fileprivate static var _scope: String?

  /// The name of the current logging subsystem.
  public static var subsystem: String {
    return _subsystem ?? "org.swift.sourcekit-lsp"
  }

  /// The name of the current logging scope.
  public static var scope: String {
    return _scope ?? "default"
  }
}

/// Logs all messages created from the operation to the given subsystem.
///
/// This overrides the current logging subsystem.
///
/// - Note: Since this stores the logging subsystem in a task-local value, it only works when run inside a task.
///   Outside a task, this is a no-op.
public func withLoggingSubsystemAndScope<Result>(
  subsystem: String,
  scope: String?,
  _ operation: () throws -> Result
) rethrows -> Result {
  return try LoggingScope.$_subsystem.withValue(subsystem) {
    return try LoggingScope.$_scope.withValue(scope, operation: operation)
  }
}

/// Same as `withLoggingSubsystemAndScope` but allows the operation to be `async`.
public func withLoggingSubsystemAndScope<Result>(
  subsystem: String,
  scope: String?,
  _ operation: () async throws -> Result
) async rethrows -> Result {
  return try await LoggingScope.$_subsystem.withValue(subsystem) {
    return try await LoggingScope.$_scope.withValue(scope, operation: operation)
  }
}

/// Create a new logging scope, which will be used as the category in any log messages created from the operation.
///
/// This overrides the current logging scope.
///
/// - Note: Since this stores the logging scope in a task-local value, it only
///   works when run inside a task. Outside a task, this is a no-op.
/// - Warning: Be very careful with the dynamic creation of logging scopes. The logging scope is used as the os_log
///   category, os_log only supports 4000 different loggers and thus at most 4000 different scopes must be used.
public func withLoggingScope<Result>(
  _ scope: String,
  _ operation: () throws -> Result
) rethrows -> Result {
  return try LoggingScope.$_scope.withValue(
    scope,
    operation: operation
  )
}

/// Same as `withLoggingScope` but allows the operation to be `async`.
///
/// - SeeAlso: ``withLoggingScope(_:_:)-6qtga``
public func withLoggingScope<Result>(
  _ scope: String,
  @_inheritActorContext _ operation: @Sendable () async throws -> Result
) async rethrows -> Result {
  return try await LoggingScope.$_scope.withValue(
    scope,
    operation: operation
  )
}
