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

#if compiler(>=6)
package import ArgumentParser
import Foundation
import RegexBuilder
import SwiftExtensions

import class TSCBasic.Process
#else
import ArgumentParser
import Foundation
import RegexBuilder
import SwiftExtensions

import class TSCBasic.Process
#endif

/// Shared instance of the regex that is used to extract Signpost lines from `log stream --signpost`.
fileprivate struct LogParseRegex {
  @MainActor static let shared = LogParseRegex()

  let dateComponent = Reference(Substring.self)
  let processIdComponent = Reference(Substring.self)
  let signpostIdComponent = Reference(Substring.self)
  let eventTypeComponent = Reference(Substring.self)
  let categoryComponent = Reference(Substring.self)
  let messageComponent = Reference(Substring.self)
  private(set) var regex:
    Regex<Regex<(Substring, Substring, Substring, Substring, Substring, Substring, Substring, Substring)>.RegexOutput>!

  private init() {
    regex = Regex {
      Capture(as: dateComponent) {
        #/[-0-9]+ [0-9:.-]+/#
      }
      " "
      #/[0-9a-fx]+/#  // Thread ID
      ZeroOrMore(.whitespace)
      "Signpost"
      ZeroOrMore(.whitespace)
      #/[0-9a-fx]+/#  // Activity
      ZeroOrMore(.whitespace)
      Capture(as: processIdComponent) {
        ZeroOrMore(.digit)
      }
      ZeroOrMore(.whitespace)
      ZeroOrMore(.digit)  // TTL
      ZeroOrMore(.whitespace)
      "[spid 0x"
      Capture(as: signpostIdComponent) {
        OneOrMore(.hexDigit)
      }
      ", process, "
      ZeroOrMore(.whitespace)
      Capture(as: eventTypeComponent) {
        #/(begin|event|end)/#
      }
      "]"
      ZeroOrMore(.whitespace)
      ZeroOrMore(.whitespace.inverted)  // Process name
      ZeroOrMore(.whitespace)
      "["
      ZeroOrMore(.any)  // subsystem
      ":"
      Capture(as: categoryComponent) {
        ZeroOrMore(.any)
      }
      "]"
      Capture(as: messageComponent) {
        ZeroOrMore(.any)
      }
    }
  }
}

/// A signpost event extracted from a log.
fileprivate struct Signpost {
  /// ID that identifies the signpost across the log.
  ///
  /// There might be multiple signposts with the same `signpostId` across multiple processes.
  struct ID: Hashable {
    let processId: Int
    let signpostId: Int
  }

  enum EventType: String {
    case begin
    case event
    case end
  }

  let date: Date
  let processId: Int
  let signpostId: Int
  let eventType: EventType
  let category: String
  let message: String

  var id: ID {
    ID(processId: processId, signpostId: signpostId)
  }

  @MainActor
  init?(logLine line: Substring) {
    let regex = LogParseRegex.shared
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
    guard let match = try? regex.regex.wholeMatch(in: line) else {
      return nil
    }
    guard let date = dateFormatter.date(from: String(match[regex.dateComponent])),
      let processId = Int(match[regex.processIdComponent]),
      let signpostId = Int(match[regex.signpostIdComponent], radix: 16),
      let eventType = Signpost.EventType(rawValue: String(match[regex.eventTypeComponent]))
    else {
      return nil
    }
    self.date = date
    self.processId = processId
    self.signpostId = signpostId
    self.eventType = eventType
    self.category = String(match[regex.categoryComponent])
    self.message = String(match[regex.messageComponent])
  }
}

/// A trace event in the *Trace Event Format* that can be opened using Perfetto.
/// https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/mobilebasic
fileprivate struct TraceEvent: Codable {
  enum EventType: String, Codable {
    case begin = "B"
    case end = "E"
  }

  /// The name of the event, as displayed in Trace Viewer
  let name: String?
  /// The event categories.
  ///
  /// This is a comma separated list of categories for the event.
  /// The categories can be used to hide events in the Trace Viewer UI.
  let cat: String

  /// The event type.
  ///
  /// This is a single character which changes depending on the type of event being output.
  let ph: EventType

  /// The process ID for the process that output this event.
  let pid: Int

  /// The thread ID for the thread that output this event.
  ///
  /// We use the signpost IDs as thread IDs to show each signpost on a single lane in the trace.
  let tid: Int

  /// The tracing clock timestamp of the event. The timestamps are provided at microsecond granularity.
  let ts: Double

  init(beginning signpost: Signpost) {
    self.name = signpost.message
    self.cat = signpost.category
    self.ph = .begin
    self.pid = signpost.processId
    self.tid = signpost.signpostId
    self.ts = signpost.date.timeIntervalSince1970 * 1_000_000
  }

  init(ending signpost: Signpost) {
    self.name = nil
    self.cat = signpost.category
    self.ph = .end
    self.pid = signpost.processId
    self.tid = signpost.signpostId
    self.ts = signpost.date.timeIntervalSince1970 * 1_000_000
  }
}

package struct TraceFromSignpostsCommand: AsyncParsableCommand {
  package static let configuration: CommandConfiguration = CommandConfiguration(
    commandName: "trace-from-signposts",
    abstract: "Generate a Trace Event Format file from signposts captured using OS Log",
    discussion: """
      Extracts signposts captured using 'log stream --signpost ..' and generates a trace file that can be opened using \
      Perfetto to visualize which requests were running concurrently.
      """
  )

  @Option(name: .customLong("log-file"), help: "The log file that was captured using 'log stream --signpost ...'")
  var logFile: String

  @Option(help: "The trace output file to generate")
  var output: String

  @Option(
    name: .customLong("category-filter"),
    help: "If specified, only include signposts from this logging category in the output file"
  )
  var categoryFilter: String?

  package init() {}

  private func traceEvents(from signpostsById: [Signpost.ID: [Signpost]]) -> [TraceEvent] {
    var traceEvents: [TraceEvent] = []
    for signposts in signpostsById.values {
      guard let begin = signposts.filter({ $0.eventType == .begin }).only else {
        continue
      }
      // Each begin event should to be paired with an end event.
      // If a begin event exists before the previous begin event is ended, a nested timeline is shown.
      // We display signpost events to last until the next signpost event.
      let events = signposts.filter { $0.eventType == .event }
      traceEvents.append(TraceEvent(beginning: begin))
      var hadPreviousEvent = false
      for event in events {
        if hadPreviousEvent {
          traceEvents.append(TraceEvent(ending: event))
        }
        hadPreviousEvent = true
        traceEvents.append(TraceEvent(beginning: event))
      }
      if let end = signposts.filter({ $0.eventType == .end }).only {
        if hadPreviousEvent {
          traceEvents.append(TraceEvent(ending: end))
        }
        traceEvents.append(TraceEvent(ending: end))
      }
    }
    return traceEvents
  }

  @MainActor
  package func run() async throws {
    let log = try String(contentsOf: URL(fileURLWithPath: logFile), encoding: .utf8)

    var signpostsById: [Signpost.ID: [Signpost]] = [:]
    for line in log.split(separator: "\n") {
      guard let signpost = Signpost(logLine: line) else {
        continue
      }
      if let categoryFilter, signpost.category != categoryFilter {
        continue
      }
      signpostsById[signpost.id, default: []].append(signpost)
    }
    let traceEvents = traceEvents(from: signpostsById)
    try JSONEncoder().encode(traceEvents).write(to: URL(fileURLWithPath: output))
  }
}
