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
@preconcurrency import SwiftDocC

package struct DocCServer {
  private let server: DocumentationServer
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()

  init(peer peerServer: DocumentationServer? = nil, qualityOfService: DispatchQoS) {
    server = DocumentationServer.createDefaultServer(qualityOfService: qualityOfService, peer: peerServer)
  }

  func convert(
    externalIDsToConvert: [String]?,
    documentPathsToConvert: [String]?,
    includeRenderReferenceStore: Bool,
    documentationBundleLocation: URL?,
    documentationBundleDisplayName: String,
    documentationBundleIdentifier: String,
    symbolGraphs: [Data],
    emitSymbolSourceFileURIs: Bool,
    markupFiles: [Data],
    tutorialFiles: [Data],
    convertRequestIdentifier: String,
    completion: @escaping (_: Result<ConvertResponse, DocCServerError>) -> Void
  ) {
    let request = ConvertRequest(
      bundleInfo: DocumentationBundle.Info(
        displayName: documentationBundleDisplayName,
        identifier: documentationBundleIdentifier,
        defaultCodeListingLanguage: nil,
        defaultAvailability: nil,
        defaultModuleKind: nil,
      ),
      externalIDsToConvert: externalIDsToConvert,
      documentPathsToConvert: documentPathsToConvert,
      includeRenderReferenceStore: includeRenderReferenceStore,
      bundleLocation: documentationBundleLocation,
      symbolGraphs: symbolGraphs,
      overridingDocumentationComments: nil,
      knownDisambiguatedSymbolPathComponents: nil,
      emitSymbolSourceFileURIs: emitSymbolSourceFileURIs,
      markupFiles: markupFiles,
      tutorialFiles: tutorialFiles,
      miscResourceURLs: [],
      symbolIdentifiersWithExpandedDocumentation: nil
    )

    makeRequest(
      messageType: ConvertService.convertMessageType,
      messageIdentifier: convertRequestIdentifier,
      request: request
    ) { response in
      completion(
        response.flatMap {
          message -> Result<Data, DocCServerError> in
          guard let messagePayload = message.payload else {
            return .failure(.unexpectedlyNilPayload(message.type.rawValue))
          }

          guard message.type != ConvertService.convertResponseErrorMessageType else {
            return Result {
              try self.jsonDecoder.decode(ConvertServiceError.self, from: messagePayload)
            }
            .flatMapError {
              .failure(
                DocCServerError.messagePayloadDecodingFailure(
                  messageType: message.type.rawValue,
                  decodingError: $0
                )
              )
            }
            .flatMap { .failure(.internalError($0)) }
          }

          guard message.type == ConvertService.convertResponseMessageType else {
            return .failure(.unknownMessageType(message.type.rawValue))
          }

          return .success(messagePayload)
        }
        .flatMap { convertMessagePayload -> Result<ConvertResponse, DocCServerError> in
          return Result {
            try self.jsonDecoder.decode(ConvertResponse.self, from: convertMessagePayload)
          }
          .flatMapError { decodingError -> Result<ConvertResponse, DocCServerError> in
            return .failure(
              DocCServerError.messagePayloadDecodingFailure(
                messageType: ConvertService.convertResponseMessageType.rawValue,
                decodingError: decodingError
              )
            )
          }
        }
      )
    }
  }

  private func makeRequest<Request: Encodable & Sendable>(
    messageType: DocumentationServer.MessageType,
    messageIdentifier: String,
    request: Request,
    completion: @escaping (_: Result<DocumentationServer.Message, DocCServerError>) -> Void
  ) {
    let encodedMessageResult: Result<Data, DocCServerError> = Result { try jsonEncoder.encode(request) }
      .mapError { .encodingFailure($0) }
      .flatMap { encodedPayload in
        Result {
          let message = DocumentationServer.Message(
            type: messageType,
            identifier: messageIdentifier,
            payload: encodedPayload
          )
          return try jsonEncoder.encode(message)
        }.mapError { encodingError -> DocCServerError in
          return .encodingFailure(encodingError)
        }
      }

    switch encodedMessageResult {
    case .success(let encodedMessage):
      server.process(encodedMessage) { response in
        let decodeMessageResult: Result<DocumentationServer.Message, DocCServerError> = Result {
          try self.jsonDecoder.decode(DocumentationServer.Message.self, from: response)
        }
        .flatMapError { .failure(.decodingFailure($0)) }
        completion(decodeMessageResult)
      }
    case .failure(let encodingError):
      completion(.failure(encodingError))
    }
  }
}

/// Represents a potential error that the ``DocCServer`` could encounter while processing requests
enum DocCServerError: LocalizedError {
  case encodingFailure(_ encodingError: Error)
  case decodingFailure(_ decodingError: Error)
  case messagePayloadDecodingFailure(messageType: String, decodingError: Error)
  case unknownMessageType(_ messageType: String)
  case unexpectedlyNilPayload(_ messageType: String)
  case internalError(_ underlyingError: DescribedError)

  var errorDescription: String? {
    switch self {
    case .encodingFailure(let encodingError):
      return "Failed to encode message: \(encodingError.localizedDescription)"
    case .decodingFailure(let decodingError):
      return "Failed to decode a received message: \(decodingError.localizedDescription)"
    case .messagePayloadDecodingFailure(let messageType, let decodingError):
      return
        "Received a message of type '\(messageType)' and failed to decode its payload: \(decodingError.localizedDescription)."
    case .unknownMessageType(let messageType):
      return "Received an unknown message type: '\(messageType)'."
    case .unexpectedlyNilPayload(let messageType):
      return "Received a message of type '\(messageType)' with a 'nil' payload."
    case .internalError(underlyingError: let underlyingError):
      return underlyingError.errorDescription
    }
  }
}
#endif
