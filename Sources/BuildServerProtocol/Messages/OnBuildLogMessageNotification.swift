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

/// The log message notification is sent from a server to a client to ask the client to log a particular message in its console.
///
/// A `build/logMessage`` notification is similar to LSP's `window/logMessage``, except for a few additions like id and originId.
public struct OnBuildLogMessageNotification: BSPNotification {
  public static let method: String = "build/logMessage"

  /// The message type.
  public var type: MessageType

  /// The task id if any.
  public var task: TaskId?

  /// The request id that originated this notification.
  /// The originId field helps clients know which request originated a notification in case several requests are handled by the
  /// client at the same time. It will only be populated if the client defined it in the request that triggered this notification.
  public var originId: OriginId?

  /// The actual message.
  public var message: String

  /// Extends BSPs log message grouping by explicitly starting and ending the log for a specific task ID.
  ///
  /// **(BSP Extension)***
  public var structure: StructuredLogKind?

  public init(
    type: MessageType,
    task: TaskId? = nil,
    originId: OriginId? = nil,
    message: String,
    structure: StructuredLogKind? = nil
  ) {
    self.type = type
    self.task = task
    self.originId = originId
    self.message = message
    self.structure = structure
  }
}

public enum StructuredLogKind: Codable, Hashable, Sendable {
  case begin(StructuredLogBegin)
  case report(StructuredLogReport)
  case end(StructuredLogEnd)

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

  private enum CodingKeys: CodingKey {
    case kind
    case title
  }

  public init(title: String) {
    self.title = title
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

  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("begin", forKey: .kind)
    try container.encode(self.title, forKey: .title)
  }
}

/// Adds a new log message to a structured log without ending it.
public struct StructuredLogReport: Codable, Hashable, Sendable {
  private enum CodingKeys: CodingKey {
    case kind
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .kind) == "report" else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Kind of StructuredLogReport is not 'report'"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("report", forKey: .kind)
  }
}

/// Ends a structured log. No more `StructuredLogReport` updates should be sent for this task ID.
///
/// The task ID may be re-used for new structured logs by beginning a new structured log for that task.
public struct StructuredLogEnd: Codable, Hashable, Sendable {
  private enum CodingKeys: CodingKey {
    case kind
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .kind) == "end" else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Kind of StructuredLogEnd is not 'end'"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("end", forKey: .kind)
  }
}
