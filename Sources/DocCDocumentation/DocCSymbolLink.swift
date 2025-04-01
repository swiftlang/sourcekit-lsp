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
import SemanticIndex
@_spi(LinkCompletion) @preconcurrency import SwiftDocC
import SymbolKit

package struct DocCSymbolLink: Sendable {
  let linkString: String
  let components: [(name: String, disambiguation: LinkCompletionTools.ParsedDisambiguation)]

  var symbolName: String {
    components.last!.name
  }

  package init?(linkString: String) {
    let components = LinkCompletionTools.parse(linkString: linkString)
    guard !components.isEmpty else {
      return nil
    }
    self.linkString = linkString
    self.components = components
  }
}
