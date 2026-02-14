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
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
package import SourceKitLSP
import SwiftExtensions

extension SwiftLanguageService {
  /// Syntactically scans the snapshot for tests declared within it.
  ///
  /// Does not write the results to the index.
  ///
  /// The order of the returned tests is not defined. The results should be sorted before being returned to the editor.
  package func syntacticTestItems(
    for snapshot: DocumentSnapshot,
  ) async -> [AnnotatedTestItem]? {
    // Don't use the `self.syntaxTreeManager` for snapshots with version number 0
    // which indicates it's loaded from the disk.
    let syntaxTreeManager = snapshot.version != 0 ? self.syntaxTreeManager : SyntaxTreeManager()
    async let swiftTestingTests = SyntacticSwiftTestingTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    async let xcTests = SyntacticSwiftXCTestScanner.findTestSymbols(in: snapshot, syntaxTreeManager: syntaxTreeManager)

    return await swiftTestingTests + xcTests
  }
}
