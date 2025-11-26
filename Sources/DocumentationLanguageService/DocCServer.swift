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
@preconcurrency import SwiftDocC

struct DocCServer {
  private let server: DocumentationServer

  init(peer peerServer: DocumentationServer? = nil, qualityOfService: DispatchQoS) {
    server = DocumentationServer.createDefaultServer(qualityOfService: qualityOfService, peer: peerServer)
  }

  /// Sends a request to SwiftDocC that will convert in-memory documentation.
  ///
  /// - Parameters:
  ///   - externalIDsToConvert: The external IDs of the symbols to convert.
  ///   - documentPathsToConvert: The paths of the documentation nodes to convert.
  ///   - includeRenderReferenceStore: Whether the conversion's render reference store should be included in
  ///     the response.
  ///   - documentationBundleLocation: The file location of the documentation bundle to convert, if any.
  ///   - documentationBundleDisplayName: The name of the documentation bundle to convert.
  ///   - documentationBundleIdentifier: The identifier of the documentation bundle to convert.
  ///   - symbolGraphs: The symbol graph data included in the documentation bundle to convert.
  ///   - overridingDocumentationComments: The mapping of external symbol identifiers to lines of a documentation
  ///     comment that overrides the value in the symbol graph.
  ///   - emitSymbolSourceFileURIs: Whether the conversion's rendered documentation should include source file
  ///     location metadata.
  ///   - markupFiles: The article and documentation extension file data included in the documentation bundle to convert.
  ///   - tutorialFiles: The tutorial file data included in the documentation bundle to convert.
  ///   - convertRequestIdentifier: A unique identifier for the request. Can be used to map additional data alongside
  ///     a request for use later on.
  /// - Throws: A ``DocCServerError`` representing the type of error that occurred.
  func convert(
    externalIDsToConvert: [String]?,
    documentPathsToConvert: [String]?,
    includeRenderReferenceStore: Bool,
    documentationBundleLocation: URL?,
    documentationBundleDisplayName: String,
    documentationBundleIdentifier: String,
    symbolGraphs: [Data],
    overridingDocumentationComments: [String: [String]] = [:],
    emitSymbolSourceFileURIs: Bool,
    markupFiles: [Data],
    tutorialFiles: [Data],
    convertRequestIdentifier: String
  ) async throws(DocCServerError) -> ConvertResponse {
    let request = ConvertRequest(
      bundleInfo: DocumentationBundle.Info(
        displayName: documentationBundleDisplayName,
        id: DocumentationBundle.Identifier(rawValue: documentationBundleIdentifier),
        defaultCodeListingLanguage: nil,
        defaultAvailability: nil,
        defaultModuleKind: nil
      ),
      externalIDsToConvert: externalIDsToConvert,
      documentPathsToConvert: documentPathsToConvert,
      includeRenderReferenceStore: includeRenderReferenceStore,
      bundleLocation: documentationBundleLocation,
      symbolGraphs: symbolGraphs,
      overridingDocumentationComments: overridingDocumentationComments.mapValues {
        $0.map { ConvertRequest.Line(text: $0) }
      },
      knownDisambiguatedSymbolPathComponents: nil,
      emitSymbolSourceFileURIs: emitSymbolSourceFileURIs,
      markupFiles: markupFiles,
      tutorialFiles: tutorialFiles,
      miscResourceURLs: [],
      symbolIdentifiersWithExpandedDocumentation: nil
    )
    let response = try await makeRequest(
      messageType: ConvertService.convertMessageType,
      messageIdentifier: convertRequestIdentifier,
      request: request
    )
    guard let responsePayload = response.payload else {
      throw .unexpectedlyNilPayload(response.type.rawValue)
    }
    // Check for an error response from SwiftDocC
    guard response.type != ConvertService.convertResponseErrorMessageType else {
      let convertServiceError: ConvertServiceError
      do {
        convertServiceError = try JSONDecoder().decode(ConvertServiceError.self, from: responsePayload)
      } catch {
        throw .messagePayloadDecodingFailure(messageType: response.type.rawValue, decodingError: error)
      }
      throw .internalError(convertServiceError)
    }
    guard response.type == ConvertService.convertResponseMessageType else {
      throw .unknownMessageType(response.type.rawValue)
    }
    // Decode the SwiftDocC.ConvertResponse and wrap it in our own Sendable type
    let doccConvertResponse: SwiftDocC.ConvertResponse
    do {
      doccConvertResponse = try JSONDecoder().decode(SwiftDocC.ConvertResponse.self, from: responsePayload)
    } catch {
      throw .decodingFailure(error)
    }
    return ConvertResponse(doccConvertResponse: doccConvertResponse)
  }

  private func makeRequest<Request: Encodable & Sendable>(
    messageType: DocumentationServer.MessageType,
    messageIdentifier: String,
    request: Request
  ) async throws(DocCServerError) -> DocumentationServer.Message {
    let result: Result<DocumentationServer.Message, DocCServerError> = await withCheckedContinuation { continuation in
      // Encode the request in JSON format
      let encodedPayload: Data
      do {
        encodedPayload = try JSONEncoder().encode(request)
      } catch {
        return continuation.resume(returning: .failure(.encodingFailure(error)))
      }
      // Encode the full message in JSON format
      let message = DocumentationServer.Message(
        type: messageType,
        identifier: messageIdentifier,
        payload: encodedPayload
      )
      let encodedMessage: Data
      do {
        encodedMessage = try JSONEncoder().encode(message)
      } catch {
        return continuation.resume(returning: .failure(.encodingFailure(error)))
      }
      // Send the request to the server and decode the response
      server.process(encodedMessage) { response in
        do {
          let decodedMessage = try JSONDecoder().decode(DocumentationServer.Message.self, from: response)
          continuation.resume(returning: .success(decodedMessage))
        } catch {
          continuation.resume(returning: .failure(.decodingFailure(error)))
        }
      }
    }
    return try result.get()
  }
}

/// A Sendable wrapper around ``SwiftDocC.ConvertResponse``
struct ConvertResponse: Sendable, Codable {
  /// The render nodes that were created as part of the conversion, encoded as JSON.
  let renderNodes: [Data]

  /// The render reference store that was created as part of the bundle's conversion, encoded as JSON.
  ///
  /// The ``RenderReferenceStore`` contains compiled information for documentation nodes that were registered as part of
  /// the conversion. This information can be used as a lightweight index of the available documentation content in the bundle that's
  /// been converted.
  let renderReferenceStore: Data?

  /// Creates a conversion response given the render nodes that were created as part of the conversion.
  init(renderNodes: [Data], renderReferenceStore: Data? = nil) {
    self.renderNodes = renderNodes
    self.renderReferenceStore = renderReferenceStore
  }

  /// Creates a conversion response given a SwiftDocC conversion response
  init(doccConvertResponse: SwiftDocC.ConvertResponse) {
    self.renderNodes = doccConvertResponse.renderNodes
    self.renderReferenceStore = doccConvertResponse.renderReferenceStore
  }
}

/// Represents a potential error that the ``DocCServer`` could encounter while processing requests
enum DocCServerError: LocalizedError {
  case encodingFailure(_ encodingError: any Error)
  case decodingFailure(_ decodingError: any Error)
  case messagePayloadDecodingFailure(messageType: String, decodingError: any Error)
  case unknownMessageType(_ messageType: String)
  case unexpectedlyNilPayload(_ messageType: String)
  case internalError(_ underlyingError: any LocalizedError)

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
    case .internalError(let underlyingError):
      return underlyingError.errorDescription
    }
  }
}
