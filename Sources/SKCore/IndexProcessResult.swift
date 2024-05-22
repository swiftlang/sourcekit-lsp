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

import struct TSCBasic.ProcessResult

/// Result of a process that prepares a target or updates the index store. To be shown in the build log.
///
/// Abstracted over a `ProcessResult` to facilitate build systems that don't spawn a new process to prepare a target but
/// prepare it from a build graph they have loaded in-process.
public struct IndexProcessResult {
  /// A human-readable description of what the process was trying to achieve, like `Preparing MyTarget`
  public let taskDescription: String

  /// The command that was run to produce the result.
  public let command: String

  /// The output that the process produced.
  public let output: String

  /// Whether the process failed.
  public let failed: Bool

  /// The duration it took for the process to execute.
  public let duration: Duration

  public init(taskDescription: String, command: String, output: String, failed: Bool, duration: Duration) {
    self.taskDescription = taskDescription
    self.command = command
    self.output = output
    self.failed = failed
    self.duration = duration
  }

  public init(taskDescription: String, processResult: ProcessResult, start: ContinuousClock.Instant) {
    let stdout = (try? String(bytes: processResult.output.get(), encoding: .utf8)) ?? "<failed to decode stdout>"
    let stderr = (try? String(bytes: processResult.stderrOutput.get(), encoding: .utf8)) ?? "<failed to decode stderr>"
    var outputComponents: [String] = []
    if !stdout.isEmpty {
      outputComponents.append(
        """
        Stdout:
        \(stdout)
        """
      )
    }
    if !stderr.isEmpty {
      outputComponents.append(
        """
        Stderr:
        \(stderr)
        """
      )
    }
    self.init(
      taskDescription: taskDescription,
      command: processResult.arguments.joined(separator: " "),
      output: outputComponents.joined(separator: "\n\n"),
      failed: processResult.exitStatus != .terminated(code: 0),
      duration: start.duration(to: .now)
    )
  }
}
