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

import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
@preconcurrency @_spi(LinkCompletion) import SwiftDocC
import SwiftExtensions
import SymbolKit

extension CheckedIndex {
  /// Find a `SymbolOccurrence` that is considered the primary definition of the symbol with the given `DocCSymbolLink`.
  ///
  /// If the `DocCSymbolLink` has an ambiguous definition, the most important role of this function is to deterministically return
  /// the same result every time.
  func primaryDefinitionOrDeclarationOccurrence(
    ofDocCSymbolLink symbolLink: DocCSymbolLink,
    fetchSymbolGraph: @Sendable (SymbolLocation) async throws -> String?
  ) async throws -> SymbolOccurrence? {
    guard let topLevelSymbolName = symbolLink.components.last?.name else {
      throw DocCCheckedIndexError.emptyDocCSymbolLink
    }
    // Find all occurrences of the symbol by name alone
    var topLevelSymbolOccurrences: [SymbolOccurrence] = []
    try forEachCanonicalSymbolOccurrence(byName: topLevelSymbolName) { symbolOccurrence in
      topLevelSymbolOccurrences.append(symbolOccurrence)
      return true  // continue
    }
    // Determine which of the symbol occurrences actually matches the symbol link
    var result: [SymbolOccurrence] = []
    for occurrence in topLevelSymbolOccurrences {
      let info = try await doccSymbolInformation(ofUSR: occurrence.symbol.usr, fetchSymbolGraph: fetchSymbolGraph)
      if info.matches(symbolLink) {
        result.append(occurrence)
      }
    }
    // Ensure that this is deterministic by sorting the results
    result.sort()
    if result.count > 1 {
      logger.debug("Multiple symbols found for DocC symbol link '\(symbolLink.linkString)'")
    }
    return result.first
  }

  /// Find the DocCSymbolLink for a given symbol USR.
  ///
  /// - Parameters:
  ///   - usr: The symbol USR to find in the index.
  ///   - fetchSymbolGraph: Callback that returns a SymbolGraph for a given SymbolLocation
  func doccSymbolInformation(
    ofUSR usr: String,
    fetchSymbolGraph: (SymbolLocation) async throws -> String?
  ) async throws -> DocCSymbolInformation {
    guard let topLevelSymbolOccurrence = try primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
      throw DocCCheckedIndexError.emptyDocCSymbolLink
    }
    let moduleName = topLevelSymbolOccurrence.location.moduleName
    var symbols = [topLevelSymbolOccurrence]
    // Find any parent symbols
    var symbolOccurrence: SymbolOccurrence = topLevelSymbolOccurrence
    while let parentSymbolOccurrence = try symbolOccurrence.parent(self) {
      symbols.insert(parentSymbolOccurrence, at: 0)
      symbolOccurrence = parentSymbolOccurrence
    }
    // Fetch symbol information from the symbol graph
    var components = [DocCSymbolInformation.Component(fromModuleName: moduleName)]
    for symbolOccurence in symbols {
      guard let rawSymbolGraph = try await fetchSymbolGraph(symbolOccurence.location) else {
        throw DocCCheckedIndexError.noSymbolGraph(symbolOccurence.symbol.usr)
      }
      let symbolGraph = try JSONDecoder().decode(SymbolGraph.self, from: Data(rawSymbolGraph.utf8))
      guard let symbol = symbolGraph.symbols[symbolOccurence.symbol.usr] else {
        throw DocCCheckedIndexError.symbolNotFound(symbolOccurence.symbol.usr)
      }
      components.append(DocCSymbolInformation.Component(fromSymbol: symbol))
    }
    return DocCSymbolInformation(components: components)
  }
}

enum DocCCheckedIndexError: LocalizedError {
  case emptyDocCSymbolLink
  case noSymbolGraph(String)
  case symbolNotFound(String)

  var errorDescription: String? {
    switch self {
    case .emptyDocCSymbolLink:
      "The provided DocCSymbolLink was empty and could not be resolved"
    case .noSymbolGraph(let usr):
      "Unable to locate symbol graph for \(usr)"
    case .symbolNotFound(let usr):
      "Symbol \(usr) was not found in its symbol graph"
    }
  }
}

extension SymbolOccurrence {
  func parent(_ index: CheckedIndex) throws -> SymbolOccurrence? {
    let allParentRelations =
      relations
      .filter { $0.roles.contains(.childOf) }
      .sorted()
    if allParentRelations.count > 1 {
      logger.debug("Symbol \(symbol.usr) has multiple parent symbols")
    }
    guard let parentRelation = allParentRelations.first else {
      return nil
    }
    if parentRelation.symbol.kind == .extension {
      let allSymbolOccurrences = try index.occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy)
        .sorted()
      if allSymbolOccurrences.count > 1 {
        logger.debug("Extension \(parentRelation.symbol.usr) extends multiple symbols")
      }
      return allSymbolOccurrences.first
    }
    return try index.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
  }
}
