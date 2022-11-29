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

/// A previous result id in a workspace pull request.
public struct PreviousResultId: Codable {
  /// The URI for which the client knows a result id.
  public var uri: DocumentURI

  /// The value of the previous result id.
  public var value: String

  public init(uri: DocumentURI, value: String) {
    self.uri = uri
    self.value = value
  }
}

public struct WorkspaceDiagnosticsRequest: RequestType {
  public static var method: String = "workspace/diagnostic"
  public typealias Response = WorkspaceDiagnosticReport

  /// The additional identifier provided during registration.
  public var identifier: String?

  /// The currently known diagnostic reports with their
  /// previous result ids.
  public var previousResultIds: [PreviousResultId]

  public init(identifier: String? = nil, previousResultIds: [PreviousResultId]) {
    self.identifier = identifier
    self.previousResultIds = previousResultIds
  }
}

/// A workspace diagnostic report.
public struct WorkspaceDiagnosticReport: ResponseType {
  public var items: [WorkspaceDocumentDiagnosticReport]

  public init(items: [WorkspaceDocumentDiagnosticReport]) {
    self.items = items
  }
}

/// A full document diagnostic report for a workspace diagnostic result.
public struct WorkspaceFullDocumentDiagnosticReport: Codable, Hashable {
  /// An optional result id. If provided it will
  /// be sent on the next diagnostic request for the
  /// same document.
  public var resultId: String?

  /// The actual items.
  public var items: [Diagnostic]

  /// The URI for which diagnostic information is reported.
  public var uri: DocumentURI

  /// The version number for which the diagnostics are reported.
 /// If the document is not marked as open `null` can be provided.
  public var version: Int?

  public init(resultId: String? = nil, items: [Diagnostic], uri: DocumentURI, version: Int? = nil) {
    self.resultId = resultId
    self.items = items
    self.uri = uri
    self.version = version
  }

  enum CodingKeys: CodingKey {
    case kind
    case resultId
    case items
    case uri
    case version
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(DocumentDiagnosticReportKind.self, forKey: .kind)
    guard kind == .full else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of FullDocumentDiagnosticReport is not 'full'")
    }
    self.resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
    self.items = try container.decode([Diagnostic].self, forKey: .items)
    self.uri = try container.decode(DocumentURI.self, forKey: .uri)
    self.version = try container.decodeIfPresent(Int.self, forKey: .version)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(DocumentDiagnosticReportKind.full, forKey: .kind)
    try container.encodeIfPresent(self.resultId, forKey: .resultId)
    try container.encode(self.items, forKey: .items)
    try container.encode(self.uri, forKey: .uri)
    try container.encodeIfPresent(self.version, forKey: .version)
  }
}

/// An unchanged document diagnostic report for a workspace diagnostic result.
public struct WorkspaceUnchangedDocumentDiagnosticReport: Codable, Hashable {
  /// A result id which will be sent on the next
  /// diagnostic request for the same document.
  public var resultId: String


  /// The URI for which diagnostic information is reported.
  public var uri: DocumentURI

  /// The version number for which the diagnostics are reported.
  /// If the document is not marked as open `null` can be provided.
  public var version: Int?

  public init(resultId: String, uri: DocumentURI, version: Int? = nil) {
    self.resultId = resultId
    self.uri = uri
    self.version = version
  }

  enum CodingKeys: CodingKey {
    case kind
    case resultId
    case uri
    case version
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(DocumentDiagnosticReportKind.self, forKey: .kind)
    guard kind == .unchanged else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of FullDocumentDiagnosticReport is not 'unchanged'")
    }
    self.resultId = try container.decode(String.self, forKey: .resultId)
    self.uri = try container.decode(DocumentURI.self, forKey: .uri)
    self.version = try container.decodeIfPresent(Int.self, forKey: .version)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(DocumentDiagnosticReportKind.unchanged, forKey: .kind)
    try container.encode(self.resultId, forKey: .resultId)
    try container.encode(self.uri, forKey: .uri)
    try container.encodeIfPresent(self.version, forKey: .version)
  }
}

/// A workspace diagnostic document report.
public enum WorkspaceDocumentDiagnosticReport: Codable, Hashable {
  case full(WorkspaceFullDocumentDiagnosticReport)
  case unchanged(WorkspaceUnchangedDocumentDiagnosticReport)

  public init(from decoder: Decoder) throws {
    if let full = try? WorkspaceFullDocumentDiagnosticReport(from: decoder) {
      self = .full(full)
    } else if let unchanged = try? WorkspaceUnchangedDocumentDiagnosticReport(from: decoder) {
      self = .unchanged(unchanged)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected WorkspaceFullDocumentDiagnosticReport or WorkspaceUnchangedDocumentDiagnosticReport")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .full(let full):
      try full.encode(to: encoder)
    case .unchanged(let unchanged):
      try unchanged.encode(to: encoder)
    }
  }
}
