//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol

/// General categorization of a file state, applicable to multiple components such as the
/// `BuildSystem` as well as the `ToolchainLanguageServer`.
///
/// In general these are limited to states that may directly impact user-facing functionality.
/// Non-blocking states (e.g. build status/log) should instead use a separate channel.
public enum FileState {
  /// Component is initializing.
  ///
  /// Examples:
  /// - Waiting on reply from `BuildSystem`
  /// - Starting up a new `ToolchainLanguageServer`.
  case initializing

  /// Component is performing work that blocks core functionality.
  ///
  /// Examples:
  /// - `ToolchainLanguageServer` loading an AST
  /// - `BuildSystem` performing work that directly impacts functionality (e.g. initial load).
  case working

  /// Component is ready.
  ///
  /// Examples:
  /// - `ToolchainLanguageServer` AST available
  /// - `BuildSystem` up-to-date for a given file.
  case ready
}

public enum FileStateSeverity {
  case ok
  case warning
  case error
}

public extension FileStateSeverity {
  var diagnosticSeverity: DiagnosticSeverity {
    switch self {
    case .ok: return DiagnosticSeverity.information
    case .warning: return DiagnosticSeverity.warning
    case .error: return DiagnosticSeverity.error
    }
  }

  static func highestSeverity(
    _ a: FileStateSeverity,
    _ b: FileStateSeverity
  ) -> FileStateSeverity {
    if a == .error || b == .error {
      return .error
    }
    if a == .warning || b == .warning {
      return .warning
    }
    return .ok
  }
}

public extension FileState {
  var skFileState: SourceKitFileState {
    switch self {
    case .initializing: return SourceKitFileState.initializing
    case .working: return SourceKitFileState.working
    case .ready: return SourceKitFileState.ready
    }
  }
}

public struct FileStatus: Equatable {
  /// Categorization of this status.
  public let state: FileState

  /// Severity of this status.
  public let severity: FileStateSeverity

  /// Human readable description. May be empty.
  public let message: String

  /// Short operation label for the status, if any.
  public let operation: String?

  public init(
    state: FileState,
    severity: FileStateSeverity = .ok,
    message: String = "",
    operation: String? = nil
  ) {
    self.state = state
    self.severity = severity
    self.message = message
    self.operation = operation
  }
}

public extension FileStatus {
  /// Merge this status with the given underlying status if present.
  ///
  /// - `state` is merged (`initializing` if either are `initializing`, `ready` if all are `ready`,
  ///   otherwise `working`).
  /// - `severity` is merged by taking the highest severity.
  /// - `message` is merged when non-empty (underlying first).
  /// - `operation` is not merged, the first non-empty operation is chosen (underlying first).
  func mergeWith(_ underlying: FileStatus?) -> FileStatus {
    guard let underlying = underlying else { return self }

    let mergedState: FileState
    switch self.state {
    case .working:
      switch underlying.state {
      case .working: mergedState = .working
      case .ready: mergedState = .working
      case .initializing: mergedState = .initializing
      }
    case .ready: mergedState = underlying.state
    case .initializing: mergedState = .initializing
    }

    let mergedMessage: String
    if !self.message.isEmpty && !underlying.message.isEmpty {
      mergedMessage = "\(underlying.message)\n\n\(self.message)"
    } else if !self.message.isEmpty {
      mergedMessage = self.message
    } else {
      mergedMessage = underlying.message
    }

    let mergedSeverity = FileStateSeverity.highestSeverity(self.severity, underlying.severity)
    let mergedOperation = underlying.operation ?? self.operation

    return FileStatus(
      state: mergedState,
      severity: mergedSeverity,
      message: mergedMessage,
      operation: mergedOperation)
  }
}
