//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request for generating documentation for the symbol at a given location **(LSP Extension)**.
///
/// This request looks up the symbol (if any) at a given text document location and returns a
/// ``DoccDocumentationResponse`` for that location. This request is primarily designed for editors
/// to support live preview of Swift documentation.
///
/// - Parameters:
///   - textDocument: The document to render documentation for.
///   - position: The document location at which to lookup symbol information. (optional)
///
/// - Returns: A ``DoccDocumentationResponse`` for the given location, which may contain an error
///   message if documentation could not be converted. This error message can be displayed to the user
///   in the live preview editor.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP.
/// The client is expected to display the documentation in an editor using swift-docc-render.
public struct DoccDocumentationRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/doccDocumentation"
  public typealias Response = DoccDocumentationResponse

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position?

  public init(textDocument: TextDocumentIdentifier, position: Position?) {
    self.textDocument = textDocument
    self.position = position
  }
}

public enum DoccDocumentationResponse: ResponseType {
  case renderNode(String)
  case error(DoccDocumentationError)
}

public enum DoccDocumentationError: ResponseType, Equatable {
  case indexNotAvailable
  case noDocumentation
  case symbolNotFound(String)

  var message: String {
    switch self {
    case .indexNotAvailable:
      return "The index is not availble to complete the request"
    case .noDocumentation:
      return "No documentation could be rendered for the position in this document"
    case .symbolNotFound(let symbolName):
      return "Could not find symbol \(symbolName) in the project"
    }
  }
}

extension DoccDocumentationError: Codable {
  enum CodingKeys: String, CodingKey {
    case kind
    case message
    case symbolName
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(String.self, forKey: .kind)
    switch kind {
    case "indexNotAvailable":
      self = .indexNotAvailable
    case "noDocumentation":
      self = .noDocumentation
    case "symbolNotFound":
      let symbolName = try values.decode(String.self, forKey: .symbolName)
      self = .symbolNotFound(symbolName)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: CodingKeys.kind,
        in: values,
        debugDescription: "Invalid error kind: \(kind)"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .indexNotAvailable:
      try container.encode("indexNotAvailable", forKey: .kind)
    case .noDocumentation:
      try container.encode("noDocumentation", forKey: .kind)
    case .symbolNotFound(let symbolName):
      try container.encode("symbolNotFound", forKey: .kind)
      try container.encode(symbolName, forKey: .symbolName)
    }
    try container.encode(message, forKey: .message)
  }
}

extension DoccDocumentationResponse: Codable {
  enum CodingKeys: String, CodingKey {
    case type
    case renderNode
    case error
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let type = try values.decode(String.self, forKey: .type)
    switch type {
    case "renderNode":
      let renderNode = try values.decode(String.self, forKey: .renderNode)
      self = .renderNode(renderNode)
    case "error":
      let error = try values.decode(DoccDocumentationError.self, forKey: .error)
      self = .error(error)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: CodingKeys.type,
        in: values,
        debugDescription: "Invalid type: \(type)"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .renderNode(let renderNode):
      try container.encode("renderNode", forKey: .type)
      try container.encode(renderNode, forKey: .renderNode)
    case .error(let error):
      try container.encode("error", forKey: .type)
      try container.encode(error, forKey: .error)
    }
  }
}
