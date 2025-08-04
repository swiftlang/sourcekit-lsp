//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import BuildServerIntegration
import BuildServerProtocol
package import Foundation
package import LanguageServerProtocol
import SKLogging
import SwiftDocC

package struct DocCDocumentationManager: Sendable {
  private let doccServer: DocCServer
  private let referenceResolutionService: DocCReferenceResolutionService
  private let catalogIndexManager: DocCCatalogIndexManager

  private let buildServerManager: BuildServerManager

  package init(buildServerManager: BuildServerManager) {
    let symbolResolutionServer = DocumentationServer(qualityOfService: .unspecified)
    doccServer = DocCServer(
      peer: symbolResolutionServer,
      qualityOfService: .default
    )
    catalogIndexManager = DocCCatalogIndexManager(server: doccServer)
    referenceResolutionService = DocCReferenceResolutionService()
    symbolResolutionServer.register(service: referenceResolutionService)
    self.buildServerManager = buildServerManager
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    for event in events {
      for target in await buildServerManager.targets(for: event.uri) {
        guard let catalogURL = await buildServerManager.doccCatalog(for: target) else {
          continue
        }
        await catalogIndexManager.invalidate(catalogURL)
      }
    }
  }

  package func catalogIndex(for catalogURL: URL) async throws(DocCIndexError) -> DocCCatalogIndex {
    try await catalogIndexManager.index(for: catalogURL)
  }

  /// Generates the SwiftDocC RenderNode for a given symbol, tutorial, or markdown file.
  ///
  /// - Parameters:
  ///   - symbolUSR: The USR of the symbol to render
  ///   - symbolGraph: The symbol graph that includes the given symbol USR
  ///   - overrideDocComments: An array of documentation comment lines that will override the comments in the symbol graph
  ///   - markupFile: The markdown article or symbol extension to render
  ///   - tutorialFile: The tutorial file to render
  ///   - moduleName: The name of the Swift module that will be rendered
  ///   - catalogURL: The URL pointing to the docc catalog that this symbol, tutorial, or markdown file is a part of
  /// - Throws: A ResponseError if something went wrong
  /// - Returns: The DoccDocumentationResponse containing the RenderNode if successful
  package func renderDocCDocumentation(
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
    var overridingDocumentationComments: [String: [String]] = [:]
    if let symbolUSR {
      externalIDsToConvert = [symbolUSR]
      if let overrideDocComments {
        overridingDocumentationComments[symbolUSR] = overrideDocComments
      }
    }
    var symbolGraphs: [Data] = []
    if let symbolGraphData = symbolGraph?.data(using: .utf8) {
      symbolGraphs.append(symbolGraphData)
    }
    var markupFiles: [Data] = []
    if let markupFile = markupFile?.data(using: .utf8) {
      markupFiles.append(markupFile)
    }
    var tutorialFiles: [Data] = []
    if let tutorialFile = tutorialFile?.data(using: .utf8) {
      tutorialFiles.append(tutorialFile)
    }
    // Store the convert request identifier in order to fulfill index requests from SwiftDocC
    let convertRequestIdentifier = UUID().uuidString
    var catalogIndex: DocCCatalogIndex? = nil
    if let catalogURL {
      catalogIndex = try await catalogIndexManager.index(for: catalogURL)
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
