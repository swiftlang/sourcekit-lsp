//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

package import struct TSCBasic.AbsolutePath
package import class TSCBasic.Process
package import enum TSCBasic.ProcessEnv
package import struct TSCBasic.ProcessEnvironmentBlock
package import struct TSCBasic.ProcessResult

#if os(Windows)
import WinSDK
#elseif canImport(Android)
import Android
#endif

extension Process {
  /// Wait for the process to exit. If the task gets cancelled, during this time, send a `SIGINT` to the process.
  /// Should the process not terminate on SIGINT after 2 seconds, it is terminated using `SIGKILL`.
  @discardableResult
  package func waitUntilExitStoppingProcessOnTaskCancellation() async throws -> ProcessResult {
    let hasExited = AtomicBool(initialValue: false)
    return try await withTaskCancellationHandler {
      defer {
        hasExited.value = true
      }
      return try await waitUntilExit()
    } onCancel: {
      logger.debug("Terminating process using SIGINT because task was cancelled: \(self.arguments)")
      signal(SIGINT)
      Task {
        // Give the process 2 seconds to react to a SIGINT. If that doesn't work, terminate the process.
        try await Task.sleep(for: .seconds(2))
        if !hasExited.value {
          logger.debug("Terminating process using SIGKILL because it did not honor SIGINT: \(self.arguments)")
          // TODO: We should also terminate all child processes (https://github.com/swiftlang/sourcekit-lsp/issues/2080)
          #if os(Windows)
          // Windows does not define SIGKILL. Process.signal sends a `terminate` to the underlying Foundation process
          // for any signal that is not SIGINT. Use `SIGABRT` to terminate the process.
          signal(SIGABRT)
          #else
          signal(SIGKILL)
          #endif
        }
      }
    }
  }

  /// Launches a new process with the given parameters.
  ///
  /// - Important: If `workingDirectory` is not supported on this platform, this logs an error and falls back to launching the
  ///   process without the working directory set.
  private static func launch(
    arguments: [String],
    environmentBlock: ProcessEnvironmentBlock = ProcessEnv.block,
    workingDirectory: AbsolutePath?,
    outputRedirection: OutputRedirection = .collect(redirectStderr: false),
    startNewProcessGroup: Bool = true,
    loggingHandler: LoggingHandler? = .none
  ) throws -> Process {
    let process =
      if let workingDirectory {
        Process(
          arguments: arguments,
          environmentBlock: environmentBlock,
          workingDirectory: workingDirectory,
          outputRedirection: outputRedirection,
          startNewProcessGroup: startNewProcessGroup,
          loggingHandler: loggingHandler
        )
      } else {
        Process(
          arguments: arguments,
          environmentBlock: environmentBlock,
          outputRedirection: outputRedirection,
          startNewProcessGroup: startNewProcessGroup,
          loggingHandler: loggingHandler
        )
      }
    do {
      try process.launch()
    } catch Process.Error.workingDirectoryNotSupported where workingDirectory != nil {
      return try Process.launchWithWorkingDirectoryUsingSh(
        arguments: arguments,
        environmentBlock: environmentBlock,
        workingDirectory: workingDirectory!,
        outputRedirection: outputRedirection,
        startNewProcessGroup: startNewProcessGroup,
        loggingHandler: loggingHandler
      )
    }
    return process
  }

  private static func launchWithWorkingDirectoryUsingSh(
    arguments: [String],
    environmentBlock: ProcessEnvironmentBlock = ProcessEnv.block,
    workingDirectory: AbsolutePath,
    outputRedirection: OutputRedirection = .collect,
    startNewProcessGroup: Bool = true,
    loggingHandler: LoggingHandler? = .none
  ) throws -> Process {
    let shPath = "/usr/bin/sh"
    guard FileManager.default.fileExists(atPath: shPath) else {
      logger.error(
        """
        Working directory not supported on the platform and 'sh' could not be found. \
        Launching process without working directory \(workingDirectory.pathString)
        """
      )
      return try Process.launch(
        arguments: arguments,
        environmentBlock: environmentBlock,
        workingDirectory: nil,
        outputRedirection: outputRedirection,
        startNewProcessGroup: startNewProcessGroup,
        loggingHandler: loggingHandler
      )
    }
    return try Process.launch(
      arguments: [shPath, "-c", #"cd "$0"; exec "$@""#, workingDirectory.pathString] + arguments,
      environmentBlock: environmentBlock,
      workingDirectory: nil,
      outputRedirection: outputRedirection,
      startNewProcessGroup: startNewProcessGroup,
      loggingHandler: loggingHandler
    )
  }

  /// Runs a new process with the given parameters and waits for it to exit, sending SIGINT if this task is cancelled.
  ///
  /// The process's priority tracks the priority of the current task.
  @discardableResult
  package static func run(
    arguments: [String],
    environmentBlock: ProcessEnvironmentBlock = ProcessEnv.block,
    workingDirectory: AbsolutePath?,
    outputRedirection: OutputRedirection = .collect(redirectStderr: false),
    startNewProcessGroup: Bool = true,
    loggingHandler: LoggingHandler? = .none
  ) async throws -> ProcessResult {
    let process = try Self.launch(
      arguments: arguments,
      environmentBlock: environmentBlock,
      workingDirectory: workingDirectory,
      outputRedirection: outputRedirection,
      startNewProcessGroup: startNewProcessGroup,
      loggingHandler: loggingHandler
    )
    return try await withTaskPriorityChangedHandler(initialPriority: Task.currentPriority) { @Sendable in
      setProcessPriority(pid: process.processID, newPriority: Task.currentPriority)
      return try await process.waitUntilExitStoppingProcessOnTaskCancellation()
    } taskPriorityChanged: {
      setProcessPriority(pid: process.processID, newPriority: Task.currentPriority)
    }
  }
}

/// Set the priority of the given process to a value that's equivalent to `newPriority` on the current OS.
private func setProcessPriority(pid: Process.ProcessID, newPriority: TaskPriority) {
  #if os(Windows)
  guard let handle = OpenProcess(UInt32(PROCESS_SET_INFORMATION), /*bInheritHandle*/ false, UInt32(pid)) else {
    logger.fault("Failed to get process handle for \(pid) to change its priority: \(GetLastError())")
    return
  }
  defer {
    CloseHandle(handle)
  }
  if !SetPriorityClass(handle, UInt32(newPriority.windowsProcessPriority)) {
    logger.fault("Failed to set process priority of \(pid) to \(newPriority.rawValue): \(GetLastError())")
  }
  #elseif canImport(Darwin) || canImport(Android) || os(OpenBSD)
  // `setpriority` is only able to decrease a process's priority and cannot elevate it. Since Swift task’s priorities
  // can only be elevated, this means that we can effectively only change a process's priority once, when it is created.
  // All subsequent calls to `setpriority` will fail. Because of this, don't log an error.
  setpriority(PRIO_PROCESS, UInt32(pid), newPriority.posixProcessPriority)
  #elseif os(FreeBSD)
  setpriority(PRIO_PROCESS, pid, newPriority.posixProcessPriority)
  #else
  setpriority(__priority_which_t(PRIO_PROCESS.rawValue), UInt32(pid), newPriority.posixProcessPriority)
  #endif
}

fileprivate extension TaskPriority {
  #if os(Windows)
  var windowsProcessPriority: Int32 {
    if self >= .high {
      // SourceKit-LSP’s request handling runs at `TaskPriority.high`, which corresponds to the normal priority class.
      return NORMAL_PRIORITY_CLASS
    }
    if self >= .medium {
      return BELOW_NORMAL_PRIORITY_CLASS
    }
    return IDLE_PRIORITY_CLASS
  }
  #else
  var posixProcessPriority: Int32 {
    if self >= .high {
      // SourceKit-LSP’s request handling runs at `TaskPriority.high`, which corresponds to the base 0 niceness value.
      return 0
    }
    if self >= .medium {
      return 5
    }
    if self >= .low {
      return 10
    }
    return 15
  }
  #endif
}
