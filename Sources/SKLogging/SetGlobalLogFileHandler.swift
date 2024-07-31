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

import RegexBuilder

#if canImport(Darwin)
import Foundation
#else
// TODO: @preconcurrency needed because stderr is not sendable on Linux https://github.com/swiftlang/swift/issues/75601
@preconcurrency import Foundation
#endif

#if os(Windows)
import WinSDK
#endif

#if !canImport(os) || SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER
fileprivate struct FailedToCreateFileError: Error, CustomStringConvertible {
  let logFile: URL

  var description: String {
    return "Failed to create log file at \(logFile)"
  }
}

/// The number of log file handles that have been created by this process.
///
/// See comment on `logFileHandle`.
@LogHandlerActor
fileprivate var logRotateIndex = 0

/// The file handle to the current log file. When the file managed by this handle reaches its maximum size, we increment
/// the `logRotateIndex` by 1 and set the `logFileHandle` to `nil`. This causes a new log file handle with index
/// `logRotateIndex % logRotateCount` to be created on the next log call.
@LogHandlerActor
fileprivate var logFileHandle: FileHandle?

@LogHandlerActor
func getOrCreateLogFileHandle(logDirectory: URL, logRotateCount: Int) -> FileHandle {
  if let logFileHandle {
    return logFileHandle
  }

  // Name must match the regex in `cleanOldLogFiles` and the prefix in `DiagnoseCommand.addNonDarwinLogs`.
  let logFileUrl = logDirectory.appendingPathComponent(
    "sourcekit-lsp-\(ProcessInfo.processInfo.processIdentifier).\(logRotateIndex % logRotateCount).log"
  )

  do {
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: logFileUrl.path) {
      guard FileManager.default.createFile(atPath: logFileUrl.path, contents: nil) else {
        throw FailedToCreateFileError(logFile: logFileUrl)
      }
    }
    let newFileHandle = try FileHandle(forWritingTo: logFileUrl)
    logFileHandle = newFileHandle
    try newFileHandle.truncate(atOffset: 0)
    return newFileHandle
  } catch {
    // If we fail to create a file handle for the log file, log one message about it to stderr and then log to stderr.
    // We will try creating a log file again once this section of the log reaches `maxLogFileSize` but that means that
    // we'll only log this error every `maxLogFileSize` bytes, which is a lot less spammy than logging it on every log
    // call.
    fputs("Failed to open file handle for log file at \(logFileUrl.path): \(error)", stderr)
    logFileHandle = FileHandle.standardError
    return FileHandle.standardError
  }
}

/// Log the given message to a log file in the given log directory.
///
/// The name of the log file includes the PID of the current process to make sure it is exclusively writing to the file.
/// When a log file reaches `logFileMaxBytes`, it will be rotated, with at most `logRotateCount` different log files
/// being created.
@LogHandlerActor
private func logToFile(message: String, logDirectory: URL, logFileMaxBytes: Int, logRotateCount: Int) throws {

  guard let data = message.data(using: .utf8) else {
    fputs(
      """
      Failed to convert log message to UTF-8 data
      \(message)

      """,
      stderr
    )
    return
  }
  let logFileHandleUnwrapped = getOrCreateLogFileHandle(logDirectory: logDirectory, logRotateCount: logRotateCount)
  try logFileHandleUnwrapped.write(contentsOf: data)

  // If this log file has exceeded the maximum size, start writing to a new log file.
  if try logFileHandleUnwrapped.offset() > logFileMaxBytes {
    logRotateIndex += 1
    // Resetting `logFileHandle` will cause a new logFileHandle to be created on the next log call.
    logFileHandle = nil
  }
}

/// If the file at the given path is writable, redirect log messages handled by `NonDarwinLogHandler` to the given file.
///
/// Occasionally checks that the log does not exceed `targetLogSize` (in bytes) and truncates the beginning of the log
/// when it does.
@LogHandlerActor
private func setUpGlobalLogFileHandlerImpl(logFileDirectory: URL, logFileMaxBytes: Int, logRotateCount: Int) {
  logHandler = { @LogHandlerActor message in
    do {
      try logToFile(
        message: message,
        logDirectory: logFileDirectory,
        logFileMaxBytes: logFileMaxBytes,
        logRotateCount: logRotateCount
      )
    } catch {
      fputs(
        """
        Failed to write message to log file: \(error)
        \(message)

        """,
        stderr
      )
    }
  }
}

/// Returns `true` if a process with the given PID still exists and is alive.
private func isProcessAlive(pid: Int32) -> Bool {
  #if os(Windows)
  if let handle = OpenProcess(UInt32(PROCESS_QUERY_INFORMATION), /*bInheritHandle=*/ false, UInt32(pid)) {
    CloseHandle(handle)
    return true
  }
  return false
  #else
  return kill(pid, 0) == 0
  #endif
}

private func cleanOldLogFilesImpl(logFileDirectory: URL, maxAge: TimeInterval) {
  let enumerator = FileManager.default.enumerator(at: logFileDirectory, includingPropertiesForKeys: nil)
  while let url = enumerator?.nextObject() as? URL {
    let name = url.lastPathComponent
    let regex = Regex {
      "sourcekit-lsp-"
      Capture(ZeroOrMore(.digit))
      "."
      ZeroOrMore(.digit)
      ".log"
    }
    guard let match = name.matches(of: regex).only, let pid = Int32(match.1) else {
      continue
    }
    if isProcessAlive(pid: pid) {
      // Process that owns this log file is still alive. Don't delete it.
      continue
    }
    guard
      let modificationDate = orLog(
        "Getting mtime of old log file",
        { try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] }
      ) as? Date,
      Date().timeIntervalSince(modificationDate) > maxAge
    else {
      // File has been modified in the last hour. Don't delete it because it's useful to diagnose issues after
      // sourcekit-lsp has exited.
      continue
    }
    orLog("Deleting old log file") { try FileManager.default.removeItem(at: url) }
  }
}
#endif

/// If the file at the given path is writable, redirect log messages handled by `NonDarwinLogHandler` to the given file.
///
/// Occasionally checks that the log does not exceed `targetLogSize` (in bytes) and truncates the beginning of the log
/// when it does.
///
/// No-op when using OSLog.
package func setUpGlobalLogFileHandler(logFileDirectory: URL, logFileMaxBytes: Int, logRotateCount: Int) async {
  #if !canImport(os) || SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER
  await setUpGlobalLogFileHandlerImpl(
    logFileDirectory: logFileDirectory,
    logFileMaxBytes: logFileMaxBytes,
    logRotateCount: logRotateCount
  )
  #endif
}

/// Deletes all sourcekit-lsp log files in `logFilesDirectory` that are not associated with a running process and that
/// haven't been modified within the last hour.
///
/// No-op when using OSLog.
package func cleanOldLogFiles(logFileDirectory: URL, maxAge: TimeInterval) {
  #if !canImport(os) || SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER
  cleanOldLogFilesImpl(logFileDirectory: logFileDirectory, maxAge: maxAge)
  #endif
}
