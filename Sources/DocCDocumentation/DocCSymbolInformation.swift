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
@_spi(LinkCompletion) @preconcurrency import SwiftDocC
import SwiftExtensions
import SymbolKit

package struct DocCSymbolInformation {
  struct Component {
    let name: String
    let information: LinkCompletionTools.SymbolInformation

    init(fromModuleName moduleName: String) {
      self.name = moduleName
      self.information = LinkCompletionTools.SymbolInformation(fromModuleName: moduleName)
    }

    init(fromSymbol symbol: SymbolGraph.Symbol) {
      self.name = symbol.pathComponents.last ?? symbol.names.title
      self.information = LinkCompletionTools.SymbolInformation(symbol: symbol)
    }
  }

  let components: [Component]

  init(components: [Component]) {
    self.components = components
  }

  package func matches(_ link: DocCSymbolLink) -> Bool {
    guard link.components.count == components.count else {
      return false
    }
    return zip(link.components, components).allSatisfy { linkComponent, symbolComponent in
      linkComponent.name == symbolComponent.name && symbolComponent.information.matches(linkComponent.disambiguation)
    }
  }
}

fileprivate typealias KindIdentifier = SymbolGraph.Symbol.KindIdentifier

extension LinkCompletionTools.SymbolInformation {
  init(fromModuleName moduleName: String) {
    self.init(
      kind: KindIdentifier.module.identifier,
      symbolIDHash: Self.hash(uniqueSymbolID: moduleName)
    )
  }
}
