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
  /// The name of the current logging scope or `nil` if no logging scope is set.
  @TaskLocal fileprivate static var _scope: String?

  /// The name of the current logging scope.
  public static var scope: String {
    return _scope ?? "default"
  }
}

/// Append `subscope` to the current scope name, if any exists, otherwise return
/// `subscope`.
private func newLoggingScopeName(_ subscope: String) -> String {
  if let existingScope = LoggingScope._scope {
    return "\(existingScope).\(subscope)"
  } else {
    return subscope
  }
}

/// Create a new logging scope, which will be used as the category in any log
/// messages created from the operation.
///
/// The name of the new scope will be any existing scope with the new scope
/// appended using a `.`.
///
/// For example if we are currently logging scope `handleRequest` and we start a
/// new scope `sourcekitd`, then the new scope has the name `handleRequest.sourcekitd`.
///
/// Because `.` is used to separate scopes and sub-scopes, `subscope` should not
/// contain any `.`.
///
/// - Note: Since this stores the logging scope in a task-local value, it only
///   works when run inside a task. Outside a task, this is a no-op.
public func withLoggingScope<Result>(
  _ subscope: String,
  _ operation: () throws -> Result
) rethrows -> Result {
  return try LoggingScope.$_scope.withValue(
    newLoggingScopeName(subscope),
    operation: operation
  )
}

/// Same as `withLoggingScope` but allows the operation to be `async`.
///
/// - SeeAlso: ``withLoggingScope(_:_:)-6qtga``
public func withLoggingScope<Result>(
  _ subscope: String,
  _ operation: () async throws -> Result
) async rethrows -> Result {
  return try await LoggingScope.$_scope.withValue(
    newLoggingScopeName(subscope),
    operation: operation
  )
}
