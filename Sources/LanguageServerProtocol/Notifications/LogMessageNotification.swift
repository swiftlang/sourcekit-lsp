//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Notification from the server containing a log message.
///
/// - Parameters:
///   - type: The kind of log message.
///   - message: The contents of the message.
public struct LogMessageNotification: LSPNotification, Hashable {
  public static let method: String = "window/logMessage"

  /// The kind of log message.
  public var type: WindowMessageType

  /// The contents of the message.
  public var message: String

  /// If specified, the client should log the message to a log with this name instead of the standard log for this LSP
  /// server.
  ///
  /// **(LSP Extension)**
  public var logName: String?

  /// If specified, allows grouping log messages that belong to the same originating task together, instead of logging
  /// them in chronological order in which they were produced.
  ///
  /// **(LSP Extension)** guarded by the experimental `structured-logs` feature.
  public var structure: StructuredLogKind?

  public init(type: WindowMessageType, message: String, logName: String? = nil, structure: StructuredLogKind? = nil) {
    self.type = type
    self.message = message
    self.logName = logName
    self.structure = structure
  }
}

public enum StructuredLogKind: Codable, Hashable, Sendable {
  case begin(StructuredLogBegin)
  case report(StructuredLogReport)
  case end(StructuredLogEnd)

  public var taskID: String {
    switch self {
    case .begin(let begin): return begin.taskID
    case .report(let report): return report.taskID
    case .end(let end): return end.taskID
    }
  }

  public init(from decoder: Decoder) throws {
    if let begin = try? StructuredLogBegin(from: decoder) {
      self = .begin(begin)
    } else if let report = try? StructuredLogReport(from: decoder) {
      self = .report(report)
    } else if let end = try? StructuredLogEnd(from: decoder) {
      self = .end(end)
    } else {
      let context = DecodingError.Context(
        codingPath: decoder.codingPath,
        debugDescription: "Expected StructuredLogBegin, StructuredLogReport, or StructuredLogEnd"
      )
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .begin(let begin):
      try begin.encode(to: encoder)
    case .report(let report):
      try report.encode(to: encoder)
    case .end(let end):
      try end.encode(to: encoder)
    }
  }
}

/// Indicates the beginning of a new task that may receive updates with `StructuredLogReport` or `StructuredLogEnd`
/// payloads.
public struct StructuredLogBegin: Codable, Hashable, Sendable {
  /// A succinct title that can be used to describe the task that started this structured.
  public var title: String

  /// A unique identifier, identifying the task this structured log message belongs to.
  public var taskID: String

  private enum CodingKeys: CodingKey {
    case kind
    case title
    case taskID
  }

  public init(title: String, taskID: String) {
    self.title = title
    self.taskID = taskID
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .kind) == "begin" else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Kind of StructuredLogBegin is not 'begin'"
      )
    }

    self.title = try container.decode(String.self, forKey: .title)
    self.taskID = try container.decode(String.self, forKey: .taskID)

  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("begin", forKey: .kind)
    try container.encode(self.title, forKey: .title)
    try container.encode(self.taskID, forKey: .taskID)
  }
}

/// Adds a new log message to a structured log without ending it.
public struct StructuredLogReport: Codable, Hashable, Sendable {
  /// A unique identifier, identifying the task this structured log message belongs to.
  public var taskID: String

  private enum CodingKeys: CodingKey {
    case kind
    case taskID
  }

  public init(taskID: String) {
    self.taskID = taskID
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .kind) == "report" else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Kind of StructuredLogReport is not 'report'"
      )
    }

    self.taskID = try container.decode(String.self, forKey: .taskID)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("report", forKey: .kind)
    try container.encode(self.taskID, forKey: .taskID)
  }
}

/// Ends a structured log. No more `StructuredLogReport` updates should be sent for this task ID.
///
/// The task ID may be re-used for new structured logs by beginning a new structured log for that task.
public struct StructuredLogEnd: Codable, Hashable, Sendable {
  /// A unique identifier, identifying the task this structured log message belongs to.
  public var taskID: String

  private enum CodingKeys: CodingKey {
    case kind
    case taskID
  }

  public init(taskID: String) {
    self.taskID = taskID
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .kind) == "end" else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Kind of StructuredLogEnd is not 'end'"
      )
    }

    self.taskID = try container.decode(String.self, forKey: .taskID)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("end", forKey: .kind)
    try container.encode(self.taskID, forKey: .taskID)
  }
}
