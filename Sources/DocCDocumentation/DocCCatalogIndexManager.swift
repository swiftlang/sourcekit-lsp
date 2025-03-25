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

package import Foundation
@preconcurrency import SwiftDocC

final actor DocCCatalogIndexManager {
  private let server: DocCServer
  private var catalogToIndexMap: [URL: Result<DocCCatalogIndex, DocCIndexError>] = [:]

  init(server: DocCServer) {
    self.server = server
  }

  func invalidate(_ url: URL) {
    catalogToIndexMap.removeValue(forKey: url)
  }

  func index(for catalogURL: URL) async throws(DocCIndexError) -> DocCCatalogIndex {
    if let existingCatalog = catalogToIndexMap[catalogURL] {
      return try existingCatalog.get()
    }
    do {
      let convertResponse = try await server.convert(
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
      )
      guard let renderReferenceStoreData = convertResponse.renderReferenceStore else {
        throw DocCIndexError.unexpectedlyNilRenderReferenceStore
      }
      let renderReferenceStore = try JSONDecoder().decode(RenderReferenceStore.self, from: renderReferenceStoreData)
      let catalogIndex = DocCCatalogIndex(from: renderReferenceStore)
      catalogToIndexMap[catalogURL] = .success(catalogIndex)
      return catalogIndex
    } catch {
      let internalError = error as? DocCIndexError ?? DocCIndexError.internalError(error)
      catalogToIndexMap[catalogURL] = .failure(internalError)
      throw internalError
    }
  }
}

/// Represents a potential error that the ``DocCCatalogIndexManager`` could encounter while indexing
package enum DocCIndexError: LocalizedError {
  case internalError(any Error)
  case unexpectedlyNilRenderReferenceStore

  package var errorDescription: String? {
    switch self {
    case .internalError(let internalError):
      return "An internal error occurred: \(internalError.localizedDescription)"
    case .unexpectedlyNilRenderReferenceStore:
      return "Did not receive a RenderReferenceStore from the DocC server"
    }
  }
}

package struct DocCCatalogIndex: Sendable {
  private let assetReferenceToDataAsset: [String: DataAsset]
  private let documentationExtensionToSourceURL: [DocCSymbolLink: URL]
  let articlePathToSourceURLAndReference: [String: (URL, TopicRenderReference)]
  let tutorialPathToSourceURLAndReference: [String: (URL, TopicRenderReference)]
  let tutorialOverviewPathToSourceURLAndReference: [String: (URL, TopicRenderReference)]

  func asset(for assetReference: AssetReference) -> DataAsset? {
    assetReferenceToDataAsset[assetReference.assetName]
  }

  package func documentationExtension(for symbolLink: DocCSymbolLink) -> URL? {
    return documentationExtensionToSourceURL[symbolLink]
  }

  init(from renderReferenceStore: RenderReferenceStore) {
    // Assets
    var assetReferenceToDataAsset: [String: DataAsset] = [:]
    for (reference, asset) in renderReferenceStore.assets {
      var asset = asset
      asset.variants = asset.variants.compactMapValues { $0.withScheme("doc-asset") }
      assetReferenceToDataAsset[reference.assetName] = asset
    }
    self.assetReferenceToDataAsset = assetReferenceToDataAsset
    // Markdown and Tutorial content
    var documentationExtensionToSourceURL: [DocCSymbolLink: URL] = [:]
    var articlePathToSourceURLAndReference = [String: (URL, TopicRenderReference)]()
    var tutorialPathToSourceURLAndReference = [String: (URL, TopicRenderReference)]()
    var tutorialOverviewPathToSourceURLAndReference = [String: (URL, TopicRenderReference)]()
    for (renderReferenceKey, topicContentValue) in renderReferenceStore.topics {
      guard let topicRenderReference = topicContentValue.renderReference as? TopicRenderReference,
        let topicContentSource = topicContentValue.source
      else {
        continue
      }
      let lastPathComponent = renderReferenceKey.url.lastPathComponent

      switch topicRenderReference.kind {
      case .article:
        articlePathToSourceURLAndReference[lastPathComponent] = (topicContentSource, topicRenderReference)
      case .tutorial:
        tutorialPathToSourceURLAndReference[lastPathComponent] = (topicContentSource, topicRenderReference)
      case .overview:
        tutorialOverviewPathToSourceURLAndReference[lastPathComponent] = (topicContentSource, topicRenderReference)
      default:
        guard topicContentValue.isDocumentationExtensionContent,
          let absoluteSymbolLink = AbsoluteSymbolLink(string: topicContentValue.renderReference.identifier.identifier)
        else {
          continue
        }
        let doccSymbolLink = DocCSymbolLink(absoluteSymbolLink: absoluteSymbolLink)
        documentationExtensionToSourceURL[doccSymbolLink] = topicContentValue.source
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
