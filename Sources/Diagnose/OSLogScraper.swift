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
@_spi(SourceKitLSP) import SKLogging
import RegexBuilder

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
      ).compactMap { $0 as? (any OSLogEntryWithPayload & OSLogEntry) }
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
    enum LogSection {
      case request
      case fileContents
      case contextualRequest
    }
    var section = LogSection.request
    var request = ""
    var fileContents = ""
    var contextualRequests: [String] = []
    let sourcekitdCrashedRegex = Regex {
      "sourcekitd crashed ("
      OneOrMore(.digit)
      "/"
      OneOrMore(.digit)
      ")"
    }
    let contextualRequestRegex = Regex {
      "Contextual request "
      OneOrMore(.digit)
      " / "
      OneOrMore(.digit)
      ":"
    }

    for entry in try getLogEntries(matching: predicate) {
      for line in entry.composedMessage.components(separatedBy: "\n") {
        if try sourcekitdCrashedRegex.wholeMatch(in: line) != nil {
          continue
        }
        if line == "Request:" {
          continue
        }
        if line == "File contents:" {
          section = .fileContents
          continue
        }
        if line == "File contents:" {
          section = .fileContents
          continue
        }
        if try contextualRequestRegex.wholeMatch(in: line) != nil {
          section = .contextualRequest
          contextualRequests.append("")
          continue
        }
        if line == "--- End Chunk" {
          continue
        }
        switch section {
        case .request:
          request += line + "\n"
        case .fileContents:
          fileContents += line + "\n"
        case .contextualRequest:
          if !contextualRequests.isEmpty {
            contextualRequests[contextualRequests.count - 1] += line + "\n"
          } else {
            // Should never happen because we have appended at least one element to `contextualRequests` when switching
            // to the `contextualRequest` section.
            logger.fault("Dropping contextual request line: \(line)")
          }
        }
      }
    }

    var requestInfo = try RequestInfo(request: request)

    let contextualRequestInfos = contextualRequests.compactMap { contextualRequest in
      orLog("Processsing contextual request") {
        try RequestInfo(request: contextualRequest)
      }
    }.filter { contextualRequest in
      if contextualRequest.fileContents != requestInfo.fileContents {
        logger.error("Contextual request concerns a different file than the crashed request. Ignoring it")
        return false
      }
      return true
    }
    requestInfo.contextualRequestTemplates = contextualRequestInfos.map(\.requestTemplate)
    if requestInfo.compilerArgs.isEmpty {
      requestInfo.compilerArgs = contextualRequestInfos.last(where: { !$0.compilerArgs.isEmpty })?.compilerArgs ?? []
    }
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
