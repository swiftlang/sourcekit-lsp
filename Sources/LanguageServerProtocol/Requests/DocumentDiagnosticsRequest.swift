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

public struct DocumentDiagnosticsRequest: TextDocumentRequest {
  public static var method: String = "textDocument/diagnostic"
  public typealias Response = DocumentDiagnosticReport

  /// The text document.
  public var textDocument: TextDocumentIdentifier

  /// The additional identifier  provided during registration.
  public var identifier: String?

  /// The result id of a previous response if provided.
  public var previousResultId: String?

  public init(textDocument: TextDocumentIdentifier, identifier: String? = nil, previousResultId: String? = nil) {
    self.textDocument = textDocument
    self.identifier = identifier
    self.previousResultId = previousResultId
  }
}

/// The result of a document diagnostic pull request. A report can
/// either be a full report containing all diagnostics for the
/// requested document or a unchanged report indicating that nothing
/// has changed in terms of diagnostics in comparison to the last
/// pull request.
public enum DocumentDiagnosticReport: ResponseType, Codable, Hashable {
  case full(RelatedFullDocumentDiagnosticReport)
  case unchanged(RelatedUnchangedDocumentDiagnosticReport)

  public init(from decoder: Decoder) throws {
    if let full = try? RelatedFullDocumentDiagnosticReport(from: decoder) {
      self = .full(full)
    } else if let unchanged = try? RelatedUnchangedDocumentDiagnosticReport(from: decoder) {
      self = .unchanged(unchanged)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected RelatedFullDocumentDiagnosticReport or RelatedUnchangedDocumentDiagnosticReport")
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

/// The document diagnostic report kinds.
public struct DocumentDiagnosticReportKind: RawRepresentable, Codable, Hashable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// A diagnostic report with a full
  /// set of problems.
  public static let full = DocumentDiagnosticReportKind(rawValue: "full")

  /// A report indicating that the last
  /// returned report is still accurate.
  public static let unchanged = DocumentDiagnosticReportKind(rawValue: "unchanged")
}

/// A diagnostic report with a full set of problems.
public struct RelatedFullDocumentDiagnosticReport: Codable, Hashable {
  /// An optional result id. If provided it will
  /// be sent on the next diagnostic request for the
  /// same document.
  public var resultId: String?

  /// The actual items.
  public var items: [Diagnostic]

  /// Diagnostics of related documents. This information is useful
  /// in programming languages where code in a file A can generate
  /// diagnostics in a file B which A depends on. An example of
  /// such a language is C/C++ where marco definitions in a file
  /// a.cpp and result in errors in a header file b.hpp.
  public var relatedDocuments: [DocumentURI: DocumentDiagnosticReport]?

  public init(resultId: String? = nil, items: [Diagnostic], relatedDocuments: [DocumentURI : DocumentDiagnosticReport]? = nil) {
    self.resultId = resultId
    self.items = items
    self.relatedDocuments = relatedDocuments
  }

  enum CodingKeys: CodingKey {
    case kind
    case resultId
    case items
    case relatedDocuments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(DocumentDiagnosticReportKind.self, forKey: .kind)
    guard kind == .full else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of FullDocumentDiagnosticReport is not 'full'")
    }
    self.resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
    self.items = try container.decode([Diagnostic].self, forKey: .items)
    self.relatedDocuments = try container.decodeIfPresent([DocumentURI: DocumentDiagnosticReport].self, forKey: .relatedDocuments)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(DocumentDiagnosticReportKind.full, forKey: .kind)
    try container.encodeIfPresent(self.resultId, forKey: .resultId)
    try container.encode(self.items, forKey: .items)
    try container.encodeIfPresent(self.relatedDocuments, forKey: .relatedDocuments)
  }
}

/// A diagnostic report indicating that the last returned
/// report is still accurate.
public struct RelatedUnchangedDocumentDiagnosticReport: Codable, Hashable {
  /// A result id which will be sent on the next
  /// diagnostic request for the same document.
  public var resultId: String

  /// Diagnostics of related documents. This information is useful
  /// in programming languages where code in a file A can generate
  /// diagnostics in a file B which A depends on. An example of
  /// such a language is C/C++ where marco definitions in a file
  /// a.cpp and result in errors in a header file b.hpp.
  public var relatedDocuments: [DocumentURI: DocumentDiagnosticReport]?

  public init(resultId: String, relatedDocuments: [DocumentURI : DocumentDiagnosticReport]? = nil) {
    self.resultId = resultId
    self.relatedDocuments = relatedDocuments
  }

  enum CodingKeys: CodingKey {
    case kind
    case resultId
    case relatedDocuments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(DocumentDiagnosticReportKind.self, forKey: .kind)
    guard kind == .unchanged else {
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Kind of FullDocumentDiagnosticReport is not 'unchanged'")
    }
    self.resultId = try container.decode(String.self, forKey: .resultId)
    self.relatedDocuments = try container.decodeIfPresent([DocumentURI: DocumentDiagnosticReport].self, forKey: .relatedDocuments)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(DocumentDiagnosticReportKind.unchanged, forKey: .kind)
    try container.encode(self.resultId, forKey: .resultId)
    try container.encodeIfPresent(self.relatedDocuments, forKey: .relatedDocuments)
  }
}
