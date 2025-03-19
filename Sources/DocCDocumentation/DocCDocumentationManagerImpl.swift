#if canImport(SwiftDocC)
import BuildServerProtocol
import BuildSystemIntegration
package import Foundation
package import IndexStoreDB
package import LanguageServerProtocol
package import SemanticIndex
import SwiftDocC
import SwiftExtensions
import SwiftSyntax

package final actor DocCDocumentationManagerImpl: DocCDocumentationManagerWithRendering {
  private let doccServer: DocCServer
  private let referenceResolutionService: DocCReferenceResolutionService
  private let catalogIndexManager: DocCCatalogIndexManager

  package init() {
    let symbolResolutionServer = DocumentationServer(qualityOfService: .unspecified)
    doccServer = DocCServer(
      peer: symbolResolutionServer,
      qualityOfService: .default
    )
    catalogIndexManager = DocCCatalogIndexManager(server: doccServer)
    referenceResolutionService = DocCReferenceResolutionService()
    symbolResolutionServer.register(service: referenceResolutionService)
  }

  package func getRenderingSupport() -> (any DocCDocumentationManagerWithRendering)? {
    self
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    let affectedCatalogURLs = events.reduce(into: Set<URL>()) { affectedCatalogURLs, event in
      guard let catalogURL = event.uri.fileURL?.doccCatalogURL else {
        return
      }
      affectedCatalogURLs.insert(catalogURL)
    }
    await catalogIndexManager.invalidate(catalogURLs: affectedCatalogURLs)
  }

  package func catalogIndex(for catalogURL: URL) async throws(DocCIndexError) -> any DocCCatalogIndex {
    try await catalogIndexManager.index(for: catalogURL)
  }

  package func symbolLink(string: String) -> (any DocCSymbolLink)? {
    DocCSymbolLinkImpl(string: string)
  }

  package func symbolLink(forUSR usr: String, in index: CheckedIndex) -> (any DocCSymbolLink)? {
    guard let topLevelSymbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
      return nil
    }
    let module = topLevelSymbolOccurrence.location.moduleName
    var components = [topLevelSymbolOccurrence.symbol.name]
    // Find any child symbols
    var symbolOccurrence: SymbolOccurrence? = topLevelSymbolOccurrence
    while let currentSymbolOccurrence = symbolOccurrence, components.count > 0 {
      let parentRelation = currentSymbolOccurrence.relations.first { $0.roles.contains(.childOf) }
      guard let parentRelation else {
        break
      }
      if parentRelation.symbol.kind == .extension {
        symbolOccurrence = index.occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy).first
      } else {
        symbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
      }
      if let symbolOccurrence {
        components.insert(symbolOccurrence.symbol.name, at: 0)
      }
    }
    return DocCSymbolLinkImpl(string: module)?.appending(components: components)
  }

  /// Find a `SymbolOccurrence` that is considered the primary definition of the symbol with the given `DocCSymbolLink`.
  ///
  /// If the `DocCSymbolLink` has an ambiguous definition, the most important role of this function is to deterministically return
  /// the same result every time.
  package func primaryDefinitionOrDeclarationOccurrence(
    ofDocCSymbolLink symbolLink: any DocCSymbolLink,
    in index: CheckedIndex
  ) -> SymbolOccurrence? {
    guard let symbolLink = symbolLink as? DocCSymbolLinkImpl else {
      return nil
    }
    var components = symbolLink.components
    guard components.count > 0 else {
      return nil
    }
    // Do a lookup to find the top level symbol
    let topLevelSymbolName = components.removeLast().name
    var topLevelSymbolOccurrences = [SymbolOccurrence]()
    index.forEachCanonicalSymbolOccurrence(byName: topLevelSymbolName) { symbolOccurrence in
      guard symbolOccurrence.location.moduleName == symbolLink.moduleName else {
        return true
      }
      topLevelSymbolOccurrences.append(symbolOccurrence)
      return true
    }
    guard let topLevelSymbolOccurrence = topLevelSymbolOccurrences.first else {
      return nil
    }
    // Find any child symbols
    var symbolOccurrence: SymbolOccurrence? = topLevelSymbolOccurrence
    while let currentSymbolOccurrence = symbolOccurrence, components.count > 0 {
      let nextComponent = components.removeLast()
      let parentRelation = currentSymbolOccurrence.relations.first {
        $0.roles.contains(.childOf) && $0.symbol.name == nextComponent.name
      }
      guard let parentRelation else {
        break
      }
      if parentRelation.symbol.kind == .extension {
        symbolOccurrence = index.occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy).first
      } else {
        symbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
      }
    }
    guard symbolOccurrence != nil else {
      return nil
    }
    return topLevelSymbolOccurrence
  }

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
    var catalogIndex: DocCCatalogIndexImpl? = nil
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
#else
package final actor DocCDocumentationManagerImpl: DocCDocumentationManager {
  package init() {}

  package func getRenderingSupport() -> (any DocCDocumentationManagerWithRendering)? {
    nil
  }
}
#endif
