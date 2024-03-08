//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct DocumentSemanticTokensDeltaRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/semanticTokens/full/delta"
  public typealias Response = DocumentSemanticTokensDeltaResponse?

  /// The document to fetch semantic tokens for.
  public var textDocument: TextDocumentIdentifier

  /// The result identifier of a previous response, which acts as the diff base for the delta.
  /// This can either point to a full response or a delta response, depending on what was
  /// last received by the client.
  public var previousResultId: String

  public init(textDocument: TextDocumentIdentifier, previousResultId: String) {
    self.textDocument = textDocument
    self.previousResultId = previousResultId
  }
}

public enum DocumentSemanticTokensDeltaResponse: ResponseType, Codable, Equatable {
  case tokens(DocumentSemanticTokensResponse)
  case delta(SemanticTokensDelta)

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let tokens = try? container.decode(DocumentSemanticTokensResponse.self) {
      self = .tokens(tokens)
    } else if let delta = try? container.decode(SemanticTokensDelta.self) {
      self = .delta(delta)
    } else {
      let error = "DocumentSemanticTokensDeltaResponse has neither SemanticTokens or SemanticTokensDelta."
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .tokens(let tokens):
      try container.encode(tokens)
    case .delta(let delta):
      try container.encode(delta)
    }
  }
}

public struct SemanticTokensDelta: Codable, Hashable, Sendable {
  /// An optional result identifier which enables supporting clients to request semantic token deltas
  /// subsequent requests.
  public var resultId: String?

  /// The edits to transform a previous result into a new result.
  public var edits: [SemanticTokensEdit]

  public init(resultId: String? = nil, edits: [SemanticTokensEdit]) {
    self.resultId = resultId
    self.edits = edits
  }
}

public struct SemanticTokensEdit: Codable, Hashable, Sendable {
  /// Start offset of the edit.
  public var start: Int

  /// The number of elements to remove.
  public var deleteCount: Int

  /// The elements to insert.
  public var data: [UInt32]?

  public init(start: Int, deleteCount: Int, data: [UInt32]? = nil) {
    self.start = start
    self.deleteCount = deleteCount
    self.data = data
  }
}
