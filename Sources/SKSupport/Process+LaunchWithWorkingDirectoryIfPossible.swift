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

import LSPLogging

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import struct TSCBasic.ProcessEnvironmentBlock

extension Process {
  /// Launches a new process with the given parameters.
  ///
  /// - Important: If `workingDirectory` is not supported on this platform, this logs an error and falls back to launching the
  ///   process without the working directory set.
  public static func launch(
    arguments: [String],
    environmentBlock: ProcessEnvironmentBlock = ProcessEnv.block,
    workingDirectory: AbsolutePath?,
    startNewProcessGroup: Bool = true,
    loggingHandler: LoggingHandler? = .none
  ) throws -> Process {
    let process =
      if let workingDirectory {
        Process(
          arguments: arguments,
          environmentBlock: environmentBlock,
          workingDirectory: workingDirectory,
          startNewProcessGroup: startNewProcessGroup,
          loggingHandler: loggingHandler
        )
      } else {
        Process(
          arguments: arguments,
          environmentBlock: environmentBlock,
          startNewProcessGroup: startNewProcessGroup,
          loggingHandler: loggingHandler
        )
      }
    do {
      try process.launch()
    } catch Process.Error.workingDirectoryNotSupported where workingDirectory != nil {
      // TODO (indexing): We need to figure out how to set the working directory on all platforms.
      logger.error(
        "Working directory not supported on the platform. Launching process without working directory \(workingDirectory!.pathString)"
      )
      return try Process.launch(
        arguments: arguments,
        environmentBlock: environmentBlock,
        workingDirectory: nil,
        startNewProcessGroup: startNewProcessGroup,
        loggingHandler: loggingHandler
      )
    }
    return process
  }
}
