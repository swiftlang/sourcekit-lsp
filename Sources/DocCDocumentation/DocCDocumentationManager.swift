import BuildServerProtocol
package import BuildSystemIntegration
package import Foundation
package import IndexStoreDB
package import LanguageServerProtocol
import SKLogging
package import SemanticIndex
import SwiftDocC

package struct DocCDocumentationManager: Sendable {
  private let doccServer: DocCServer
  private let referenceResolutionService: DocCReferenceResolutionService
  private let catalogIndexManager: DocCCatalogIndexManager

  private let buildSystemManager: BuildSystemManager

  package init(buildSystemManager: BuildSystemManager) {
    let symbolResolutionServer = DocumentationServer(qualityOfService: .unspecified)
    doccServer = DocCServer(
      peer: symbolResolutionServer,
      qualityOfService: .default
    )
    catalogIndexManager = DocCCatalogIndexManager(server: doccServer)
    referenceResolutionService = DocCReferenceResolutionService()
    symbolResolutionServer.register(service: referenceResolutionService)
    self.buildSystemManager = buildSystemManager
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    for event in events {
      guard let target = await buildSystemManager.canonicalTarget(for: event.uri),
        let catalogURL = await buildSystemManager.doccCatalog(for: target)
      else {
        continue
      }
      await catalogIndexManager.invalidate(catalogURL)
    }
  }

  package func catalogIndex(for catalogURL: URL) async throws(DocCIndexError) -> DocCCatalogIndex {
    try await catalogIndexManager.index(for: catalogURL)
  }

  package func symbolLink(string: String) -> DocCSymbolLink? {
    DocCSymbolLink(string: string)
  }

  private func parentSymbol(of symbol: SymbolOccurrence, in index: CheckedIndex) -> SymbolOccurrence? {
    let allParentRelations = symbol.relations
      .filter { $0.roles.contains(.childOf) }
      .sorted()
    if allParentRelations.count > 1 {
      logger.debug("Symbol \(symbol.symbol.usr) has multiple parent symbols")
    }
    guard let parentRelation = allParentRelations.first else {
      return nil
    }
    if parentRelation.symbol.kind == .extension {
      let allSymbolOccurrences = index.occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy)
        .sorted()
      if allSymbolOccurrences.count > 1 {
        logger.debug("Extension \(parentRelation.symbol.usr) extends multiple symbols")
      }
      return allSymbolOccurrences.first
    }
    return index.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
  }

  package func symbolLink(forUSR usr: String, in index: CheckedIndex) -> DocCSymbolLink? {
    guard let topLevelSymbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
      return nil
    }
    let module = topLevelSymbolOccurrence.location.moduleName
    var components = [topLevelSymbolOccurrence.symbol.name]
    // Find any parent symbols
    var symbolOccurrence: SymbolOccurrence = topLevelSymbolOccurrence
    while let parentSymbolOccurrence = parentSymbol(of: symbolOccurrence, in: index) {
      components.insert(parentSymbolOccurrence.symbol.name, at: 0)
      symbolOccurrence = parentSymbolOccurrence
    }
    return DocCSymbolLink(string: module)?.appending(components: components)
  }

  /// Find a `SymbolOccurrence` that is considered the primary definition of the symbol with the given `DocCSymbolLink`.
  ///
  /// If the `DocCSymbolLink` has an ambiguous definition, the most important role of this function is to deterministically return
  /// the same result every time.
  package func primaryDefinitionOrDeclarationOccurrence(
    ofDocCSymbolLink symbolLink: DocCSymbolLink,
    in index: CheckedIndex
  ) -> SymbolOccurrence? {
    var components = symbolLink.components
    guard components.count > 0 else {
      return nil
    }
    // Do a lookup to find the top level symbol
    let topLevelSymbolName = components.removeLast().name
    var topLevelSymbolOccurrences: [SymbolOccurrence] = []
    index.forEachCanonicalSymbolOccurrence(byName: topLevelSymbolName) { symbolOccurrence in
      guard symbolOccurrence.location.moduleName == symbolLink.moduleName else {
        return true  // continue
      }
      topLevelSymbolOccurrences.append(symbolOccurrence)
      return true  // continue
    }
    // Search each potential symbol's parents to find an exact match
    let symbolOccurences = topLevelSymbolOccurrences.filter { topLevelSymbolOccurrence in
      var components = components
      var symbolOccurrence = topLevelSymbolOccurrence
      while let parentSymbolOccurrence = parentSymbol(of: symbolOccurrence, in: index), !components.isEmpty {
        let nextComponent = components.removeLast()
        guard parentSymbolOccurrence.symbol.name == nextComponent.name else {
          return false
        }
        symbolOccurrence = parentSymbolOccurrence
      }
      guard components.isEmpty else {
        return false
      }
      return true
    }.sorted()
    if symbolOccurences.count > 1 {
      logger.debug("Multiple symbols found for DocC symbol link '\(symbolLink.absoluteString)'")
    }
    return symbolOccurences.first
  }

  /// Generates the SwiftDocC RenderNode for a given symbol, tutorial, or markdown file.
  ///
  /// - Parameters:
  ///   - symbolUSR: The USR of the symbol to render
  ///   - symbolGraph: The symbol graph that includes the given symbol USR
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
    var overridingDocumentationComments = [String: [String]]()
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
