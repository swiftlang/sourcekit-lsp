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

import Foundation
import IndexStoreDB
package import SemanticIndex
@_spi(LinkCompletion) @preconcurrency import SwiftDocC
import SymbolKit

package struct DocCSymbolInformation {
  let components: [(name: String, information: LinkCompletionTools.SymbolInformation)]

  /// Find the DocCSymbolLink for a given symbol USR.
  ///
  /// - Parameters:
  ///   - usr: The symbol USR to find in the index.
  ///   - index: The CheckedIndex to search within.
  package init?(fromUSR usr: String, in index: CheckedIndex) {
    guard let topLevelSymbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
      return nil
    }
    let moduleName = topLevelSymbolOccurrence.location.moduleName
    var components = [topLevelSymbolOccurrence]
    // Find any parent symbols
    var symbolOccurrence: SymbolOccurrence = topLevelSymbolOccurrence
    while let parentSymbolOccurrence = symbolOccurrence.parent(index) {
      components.insert(parentSymbolOccurrence, at: 0)
      symbolOccurrence = parentSymbolOccurrence
    }
    self.components =
      [(name: moduleName, LinkCompletionTools.SymbolInformation(fromModuleName: moduleName))]
      + components.map {
        (name: $0.symbol.name, information: LinkCompletionTools.SymbolInformation(fromSymbolOccurrence: $0))
      }
  }

  package func matches(_ link: DocCSymbolLink) -> Bool {
    var linkComponents = link.components
    var symbolComponents = components
    while !linkComponents.isEmpty, !symbolComponents.isEmpty {
      let nextLinkComponent = linkComponents.removeLast()
      let nextSymbolComponent = symbolComponents.removeLast()
      guard nextLinkComponent.name == nextSymbolComponent.name,
        nextSymbolComponent.information.matches(nextLinkComponent.disambiguation)
      else {
        return false
      }
    }
    return true
  }
}

fileprivate typealias KindIdentifier = SymbolGraph.Symbol.KindIdentifier

extension SymbolOccurrence {
  var doccSymbolKind: String {
    switch symbol.kind {
    case .module:
      KindIdentifier.module.identifier
    case .namespace, .namespaceAlias:
      KindIdentifier.namespace.identifier
    case .macro:
      KindIdentifier.macro.identifier
    case .enum:
      KindIdentifier.enum.identifier
    case .struct:
      KindIdentifier.struct.identifier
    case .class:
      KindIdentifier.class.identifier
    case .protocol:
      KindIdentifier.protocol.identifier
    case .extension:
      KindIdentifier.extension.identifier
    case .union:
      KindIdentifier.union.identifier
    case .typealias:
      KindIdentifier.typealias.identifier
    case .function:
      KindIdentifier.func.identifier
    case .variable:
      KindIdentifier.var.identifier
    case .field:
      KindIdentifier.property.identifier
    case .enumConstant:
      KindIdentifier.case.identifier
    case .instanceMethod:
      KindIdentifier.func.identifier
    case .classMethod:
      KindIdentifier.func.identifier
    case .staticMethod:
      KindIdentifier.func.identifier
    case .instanceProperty:
      KindIdentifier.property.identifier
    case .classProperty, .staticProperty:
      KindIdentifier.typeProperty.identifier
    case .constructor:
      KindIdentifier.`init`.identifier
    case .destructor:
      KindIdentifier.deinit.identifier
    case .conversionFunction:
      KindIdentifier.func.identifier
    case .unknown, .using, .concept, .commentTag, .parameter:
      "unknown"
    }
  }
}

extension LinkCompletionTools.SymbolInformation {
  init(fromModuleName moduleName: String) {
    self.init(
      kind: KindIdentifier.module.identifier,
      symbolIDHash: Self.hash(uniqueSymbolID: moduleName)
    )
  }

  init(fromSymbolOccurrence occurrence: SymbolOccurrence) {
    self.init(
      kind: occurrence.doccSymbolKind,
      symbolIDHash: Self.hash(uniqueSymbolID: occurrence.symbol.usr),
      parameterTypes: nil,
      returnTypes: nil
    )
  }
}
