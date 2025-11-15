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

import DocCCommon
import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
@_spi(Linkcompletion) @preconcurrency import SwiftDocC
import SwiftExtensions

final class DocCReferenceResolutionService: DocumentationService, Sendable {
  /// The message type that this service accepts.
  static let symbolResolutionMessageType: DocumentationServer.MessageType = "resolve-reference"

  /// The message type that this service responds with when the requested symbol resolution was successful.
  static let symbolResolutionResponseMessageType: DocumentationServer.MessageType = "resolve-reference-response"

  static let handlingTypes = [symbolResolutionMessageType]

  private let contextMap = ThreadSafeBox<[String: DocCReferenceResolutionContext]>(initialValue: [:])

  init() {}

  func addContext(_ context: DocCReferenceResolutionContext, withKey key: String) {
    contextMap.value[key] = context
  }

  @discardableResult func removeContext(forKey key: String) -> DocCReferenceResolutionContext? {
    contextMap.value.removeValue(forKey: key)
  }

  func context(forKey key: String) -> DocCReferenceResolutionContext? {
    contextMap.value[key]
  }

  func process(
    _ message: DocumentationServer.Message,
    completion: @escaping (DocumentationServer.Message) -> Void
  ) {
    do {
      let response = try process(message)
      completion(response)
    } catch {
      completion(createResponseWithErrorMessage(error.localizedDescription))
    }
  }

  private func process(
    _ message: DocumentationServer.Message
  ) throws(ReferenceResolutionError) -> DocumentationServer.Message {
    // Decode the message payload
    guard let payload = message.payload else {
      throw ReferenceResolutionError.nilMessagePayload
    }
    let request = try decode(ConvertRequestContextWrapper<OutOfProcessReferenceResolver.Request>.self, from: payload)
    // Attempt to resolve the reference in the request
    let resolvedReference = try resolveReference(request: request);
    // Encode the response payload
    let encodedResolvedReference = try encode(resolvedReference)
    return createResponse(payload: encodedResolvedReference)
  }

  private func resolveReference(
    request: ConvertRequestContextWrapper<OutOfProcessReferenceResolver.Request>
  ) throws(ReferenceResolutionError) -> OutOfProcessReferenceResolver.Response {
    guard let convertRequestIdentifier = request.convertRequestIdentifier else {
      throw .missingConvertRequestIdentifier
    }
    guard let context = context(forKey: convertRequestIdentifier) else {
      throw .missingContext
    }
    switch request.payload {
    case .symbol(let symbolUSR):
      throw .symbolNotFound(symbolUSR)
    case .asset(let assetReference):
      guard let catalog = context.catalogIndex else {
        throw .indexNotAvailable
      }
      guard let dataAsset = catalog.assets[assetReference.assetName] else {
        throw .assetNotFound
      }
      return .asset(dataAsset)
    case .topic(let topicURL):
      // Check if this is a link to another documentation article
      let relevantPathComponents = topicURL.pathComponents.filter { $0 != "/" }
      let resolvedReference: TopicRenderReference? =
        switch relevantPathComponents.first {
        case NodeURLGenerator.Path.documentationFolderName:
          context.catalogIndex?.articles[topicURL.lastPathComponent]
        case NodeURLGenerator.Path.tutorialsFolderName:
          context.catalogIndex?.tutorials[topicURL.lastPathComponent]
        default:
          nil
        }
      if let resolvedReference {
        return .resolvedInformation(OutOfProcessReferenceResolver.ResolvedInformation(resolvedReference, url: topicURL))
      }
      // Otherwise this must be a link to a symbol
      let urlString = topicURL.absoluteString
      guard let doccSymbolLink = DocCSymbolLink(linkString: urlString) else {
        throw .invalidURLInRequest
      }
      // Don't bother checking to see if the symbol actually exists in the index. This can be time consuming and
      // it would be better to report errors/warnings for unresolved symbols directly within the document, anyway.
      return .resolvedInformation(
        OutOfProcessReferenceResolver.ResolvedInformation(
          symbolURL: topicURL,
          symbolName: doccSymbolLink.symbolName
        )
      )
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(ReferenceResolutionError) -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw .decodingFailure(error.localizedDescription)
    }
  }

  private func encode<T: Encodable>(_ value: T) throws(ReferenceResolutionError) -> Data {
    do {
      return try JSONEncoder().encode(value)
    } catch {
      throw .decodingFailure(error.localizedDescription)
    }
  }

  private func createResponseWithErrorMessage(_ message: String) -> DocumentationServer.Message {
    let errorMessage = OutOfProcessReferenceResolver.Response.errorMessage(message)
    let encodedErrorMessage = orLog("Encoding error message for OutOfProcessReferenceResolver.Response") {
      try JSONEncoder().encode(errorMessage)
    }
    return createResponse(payload: encodedErrorMessage)
  }

  private func createResponse(payload: Data?) -> DocumentationServer.Message {
    DocumentationServer.Message(
      type: DocCReferenceResolutionService.symbolResolutionResponseMessageType,
      payload: payload
    )
  }
}

struct DocCReferenceResolutionContext {
  let catalogURL: URL?
  let catalogIndex: DocCCatalogIndex?
}

fileprivate extension OutOfProcessReferenceResolver.ResolvedInformation {
  init(symbolURL: URL, symbolName: String) {
    self = OutOfProcessReferenceResolver.ResolvedInformation(
      kind: .unknownSymbol,
      url: symbolURL,
      title: symbolName,
      abstract: "",
      language: .swift,
      availableLanguages: [.swift],
      platforms: [],
      declarationFragments: nil
    )
  }

  init(_ renderReference: TopicRenderReference, url: URL) {
    let kind: DocumentationNode.Kind
    switch renderReference.kind {
    case .article:
      kind = .article
    case .tutorial, .overview:
      kind = .tutorial
    case .symbol:
      kind = .unknownSymbol
    case .section:
      kind = .unknown
    }

    self.init(
      kind: kind,
      url: url,
      title: renderReference.title,
      abstract: renderReference.abstract.map(\.plainText).joined(),
      language: .swift,
      availableLanguages: [.swift, .objectiveC],
      topicImages: renderReference.images
    )
  }
}

enum ReferenceResolutionError: LocalizedError {
  case nilMessagePayload
  case invalidURLInRequest
  case decodingFailure(String)
  case encodingFailure(String)
  case missingConvertRequestIdentifier
  case missingContext
  case indexNotAvailable
  case symbolNotFound(String)
  case assetNotFound

  var errorDescription: String? {
    switch self {
    case .nilMessagePayload:
      return "Nil message payload provided."
    case .decodingFailure(let error):
      return "The service was unable to decode the given symbol resolution request: '\(error)'."
    case .encodingFailure(let error):
      return "The service failed to encode the result after resolving the symbol: \(error)"
    case .invalidURLInRequest:
      return "Failed to initialize an 'AbsoluteSymbolLink' from the given URL."
    case .missingConvertRequestIdentifier:
      return "The given request was missing a convert request identifier."
    case .missingContext:
      return "The given convert request identifier is not associated with any symbol resolution context."
    case .indexNotAvailable:
      return "An index was not available to complete this request."
    case .symbolNotFound(let symbol):
      return "Unable to find symbol '\(symbol)' in the index."
    case .assetNotFound:
      return "The requested asset could not be found."
    }
  }
}
