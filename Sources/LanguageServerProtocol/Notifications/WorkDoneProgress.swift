//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum WorkDoneProgress: NotificationType, Hashable {
  public static var method: String = "$/progress"

  case begin(WorkDoneProgressBegin)
  case report(WorkDoneProgressReport)
  case end(WorkDoneProgressEnd)

  public init(from decoder: Decoder) throws {
    if let begin = try? WorkDoneProgressBegin(from: decoder) {
      self = .begin(begin)
    } else if let report = try? WorkDoneProgressReport(from: decoder) {
      self = .report(report)
    } else if let end = try? WorkDoneProgressEnd(from: decoder) {
      self = .end(end)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected WorkDoneProgressBegin, WorkDoneProgressReport, or WorkDoneProgressEnd")
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

public struct WorkDoneProgressBegin: Codable, Hashable {
  /// Mandatory title of the progress operation. Used to briefly inform about
  /// the kind of operation being performed.
  ///
  /// Examples: "Indexing" or "Linking dependencies".
  public var title: String

  /// Controls if a cancel button should show to allow the user to cancel the
  /// long running operation. Clients that don't support cancellation are
  /// allowed to ignore the setting.
  public var cancellable: Bool?

  /// Optional, more detailed associated progress message. Contains
  /// complementary information to the `title`.
  ///
  /// Examples: "3/25 files", "project/src/module2", "node_modules/some_dep".
  /// If unset, the previous progress message (if any) is still valid.
  public var message: String?

  /// Optional progress percentage to display (value 100 is considered 100%).
  /// If not provided infinite progress is assumed and clients are allowed
  /// to ignore the `percentage` value in subsequent in report notifications.
  ///
  /// The value should be steadily rising. Clients are free to ignore values
  /// that are not following this rule. The value range is [0, 100]
  public var percentage: Int?

  public init(title: String, cancellable: Bool? = nil, message: String? = nil, percentage: Int? = nil) {
    self.title = title
    self.cancellable = cancellable
    self.message = message
    self.percentage = percentage
  }

  enum CodingKeys: CodingKey {
    case kind
    case title
    case cancellable
    case message
    case percentage
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    guard kind == "begin" else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of WorkDoneProgressBegin is not 'begin'")
    }

    self.title = try container.decode(String.self, forKey: .title)
    self.cancellable = try container.decodeIfPresent(Bool.self, forKey: .cancellable)
    self.message = try container.decodeIfPresent(String.self, forKey: .message)
    self.percentage = try container.decodeIfPresent(Int.self, forKey: .percentage)
  }


  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("begin", forKey: .kind)
    try container.encode(self.title, forKey: .title)
    try container.encodeIfPresent(self.cancellable, forKey: .cancellable)
    try container.encodeIfPresent(self.message, forKey: .message)
    try container.encodeIfPresent(self.percentage, forKey: .percentage)
  }
}

public struct WorkDoneProgressReport: Codable, Hashable {
  /// Controls enablement state of a cancel button. This property is only valid
  /// if a cancel button got requested in the `WorkDoneProgressBegin` payload.
  ///
  /// Clients that don't support cancellation or don't support control the
  /// button's enablement state are allowed to ignore the setting.
  public var cancellable: Bool?

  /// Optional, more detailed associated progress message. Contains
  /// complementary information to the `title`.
  ///
  /// Examples: "3/25 files", "project/src/module2", "node_modules/some_dep".
  /// If unset, the previous progress message (if any) is still valid.
  public var message: String?

  /// Optional progress percentage to display (value 100 is considered 100%).
  /// If not provided infinite progress is assumed and clients are allowed
  /// to ignore the `percentage` value in subsequent in report notifications.
  ///
  /// The value should be steadily rising. Clients are free to ignore values
  /// that are not following this rule. The value range is [0, 100]
  public var percentage: Int?

  public init(cancellable: Bool? = nil, message: String? = nil, percentage: Int? = nil) {
    self.cancellable = cancellable
    self.message = message
    self.percentage = percentage
  }

  enum CodingKeys: CodingKey {
    case kind
    case cancellable
    case message
    case percentage
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    guard kind == "report" else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of WorkDoneProgressReport is not 'report'")
    }

    self.cancellable = try container.decodeIfPresent(Bool.self, forKey: .cancellable)
    self.message = try container.decodeIfPresent(String.self, forKey: .message)
    self.percentage = try container.decodeIfPresent(Int.self, forKey: .percentage)
  }


  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("report", forKey: .kind)
    try container.encodeIfPresent(self.cancellable, forKey: .cancellable)
    try container.encodeIfPresent(self.message, forKey: .message)
    try container.encodeIfPresent(self.percentage, forKey: .percentage)
  }
}

public struct WorkDoneProgressEnd: Codable, Hashable {
  /// Optional, a final message indicating to for example indicate the outcome
  /// of the operation.
  public var message: String?

  public init(message: String? = nil) {
    self.message = message
  }

  enum CodingKeys: CodingKey {
    case kind
    case message
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    guard kind == "end" else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of WorkDoneProgressReport is not 'end'")
    }

    self.message = try container.decodeIfPresent(String.self, forKey: .message)
  }


  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("end", forKey: .kind)
    try container.encodeIfPresent(self.message, forKey: .message)
  }
}
