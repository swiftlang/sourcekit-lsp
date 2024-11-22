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

import Foundation
import IndexStoreDB
import SemanticIndex
@preconcurrency import SwiftDocC
import SwiftExtensions

final class DocCSymbolResolutionService: SwiftDocC.DocumentationService, Sendable {
  struct Context {
    let catalogURL: URL
    let uncheckedIndex: UncheckedIndex?
    let catalogIndex: DocCCatalogIndex?
  }

  /// The message type that this service accepts.
  public static let symbolResolutionMessageType: DocumentationServer.MessageType = "resolve-reference"

  /// The message type that this service responds with when the requested symbol resolution was successful.
  public static let symbolResolutionResponseMessageType: DocumentationServer.MessageType = "resolve-reference-response"

  static let handlingTypes = [symbolResolutionMessageType]

  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()

  private let contextMap = ThreadSafeBox<[String: Context]>(initialValue: [:])

  init() {}

  func add(context: Context, withKey key: String) {
    contextMap.value[key] = context
  }

  @discardableResult func removeContext(forKey key: String) -> Context? {
    contextMap.value.removeValue(forKey: key)
  }

  func context(forKey key: String) -> Context? {
    contextMap.value[key]
  }

  func lookupSymbolLink(usr: String, index: CheckedIndex) -> Result<DocCSymbolLink, SymbolLookupError> {
    guard let symbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
      return .failure(.symbolNotFound(usr: usr))
    }
    let module = symbolOccurrence.location.moduleName
    var components = [symbolOccurrence.symbol.name]
    var parentSymbol = symbolOccurrence.relations.first { $0.roles.contains(.childOf) }?.symbol
    while let currentSymbol = parentSymbol {
      components.insert(currentSymbol.name, at: 0)
      parentSymbol =
        index.occurrences(ofUSR: currentSymbol.usr, roles: .definition).first?.relations.first {
          $0.roles.contains(.childOf)
        }?.symbol
    }
    guard let symbolLink = DocCSymbolLink(module: module, components: components) else {
      return .failure(.malformedSymbolLink)
    }
    return .success(symbolLink)
  }

  func lookupSymbol(usr: String, index: CheckedIndex) -> Result<DocumentationSymbol, SymbolLookupError> {
    guard let symbol = index.occurrences(ofUSR: usr, roles: .definition).first else {
      return .failure(.symbolNotFound(usr: usr))
    }
    return .success(.init(symbol))
  }

  func lookupSymbol(
    forLink symbolLink: DocCSymbolLink,
    index: CheckedIndex
  ) -> Result<DocumentationSymbol, SymbolLookupError> {
    // Do a lookup to find the top level symbol
    var components = symbolLink.components
    var topLevelSymbolOccurrence: SymbolOccurrence? = nil
    index.forEachCanonicalSymbolOccurrence(byName: components.removeFirst().name) { symbolOccurrence in
      guard symbolOccurrence.location.moduleName == symbolLink.module else {
        return true
      }
      topLevelSymbolOccurrence = symbolOccurrence
      return false
    }
    // Find any child symbols
    var currentSymbolOccurence: SymbolOccurrence? = topLevelSymbolOccurrence
    while let parentSymbolOccurrence = currentSymbolOccurence, components.count > 0 {
      let nextComponent = components.removeFirst()
      currentSymbolOccurence = index.occurrences(relatedToUSR: parentSymbolOccurrence.symbol.usr, roles: .childOf)
        .first { $0.symbol.name == nextComponent.name }
    }
    guard let symbolOccurrence = currentSymbolOccurence else {
      return .failure(.symbolNotFound(name: symbolLink.absoluteString))
    }
    return .success(.init(symbolOccurrence))
  }

  func process(
    _ message: DocumentationServer.Message,
    completion: @escaping (DocumentationServer.Message) -> ()
  ) {
    guard let payload = message.payload else {
      completion(resolveSymbolResponseErrorMessage("Nil message payload provided."))
      return
    }

    let decodedRequest = Result {
      try jsonDecoder.decode(
        ConvertRequestContextWrapper<OutOfProcessReferenceResolver.Request>.self,
        from: payload
      )
    }
    .mapError { error -> SymbolResolutionError in
      return .decodingFailure(error.localizedDescription)
    }
    switch decodedRequest {
    case let .success(request):
      resolveReference(request: request) { response in
        let symbolResolutionRequestResult = response.flatMap { response in
          Result {
            try self.jsonEncoder.encode(response)
          }
          .mapError { error -> SymbolResolutionError in
            return .encodingFailure(error.localizedDescription)
          }
        }
        .flatMapError { error -> Result<Data, SymbolResolutionError> in
          // This is a catch all for any errors we've encountered along the way. We want
          // to catch them here and convert them to reference resolver responses so
          // DocC knows why we were unable to resolve the link.

          let errorResponse = OutOfProcessReferenceResolver.Response.errorMessage(
            error.localizedDescription
          )

          return Result {
            return try self.jsonEncoder.encode(errorResponse)
          }
          .mapError { error -> SymbolResolutionError in
            return .encodingFailure(error.localizedDescription)
          }
        }
        switch symbolResolutionRequestResult {
        case .success(let responsePayload):
          completion(
            self.resolveSymbolResponseMessage(payload: responsePayload)
          )
        case .failure(let error):
          completion(
            self.resolveSymbolResponseErrorMessage(error.localizedDescription)
          )
        }
      }
    case .failure(let error):
      completion(resolveSymbolResponseErrorMessage(error.localizedDescription))
    }
  }

  private func resolveReference(
    request: ConvertRequestContextWrapper<OutOfProcessReferenceResolver.Request>,
    completion: @escaping (_: Result<OutOfProcessReferenceResolver.Response, SymbolResolutionError>) -> Void
  ) {
    guard let convertRequestIdentifier = request.convertRequestIdentifier else {
      completion(.failure(.missingConvertRequestIdentifier))
      return
    }
    guard let context = context(forKey: convertRequestIdentifier) else {
      completion(.failure(.resolutionFailure))
      return
    }
    switch request.payload {
    case .symbol(let symbolUSR):
      guard let index = context.uncheckedIndex?.checked(for: .deletedFiles) else {
        completion(.failure(.resolutionFailure))
        return
      }
      completion(
        lookupSymbol(usr: symbolUSR, index: index).mapError { error -> SymbolResolutionError in
          return .resolutionFailure
        }.flatMap { symbol -> Result<OutOfProcessReferenceResolver.Response, SymbolResolutionError> in
          guard let symbolURL = symbol.location.documentUri.fileURL else {
            return .failure(.resolutionFailure)
          }
          return .success(.resolvedInformation(.init(symbolURL: symbolURL, symbolName: symbol.name)))
        }
      )
    case .asset(let assetReference):
      guard let catalog = context.catalogIndex else {
        completion(.failure(.resolutionFailure))
        break
      }
      guard let dataAsset = catalog.asset(for: assetReference) else {
        completion(.failure(.resolutionFailure))
        break
      }
      completion(.success(.asset(dataAsset)))
    case .topic(let topicURL):
      let relevantPathComponents = topicURL.pathComponents.filter { $0 != "/" }

      let resolvedReference: TopicRenderReference?
      switch relevantPathComponents.first {
      case NodeURLGenerator.Path.documentationFolderName:
        resolvedReference = nil  // catalogIndex?.articlePathToSourceURLAndReference[topicURL.lastPathComponent]?.1
      case NodeURLGenerator.Path.tutorialsFolderName:
        resolvedReference = nil  // catalogIndex?.tutorialPathToSourceURLAndReference[topicURL.lastPathComponent]?.1
      default:
        resolvedReference = nil
      }
      if let resolvedReference = resolvedReference {
        completion(.success(.resolvedInformation(.init(resolvedReference, url: topicURL))))
        return
      }

      guard let index = context.uncheckedIndex?.checked(for: .deletedFiles),
        let symbolLink = DocCSymbolLink(string: topicURL.absoluteString)
      else {
        completion(.failure(.resolutionFailure))
        break
      }
      completion(
        lookupSymbol(forLink: symbolLink, index: index).mapError { _ in .resolutionFailure }.map {
          return .resolvedInformation(.init(symbolURL: topicURL, symbolName: $0.name))
        }
      )
    }
  }

  private func resolveSymbolResponseErrorMessage(_ message: String) -> DocumentationServer.Message {
    let errorMessage = OutOfProcessReferenceResolver.Response.errorMessage(message)
    do {
      let encodedErrorMessage = try JSONEncoder().encode(errorMessage)
      return resolveSymbolResponseMessage(payload: encodedErrorMessage)
    } catch {
      return resolveSymbolResponseMessage(payload: nil)
    }
  }

  private func resolveSymbolResponseMessage(payload: Data?) -> DocumentationServer.Message {
    DocumentationServer.Message(
      type: DocCSymbolResolutionService.symbolResolutionResponseMessageType,
      payload: payload
    )
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

enum SymbolResolutionError: LocalizedError {
  case systemFailure
  case invalidURLInRequest
  case urlInitializationFailure(String)
  case resolutionFailure
  case decodingFailure(String)
  case encodingFailure(String)
  case unsupportedRequest
  case missingConvertRequestIdentifier

  var errorDescription: String? {
    switch self {
    case .systemFailure:
      return "The service is currently unable to resolve symbols."
    case .decodingFailure(let error):
      return """
        The service was unable to decode the given symbol resolution \
        request: '\(error)'.
        """
    case .resolutionFailure:
      return "The given symbol could not be resolved in the current workspace."
    case .unsupportedRequest:
      return "The service is unable to resolve the given kind of resolution request."
    case .encodingFailure(let error):
      return "The service failed to encode the result after resolving the symbol: \(error)"
    case .invalidURLInRequest:
      return "Failed to initialize an 'AbsoluteSymbolLink' from the given URL."
    case .missingConvertRequestIdentifier:
      return "The given request was missing a convert request identifier."
    case .urlInitializationFailure(let error):
      return "Failed to initialize URL: \(error)"
    }
  }
}

struct DocumentationSymbol: Sendable {
  let usr: String
  let name: String
  let location: SymbolLocation

  init(_ symbolOccurrence: SymbolOccurrence) {
    self.usr = symbolOccurrence.symbol.usr
    self.name = symbolOccurrence.symbol.name
    self.location = symbolOccurrence.location
  }
}

enum SymbolLookupError: LocalizedError {
  case malformedSymbol(String)
  case symbolNotFound(name: String)
  case symbolNotFound(usr: String)
  case malformedSymbolLink
}
