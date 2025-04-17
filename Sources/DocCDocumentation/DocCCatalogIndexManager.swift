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
import SKLogging
import SKUtilities
@_spi(LinkCompletion) @preconcurrency import SwiftDocC

final actor DocCCatalogIndexManager {
  private let server: DocCServer

  /// The cache of DocCCatalogIndex for a given SwiftDocC catalog URL
  ///
  /// - Note: The capacity has been chosen without scientific measurements. The
  ///   feeling is that switching between SwiftDocC catalogs is rare and 5 catalog
  ///   indexes won't take up much memory.
  private var indexCache = LRUCache<URL, Result<DocCCatalogIndex, DocCIndexError>>(capacity: 5)

  init(server: DocCServer) {
    self.server = server
  }

  func invalidate(_ url: URL) {
    indexCache.removeValue(forKey: url)
  }

  func index(for catalogURL: URL) async throws(DocCIndexError) -> DocCCatalogIndex {
    if let existingCatalog = indexCache[catalogURL] {
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
      indexCache[catalogURL] = .success(catalogIndex)
      return catalogIndex
    } catch {
      // Don't cache cancellation errors
      guard !(error is CancellationError) else {
        throw .cancelled
      }
      let internalError = error as? DocCIndexError ?? DocCIndexError.internalError(error)
      indexCache[catalogURL] = .failure(internalError)
      throw internalError
    }
  }
}

/// Represents a potential error that the ``DocCCatalogIndexManager`` could encounter while indexing
package enum DocCIndexError: LocalizedError {
  case internalError(any Error)
  case unexpectedlyNilRenderReferenceStore
  case cancelled

  package var errorDescription: String? {
    switch self {
    case .internalError(let internalError):
      return "An internal error occurred: \(internalError.localizedDescription)"
    case .unexpectedlyNilRenderReferenceStore:
      return "Did not receive a RenderReferenceStore from the DocC server"
    case .cancelled:
      return "The request was cancelled"
    }
  }
}

package struct DocCCatalogIndex: Sendable {
  /// A map from an asset name to its DataAsset contents.
  let assets: [String: DataAsset]

  /// An array of DocCSymbolLink and their associated document URLs.
  let documentationExtensions: [(link: DocCSymbolLink, documentURL: URL?)]

  /// A map from article name to its TopicRenderReference.
  let articles: [String: TopicRenderReference]

  /// A map from tutorial name to its TopicRenderReference.
  let tutorials: [String: TopicRenderReference]

  // A map from tutorial overview name to its TopicRenderReference.
  let tutorialOverviews: [String: TopicRenderReference]

  /// Retrieves the documentation extension URL for the given symbol if one exists.
  ///
  /// - Parameter symbolInformation: The `DocCSymbolInformation` representing the symbol to search for.
  package func documentationExtension(for symbolInformation: DocCSymbolInformation) -> URL? {
    documentationExtensions.filter { symbolInformation.matches($0.link) }.first?.documentURL
  }

  init(from renderReferenceStore: RenderReferenceStore) {
    // Assets
    var assets: [String: DataAsset] = [:]
    for (reference, asset) in renderReferenceStore.assets {
      var asset = asset
      asset.variants = asset.variants.compactMapValues { url in
        orLog("Failed to convert asset from RenderReferenceStore") { try url.withScheme("doc-asset") }
      }
      assets[reference.assetName] = asset
    }
    self.assets = assets
    // Markdown and Tutorial content
    var documentationExtensionToSourceURL: [(link: DocCSymbolLink, documentURL: URL?)] = []
    var articles: [String: TopicRenderReference] = [:]
    var tutorials: [String: TopicRenderReference] = [:]
    var tutorialOverviews: [String: TopicRenderReference] = [:]
    for (renderReferenceKey, topicContentValue) in renderReferenceStore.topics {
      guard let topicRenderReference = topicContentValue.renderReference as? TopicRenderReference else {
        continue
      }
      // Article and Tutorial URLs in SwiftDocC are always of the form `doc://<BundleID>/<Type>/<ModuleName>/<Filename>`.
      // Therefore, we only really need to store the filename in these cases which will always be the last path component.
      let lastPathComponent = renderReferenceKey.url.lastPathComponent

      switch topicRenderReference.kind {
      case .article:
        articles[lastPathComponent] = topicRenderReference
      case .tutorial:
        tutorials[lastPathComponent] = topicRenderReference
      case .overview:
        tutorialOverviews[lastPathComponent] = topicRenderReference
      default:
        guard topicContentValue.isDocumentationExtensionContent, renderReferenceKey.url.pathComponents.count > 2 else {
          continue
        }
        // Documentation extensions are always of the form `doc://<BundleID>/documentation/<SymbolPath>`.
        // We want to parse the `SymbolPath` in this case and store it in the index for lookups later.
        let linkString = renderReferenceKey.url.pathComponents[2...].joined(separator: "/")
        guard let doccSymbolLink = DocCSymbolLink(linkString: linkString) else {
          continue
        }
        documentationExtensionToSourceURL.append((link: doccSymbolLink, documentURL: topicContentValue.source))
      }
    }
    self.documentationExtensions = documentationExtensionToSourceURL
    self.articles = articles
    self.tutorials = tutorials
    self.tutorialOverviews = tutorialOverviews
  }
}

fileprivate enum WithSchemeError: LocalizedError {
  case failedToRetrieveComponents(URL)
  case failedToEncode(URLComponents)

  var errorDescription: String? {
    switch self {
    case .failedToRetrieveComponents(let url):
      "Failed to retrieve components for URL \(url.absoluteString)"
    case .failedToEncode(let components):
      "Failed to encode URL components \(String(reflecting: components))"
    }
  }
}

fileprivate extension URL {
  func withScheme(_ scheme: String) throws(WithSchemeError) -> URL {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
      throw WithSchemeError.failedToRetrieveComponents(self)
    }
    components.scheme = scheme
    guard let result = components.url else {
      throw WithSchemeError.failedToEncode(components)
    }
    return result
  }
}
