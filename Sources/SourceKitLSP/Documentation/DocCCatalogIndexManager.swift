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

  func index(for catalogURL: URL, moduleName: String?) async throws(DocCIndexError) -> DocCCatalogIndex {
    if let existingCatalog = catalogToIndexMap[catalogURL] {
      return try existingCatalog.get()
    }
    let catalogIndexResult: Result<DocCCatalogIndex, DocCIndexError>
    do {
      let convertResponse = try await server.convert(
        externalIDsToConvert: [],
        documentPathsToConvert: [],
        includeRenderReferenceStore: true,
        documentationBundleLocation: catalogURL,
        documentationBundleDisplayName: moduleName ?? "unknown",
        documentationBundleIdentifier: "unknown",
        symbolGraphs: [],
        emitSymbolSourceFileURIs: true,
        markupFiles: [],
        tutorialFiles: [],
        convertRequestIdentifier: UUID().uuidString
      )
      catalogIndexResult = Result { convertResponse }
        .flatMap { convertResponse in
          guard let renderReferenceStoreData = convertResponse.renderReferenceStore else {
            return .failure(.unexpectedlyNilRenderReferenceStore)
          }
          return .success(renderReferenceStoreData)
        }
        .flatMap { renderReferenceStoreData in
          Result { try JSONDecoder().decode(RenderReferenceStore.self, from: renderReferenceStoreData) }
            .flatMapError { .failure(.decodingFailure($0)) }
        }
        .map { DocCCatalogIndex(from: $0) }
    } catch {
      catalogIndexResult = .failure(.serverError(error))
    }
    catalogToIndexMap[catalogURL] = catalogIndexResult
    return try catalogIndexResult.get()
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
  let articlePathToSourceURLAndReference: [String: (URL, TopicRenderReference)]
  let tutorialPathToSourceURLAndReference: [String: (URL, TopicRenderReference)]
  let tutorialOverviewPathToSourceURLAndReference: [String: (URL, TopicRenderReference)]

  func asset(for assetReference: AssetReference) -> DataAsset? {
    assetReferenceToDataAsset[assetReference.assetName] ?? fuzzyAssetReferenceToDataAsset[assetReference.assetName]
  }

  func documentationExtension(for symbolLink: DocCSymbolLink) -> URL? {
    documentationExtensionToSourceURL[symbolLink]
  }

  init(from renderReferenceStore: RenderReferenceStore) {
    // Assets
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
    // Markdown and Tutorial content
    var documentationExtensionToSourceURL = [DocCSymbolLink: URL]()
    var articlePathToSourceURLAndReference = [String: (URL, TopicRenderReference)]()
    var tutorialPathToSourceURLAndReference = [String: (URL, TopicRenderReference)]()
    var tutorialOverviewPathToSourceURLAndReference = [String: (URL, TopicRenderReference)]()
    for (renderReferenceKey, topicContentValue) in renderReferenceStore.topics {
      guard let topicRenderReference = topicContentValue.renderReference as? TopicRenderReference,
        let topicContentSource = topicContentValue.source
      else {
        continue
      }

      if topicContentValue.isDocumentationExtensionContent {
        guard
          let absoluteSymbolLink = AbsoluteSymbolLink(string: topicContentValue.renderReference.identifier.identifier)
        else {
          continue
        }
        let doccSymbolLink = DocCSymbolLink(absoluteSymbolLink: absoluteSymbolLink)
        documentationExtensionToSourceURL[doccSymbolLink] = topicContentValue.source
      } else if topicRenderReference.kind == .article {
        articlePathToSourceURLAndReference[renderReferenceKey.url.lastPathComponent] = (
          topicContentSource, topicRenderReference
        )
      } else if topicRenderReference.kind == .tutorial {
        tutorialPathToSourceURLAndReference[renderReferenceKey.url.lastPathComponent] = (
          topicContentSource, topicRenderReference
        )
      } else if topicRenderReference.kind == .overview {
        tutorialOverviewPathToSourceURLAndReference[renderReferenceKey.url.lastPathComponent] = (
          topicContentSource, topicRenderReference
        )
      }
    }
    self.documentationExtensionToSourceURL = documentationExtensionToSourceURL
    self.articlePathToSourceURLAndReference = articlePathToSourceURLAndReference
    self.tutorialPathToSourceURLAndReference = tutorialPathToSourceURLAndReference
    self.tutorialOverviewPathToSourceURLAndReference = tutorialOverviewPathToSourceURLAndReference
  }
}

fileprivate extension URL {
  func withScheme(_ scheme: String) -> URL {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
    components?.scheme = scheme
    return components?.url ?? self
  }
}
#endif
