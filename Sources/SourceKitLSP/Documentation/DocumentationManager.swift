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

  func catalogIndex(for catalogURL: URL, moduleName: String?) async throws(DocCIndexError) -> DocCCatalogIndex {
    try await catalogIndexManager.index(for: catalogURL, moduleName: moduleName)
  }

  func convertDocumentation(
    workspace: Workspace,
    buildInformation: DocCBuildInformation,
    externalIDsToConvert: [String]? = nil,
    symbolGraphs: [Data] = [],
    overridingDocumentationComments: [String: [String]] = [:],
    markupFiles: [Data] = [],
    tutorialFiles: [Data] = []
  ) async throws -> DoccDocumentationResponse {
    // Store the convert request identifier in order to fulfill index requests from SwiftDocC
    let convertRequestIdentifier = UUID().uuidString
    referenceResolutionService.addContext(
      DocCReferenceResolutionContext(
        catalogURL: buildInformation.catalogURL,
        uncheckedIndex: workspace.uncheckedIndex,
        catalogIndex: buildInformation.catalogIndex
      ),
      withKey: convertRequestIdentifier
    )
    // Send the convert request to SwiftDocC and wait for the response
    let convertResponse = try await doccServer.convert(
      externalIDsToConvert: externalIDsToConvert,
      documentPathsToConvert: nil,
      includeRenderReferenceStore: false,
      documentationBundleLocation: nil,
      documentationBundleDisplayName: buildInformation.moduleName ?? "Unknown",
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
