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

#if canImport(SwiftDocC)
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import SemanticIndex
@preconcurrency import SwiftDocC
import SwiftExtensions

final class DocCReferenceResolutionService: DocumentationService, Sendable {
  /// The message type that this service accepts.
  public static let symbolResolutionMessageType: DocumentationServer.MessageType = "resolve-reference"

  /// The message type that this service responds with when the requested symbol resolution was successful.
  public static let symbolResolutionResponseMessageType: DocumentationServer.MessageType = "resolve-reference-response"

  public static let handlingTypes = [symbolResolutionMessageType]

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
    completion: @escaping (DocumentationServer.Message) -> ()
  ) {
    guard let payload = message.payload else {
      completion(createResponseWithErrorMessage("Nil message payload provided."))
      return
    }

    let decodedRequest = Result {
      try JSONDecoder().decode(
        ConvertRequestContextWrapper<OutOfProcessReferenceResolver.Request>.self,
        from: payload
      )
    }
    .mapError { error -> ReferenceResolutionError in
      return .decodingFailure(error.localizedDescription)
    }
    switch decodedRequest {
    case let .success(request):
      resolveReference(request: request) { response in
        let symbolResolutionRequestResult = response.flatMap { response in
          Result {
            try JSONEncoder().encode(response)
          }
          .mapError { error -> ReferenceResolutionError in
            return .encodingFailure(error.localizedDescription)
          }
        }
        .flatMapError { error -> Result<Data, ReferenceResolutionError> in
          // This is a catch all for any errors we've encountered along the way. We want
          // to catch them here and convert them to reference resolver responses so
          // DocC knows why we were unable to resolve the link.

          let errorResponse = OutOfProcessReferenceResolver.Response.errorMessage(
            error.localizedDescription
          )

          return Result {
            return try JSONEncoder().encode(errorResponse)
          }
          .mapError { error -> ReferenceResolutionError in
            return .encodingFailure(error.localizedDescription)
          }
        }
        switch symbolResolutionRequestResult {
        case .success(let responsePayload):
          completion(
            self.createResponse(payload: responsePayload)
          )
        case .failure(let error):
          completion(
            self.createResponseWithErrorMessage(error.localizedDescription)
          )
        }
      }
    case .failure(let error):
      completion(createResponseWithErrorMessage(error.localizedDescription))
    }
  }

  private func resolveReference(
    request: ConvertRequestContextWrapper<OutOfProcessReferenceResolver.Request>,
    completion: @escaping (_: Result<OutOfProcessReferenceResolver.Response, ReferenceResolutionError>) -> Void
  ) {
    guard let convertRequestIdentifier = request.convertRequestIdentifier else {
      completion(.failure(.missingConvertRequestIdentifier))
      return
    }
    guard let context = context(forKey: convertRequestIdentifier) else {
      completion(.failure(.missingContext))
      return
    }
    switch request.payload {
    case .symbol(let symbolUSR):
      guard let index = context.uncheckedIndex?.checked(for: .deletedFiles) else {
        completion(.failure(.indexNotAvailable))
        return
      }
      guard let symbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: symbolUSR),
        let symbolURL = symbolOccurrence.location.documentUri.fileURL
      else {
        completion(.failure(.symbolNotFound(symbolUSR)))
        return
      }
      completion(
        .success(
          .resolvedInformation(
            OutOfProcessReferenceResolver.ResolvedInformation(
              symbolURL: symbolURL,
              symbolName: symbolOccurrence.symbol.name
            )
          )
        )
      )
    case .asset(let assetReference):
      guard let catalog = context.catalogIndex else {
        completion(.failure(.indexNotAvailable))
        break
      }
      guard let dataAsset = catalog.asset(for: assetReference) else {
        completion(.failure(.assetNotFound))
        break
      }
      completion(.success(.asset(dataAsset)))
    case .topic(let topicURL):
      // Check if this is a link to another documentation article
      let relevantPathComponents = topicURL.pathComponents.filter { $0 != "/" }
      let resolvedReference: TopicRenderReference? =
        switch relevantPathComponents.first {
        case NodeURLGenerator.Path.documentationFolderName:
          context.catalogIndex?.articlePathToSourceURLAndReference[topicURL.lastPathComponent]?.1
        case NodeURLGenerator.Path.tutorialsFolderName:
          context.catalogIndex?.tutorialPathToSourceURLAndReference[topicURL.lastPathComponent]?.1
        default:
          nil
        }
      if let resolvedReference {
        completion(
          .success(
            .resolvedInformation(OutOfProcessReferenceResolver.ResolvedInformation(resolvedReference, url: topicURL))
          )
        )
        return
      }
      // Otherwise this must be a link to a symbol
      let urlString = topicURL.absoluteString
      guard let absoluteSymbolLink = AbsoluteSymbolLink(string: urlString) else {
        completion(Result.failure(.invalidURLInRequest))
        break
      }
      // Don't bother checking to see if the symbol actually exists in the index. This can be time consuming and
      // it would be better to report errors/warnings for unresolved symbols directly within the document, anyway.
      completion(
        Result.success(
          .resolvedInformation(
            OutOfProcessReferenceResolver.ResolvedInformation(
              symbolURL: topicURL,
              symbolName: absoluteSymbolLink.symbolName
            )
          )
        )
      )
    }
  }

  private func createResponseWithErrorMessage(_ message: String) -> DocumentationServer.Message {
    let errorMessage = OutOfProcessReferenceResolver.Response.errorMessage(message)
    do {
      let encodedErrorMessage = try JSONEncoder().encode(errorMessage)
      return createResponse(payload: encodedErrorMessage)
    } catch {
      return createResponse(payload: nil)
    }
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
  let uncheckedIndex: UncheckedIndex?
  let catalogIndex: DocCCatalogIndex?
}

fileprivate extension AbsoluteSymbolLink {
  var symbolName: String {
    guard !representsModule else {
      return module
    }
    guard let lastComponent = basePathComponents.last else {
      return topLevelSymbol.name
    }
    return lastComponent.name
  }
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
#endif
