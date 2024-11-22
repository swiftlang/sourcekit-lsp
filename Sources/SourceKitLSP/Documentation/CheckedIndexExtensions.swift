#if canImport(SwiftDocC)
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import SemanticIndex
@preconcurrency import SwiftDocC
import SwiftExtensions

extension CheckedIndex {
  func doccSymbolLink(forUSR usr: String) -> DocCSymbolLink? {
    guard let topLevelSymbolOccurrence = primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
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
        symbolOccurrence = occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy).first
      } else {
        symbolOccurrence = primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
      }
      if let symbolOccurrence {
        components.insert(symbolOccurrence.symbol.name, at: 0)
      }
    }
    return DocCSymbolLink(string: module)?.appending(components: components)
  }

  /// Find a `SymbolOccurrence` that is considered the primary definition of the symbol with the given `DocCSymbolLink`.
  ///
  /// If the `DocCSymbolLink` has an ambiguous definition, the most important role of this function is to deterministically return
  /// the same result every time.
  func primaryDefinitionOrDeclarationOccurrence(
    ofDocCSymbolLink symbolLink: DocCSymbolLink
  ) -> SymbolOccurrence? {
    var components = symbolLink.components
    guard components.count > 0 else {
      return nil
    }
    // Do a lookup to find the top level symbol
    let topLevelSymbolName = components.removeLast().name
    var topLevelSymbolOccurrences = [SymbolOccurrence]()
    forEachCanonicalSymbolOccurrence(byName: topLevelSymbolName) { symbolOccurrence in
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
        symbolOccurrence = occurrences(relatedToUSR: parentRelation.symbol.usr, roles: .extendedBy).first
      } else {
        symbolOccurrence = primaryDefinitionOrDeclarationOccurrence(ofUSR: parentRelation.symbol.usr)
      }
    }
    guard symbolOccurrence != nil else {
      return nil
    }
    return topLevelSymbolOccurrence
  }
}
#endif
