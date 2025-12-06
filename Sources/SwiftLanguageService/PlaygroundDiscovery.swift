//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
package import SourceKitLSP
import SwiftExtensions

extension SwiftLanguageService {
  package func syntacticPlaygrounds(
    for snapshot: DocumentSnapshot,
    in workspace: Workspace
  ) async -> [TextDocumentPlayground] {
    // Don't use the `syntaxTreeManager` instance variable in `SwiftLanguageService` in `DocumentSnapshot`
    // loaded from the disk will always have version number 0
    let syntaxTreeManager = SyntaxTreeManager()
    return await SwiftPlaygroundsScanner.findDocumentPlaygrounds(
      for: snapshot,
      workspace: workspace,
      syntaxTreeManager: syntaxTreeManager
    )
  }
}
