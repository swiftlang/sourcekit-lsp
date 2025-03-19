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
import BuildSystemIntegration
import BuildServerProtocol
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import Markdown
import SemanticIndex
import SwiftDocC
import SwiftExtensions
import SwiftSyntax
import SymbolKit

package final actor DocumentationManager {
  private let doccServer: DocCServer
  private let referenceResolutionService: DocCReferenceResolutionService
  private let catalogIndexManager: DocCCatalogIndexManager

  init() {
    let symbolResolutionServer = DocumentationServer(qualityOfService: .unspecified)
    doccServer = DocCServer(
      peer: symbolResolutionServer,
      qualityOfService: .default
    )
    catalogIndexManager = DocCCatalogIndexManager(server: doccServer)
    referenceResolutionService = DocCReferenceResolutionService()
    symbolResolutionServer.register(service: referenceResolutionService)
  }

  func filesDidChange(_ events: [FileEvent]) async {
    let affectedCatalogURLs = events.reduce(into: Set<URL>()) { affectedCatalogURLs, event in
      guard let catalogURL = event.uri.fileURL?.doccCatalogURL else {
        return
      }
      affectedCatalogURLs.insert(catalogURL)
    }
    await catalogIndexManager.invalidate(catalogURLs: affectedCatalogURLs)
  }

  func emptySymbolGraph(moduleName: String) throws -> String {
    let data = try JSONEncoder().encode(
      SymbolGraph(
        metadata: SymbolGraph.Metadata(
          formatVersion: SymbolGraph.SemanticVersion(major: 0, minor: 5, patch: 0),
          generator: "SourceKit-LSP"
        ),
        module: SymbolGraph.Module(name: moduleName, platform: SymbolGraph.Platform()),
        symbols: [],
        relationships: []
      )
    )
    guard let result = String(data: data, encoding: .utf8) else {
      throw ResponseError.internalError("Failed to encode symbol graph")
    }
    return result
  }

  func catalogIndex(for catalogURL: URL) async throws(DocCIndexError) -> DocCCatalogIndex {
    try await catalogIndexManager.index(for: catalogURL)
  }

  func renderDocCDocumentation(
    symbolUSR: String? = nil,
    symbolGraph: String? = nil,
    overrideDocComments: [String]? = nil,
    markupFile: String? = nil,
    tutorialFile: String? = nil,
    moduleName: String?,
    catalogURL: URL?
  ) async throws -> DoccDocumentationResponse {
    // Make inputs consumable by DocC
    var externalIDsToConvert: [String]? = nil
    var overridingDocumentationComments = [String: [String]]()
    if let symbolUSR {
      externalIDsToConvert = [symbolUSR]
      if let overrideDocComments {
        overridingDocumentationComments[symbolUSR] = overrideDocComments
      }
    }
    var symbolGraphs = [Data]()
    if let symbolGraphData = symbolGraph?.data(using: .utf8) {
      symbolGraphs.append(symbolGraphData)
    }
    var markupFiles = [Data]()
    if let markupFile = markupFile?.data(using: .utf8) {
      markupFiles.append(markupFile)
    }
    var tutorialFiles = [Data]()
    if let tutorialFile = tutorialFile?.data(using: .utf8) {
      tutorialFiles.append(tutorialFile)
    }
    // Store the convert request identifier in order to fulfill index requests from SwiftDocC
    let convertRequestIdentifier = UUID().uuidString
    var catalogIndex: DocCCatalogIndex? = nil
    if let catalogURL {
      catalogIndex = try await self.catalogIndex(for: catalogURL)
    }
    referenceResolutionService.addContext(
      DocCReferenceResolutionContext(
        catalogURL: catalogURL,
        catalogIndex: catalogIndex
      ),
      withKey: convertRequestIdentifier
    )
    // Send the convert request to SwiftDocC and wait for the response
    let convertResponse = try await doccServer.convert(
      externalIDsToConvert: externalIDsToConvert,
      documentPathsToConvert: nil,
      includeRenderReferenceStore: false,
      documentationBundleLocation: nil,
      documentationBundleDisplayName: moduleName ?? "Unknown",
      documentationBundleIdentifier: "unknown",
      symbolGraphs: symbolGraphs,
      overridingDocumentationComments: overridingDocumentationComments,
      emitSymbolSourceFileURIs: false,
      markupFiles: markupFiles,
      tutorialFiles: tutorialFiles,
      convertRequestIdentifier: convertRequestIdentifier
    )
    guard let renderNodeData = convertResponse.renderNodes.first else {
      throw ResponseError.internalError("SwiftDocC did not return any render nodes")
    }
    guard let renderNode = String(data: renderNodeData, encoding: .utf8) else {
      throw ResponseError.internalError("Failed to encode render node from SwiftDocC")
    }
    return DoccDocumentationResponse(renderNode: renderNode)
  }
}
#endif
