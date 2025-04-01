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

package import IndexStoreDB
import SKLogging
import SemanticIndex
@_spi(LinkCompletion) import SwiftDocC

extension CheckedIndex {
  /// Find a `SymbolOccurrence` that is considered the primary definition of the symbol with the given `DocCSymbolLink`.
  ///
  /// If the `DocCSymbolLink` has an ambiguous definition, the most important role of this function is to deterministically return
  /// the same result every time.
  package func primaryDefinitionOrDeclarationOccurrence(
    ofDocCSymbolLink symbolLink: DocCSymbolLink
  ) -> SymbolOccurrence? {
    var components = symbolLink.components
    guard components.count > 0 else {
      return nil
    }
    // Do a lookup to find the top level symbol
    let topLevelSymbol = components.removeLast()
    var topLevelSymbolOccurrences: [SymbolOccurrence] = []
    forEachCanonicalSymbolOccurrence(byName: topLevelSymbol.name) { symbolOccurrence in
      topLevelSymbolOccurrences.append(symbolOccurrence)
      return true  // continue
    }
    topLevelSymbolOccurrences = topLevelSymbolOccurrences.filter {
      let symbolInformation = LinkCompletionTools.SymbolInformation(fromSymbolOccurrence: $0)
      return symbolInformation.matches(topLevelSymbol.disambiguation)
    }
    // Search each potential symbol's parents to find an exact match
    let symbolOccurences = topLevelSymbolOccurrences.filter { topLevelSymbolOccurrence in
      var components = components
      var symbolOccurrence = topLevelSymbolOccurrence
      while let parentSymbolOccurrence = symbolOccurrence.parent(self), !components.isEmpty {
        let nextComponent = components.removeLast()
        let parentSymbolInformation = LinkCompletionTools.SymbolInformation(
          fromSymbolOccurrence: parentSymbolOccurrence
        )
        guard parentSymbolOccurrence.symbol.name == nextComponent.name,
          parentSymbolInformation.matches(nextComponent.disambiguation)
        else {
          return false
        }
        symbolOccurrence = parentSymbolOccurrence
      }
      // If we have exactly one component left, check to see if it's the module name
      if components.count == 1 {
        let lastComponent = components.removeLast()
        guard lastComponent.name == topLevelSymbolOccurrence.location.moduleName else {
          return false
        }
      }
      guard components.isEmpty else {
        return false
      }
      return true
    }.sorted()
    if symbolOccurences.count > 1 {
      logger.debug("Multiple symbols found for DocC symbol link '\(symbolLink.linkString)'")
    }
    return symbolOccurences.first
  }
}

extension SymbolOccurrence {
  func parent(_ index: CheckedIndex) -> SymbolOccurrence? {
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
      let allSymbolOccurrences = index.occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy)
        .sorted()
      if allSymbolOccurrences.count > 1 {
        logger.debug("Extension \(parentRelation.symbol.usr) extends multiple symbols")
      }
      return allSymbolOccurrences.first
    }
    return index.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
  }
}
