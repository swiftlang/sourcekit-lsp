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
import LanguageServerProtocol
@preconcurrency import SwiftDocC
import SwiftExtensions

final actor DocCCatalogIndexManager {
  private let server: DocCServer
  private var catalogToIndexMap = [URL: Result<DocCCatalogIndex, DocCIndexError>]()

  init(server: DocCServer) {
    self.server = server
  }

  func invalidate(catalogURLs: some Collection<URL>) {
    guard catalogURLs.count > 0 else {
      return
    }
    for catalogURL in catalogURLs {
      catalogToIndexMap.removeValue(forKey: catalogURL)
    }
  }

  func index(for catalogURL: URL) async -> Result<DocCCatalogIndex, DocCIndexError> {
    if let existingCatalog = catalogToIndexMap[catalogURL] {
      return existingCatalog
    }
    let catalog: Result<DocCCatalogIndex, DocCIndexError> = await withCheckedContinuation { continuation in
      server.convert(
        externalIDsToConvert: [],
        documentPathsToConvert: [],
        includeRenderReferenceStore: true,
        documentationBundleLocation: catalogURL,
        documentationBundleDisplayName: "unknown",
        documentationBundleIdentifier: "unknown",
        symbolGraphs: [],
        emitSymbolSourceFileURIs: true,
        markupFiles: [],
        tutorialFiles: [],
        convertRequestIdentifier: UUID().uuidString
      ) { response in
        switch response {
        case .success(let convertResponse):
          guard let renderReferenceStoreData = convertResponse.renderReferenceStore else {
            continuation.resume(returning: .failure(.unexpectedlyNilRenderReferenceStore))
            break
          }
          continuation.resume(
            returning:
              Result { try JSONDecoder().decode(RenderReferenceStore.self, from: renderReferenceStoreData) }
              .flatMapError { .failure(.decodingFailure($0)) }
              .map { DocCCatalogIndex(from: $0) }
          )
        case .failure(let error):
          continuation.resume(returning: .failure(.serverError(error)))
        }
      }
    }
    catalogToIndexMap[catalogURL] = catalog
    return catalog
  }
}

/// Represents a potential error that the ``DocCCatalogIndexManager`` could encounter while indexing
enum DocCIndexError: LocalizedError {
  case decodingFailure(Error)
  case serverError(DocCServerError)
  case unexpectedlyNilRenderReferenceStore

  var errorDescription: String? {
    switch self {
    case .decodingFailure(let decodingError):
      return "Failed to decode a received message: \(decodingError.localizedDescription)"
    case .serverError(let serverError):
      return "DocC server failed to convert the catalog: \(serverError.localizedDescription)"
    case .unexpectedlyNilRenderReferenceStore:
      return "Did not receive a RenderReferenceStore from the DocC server"
    }
  }
}

struct DocCCatalogIndex: Sendable {
  private let assetReferenceToDataAsset: [String: DataAsset]
  private let fuzzyAssetReferenceToDataAsset: [String: DataAsset]
  private let documentationExtensionToSourceURL: [DocCSymbolLink: URL]

  func asset(for assetReference: AssetReference) -> DataAsset? {
    assetReferenceToDataAsset[assetReference.assetName] ?? fuzzyAssetReferenceToDataAsset[assetReference.assetName]
  }

  func documentationExtension(for symbolLink: DocCSymbolLink) -> URL? {
    documentationExtensionToSourceURL[symbolLink]
  }

  init(from renderReferenceStore: RenderReferenceStore) {
    var assetReferenceToDataAsset = [String: DataAsset]()
    var fuzzyAssetReferenceToDataAsset = [String: DataAsset]()
    for (reference, asset) in renderReferenceStore.assets {
      var asset = asset
      asset.variants = asset.variants.compactMapValues { $0.withScheme("doc-asset") }
      assetReferenceToDataAsset[reference.assetName] = asset
      if let indexOfExtensionDelimiter = reference.assetName.lastIndex(of: ".") {
        let assetNameWithoutExtension = reference.assetName.prefix(upTo: indexOfExtensionDelimiter)
        fuzzyAssetReferenceToDataAsset[String(assetNameWithoutExtension)] = asset
      }
    }
    self.assetReferenceToDataAsset = assetReferenceToDataAsset
    self.fuzzyAssetReferenceToDataAsset = fuzzyAssetReferenceToDataAsset

    var documentationExtensionToSourceURL = [DocCSymbolLink: URL]()
    for (_, topicContent) in renderReferenceStore.topics {
      if topicContent.isDocumentationExtensionContent {
        guard let absoluteSymbolLink = AbsoluteSymbolLink(string: topicContent.renderReference.identifier.identifier)
        else {
          continue
        }
        let doccSymbolLink = DocCSymbolLink(symbolLink: absoluteSymbolLink)
        documentationExtensionToSourceURL[doccSymbolLink] = topicContent.source
      }
    }
    self.documentationExtensionToSourceURL = documentationExtensionToSourceURL
  }
}

fileprivate extension URL {
  func withScheme(_ scheme: String) -> URL {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
    components?.scheme = scheme
    return components?.url ?? self
  }
}
