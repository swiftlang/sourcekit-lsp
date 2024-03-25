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

#if canImport(OSLog)
import OSLog

/// Reads oslog messages to find recent sourcekitd crashes.
struct OSLogScraper {
  /// How far into the past we should search for crashes in OSLog.
  var searchDuration: TimeInterval

  private func getLogEntries(matching predicate: NSPredicate) throws -> [any OSLogEntryWithPayload & OSLogEntry] {
    let logStore = try OSLogStore.local()
    let startPoint = logStore.position(date: Date().addingTimeInterval(-searchDuration))
    return
      try logStore
      .getEntries(
        at: startPoint,
        matching: predicate
      ).compactMap { $0 as? (OSLogEntryWithPayload & OSLogEntry) }
  }

  private func crashedSourceKitLSPRequests() throws -> [(name: String, logCategory: String)] {
    let predicate = NSPredicate(
      format: #"subsystem CONTAINS "sourcekit-lsp" AND composedMessage CONTAINS "sourcekitd crashed (1/""#
    )
    return try getLogEntries(matching: predicate).map {
      (name: "Crash at \($0.date)", logCategory: $0.category)
    }
  }

  /// Get the `RequestInfo` for a crash that was logged in `logCategory`.
  private func requestInfo(for logCategory: String) throws -> RequestInfo {
    let predicate = NSPredicate(
      format:
        #"subsystem CONTAINS "sourcekit-lsp" AND composedMessage CONTAINS "sourcekitd crashed" AND category = %@"#,
      logCategory
    )
    var isInFileContentSection = false
    var request = ""
    var fileContents = ""
    for entry in try getLogEntries(matching: predicate) {
      for line in entry.composedMessage.components(separatedBy: "\n") {
        if line.starts(with: "sourcekitd crashed (") {
          continue
        }
        if line == "Request:" {
          continue
        }
        if line == "File contents:" {
          isInFileContentSection = true
          continue
        }
        if line == "--- End Chunk" {
          continue
        }
        if isInFileContentSection {
          fileContents += line + "\n"
        } else {
          request += line + "\n"
        }
      }
    }

    var requestInfo = try RequestInfo(request: request)
    requestInfo.fileContents = fileContents
    return requestInfo
  }

  /// Get information about sourcekitd crashes that haven logged to OSLog.
  /// This information can be used to reduce the crash.
  ///
  /// Name is a human readable name that identifies the crash.
  func getCrashedRequests() throws -> [(name: String, info: RequestInfo)] {
    let crashedRequests = try crashedSourceKitLSPRequests().reversed()
    return crashedRequests.compactMap { (name: String, logCategory: String) -> (name: String, info: RequestInfo)? in
      guard let requestInfo = try? requestInfo(for: logCategory) else {
        return nil
      }
      return (name, requestInfo)
    }
  }
}
#endif
