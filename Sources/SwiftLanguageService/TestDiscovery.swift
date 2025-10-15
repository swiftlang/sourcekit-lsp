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
  package func syntacticDocumentTests(
    for uri: DocumentURI,
    in workspace: Workspace
  ) async throws -> [AnnotatedTestItem]? {
    let targetIdentifiers = await workspace.buildServerManager.targets(for: uri)
    let isInTestTarget = await targetIdentifiers.asyncContains(where: {
      await workspace.buildServerManager.buildTarget(named: $0)?.tags.contains(.test) ?? true
    })
    if !targetIdentifiers.isEmpty && !isInTestTarget {
      // If we know the targets for the file and the file is not part of any test target, don't scan it for tests.
      return nil
    }
    let snapshot = try documentManager.latestSnapshot(uri)
    let semanticSymbols = await workspace.index(checkedFor: .deletedFiles)?.symbols(inFilePath: snapshot.uri.pseudoPath)
    let xctestSymbols = await SyntacticSwiftXCTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    .compactMap { $0.filterUsing(semanticSymbols: semanticSymbols) }

    let swiftTestingSymbols = await SyntacticSwiftTestingTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    return (xctestSymbols + swiftTestingSymbols).sorted { $0.testItem.location < $1.testItem.location }
  }

  package static func syntacticTestItems(in uri: DocumentURI) async -> [AnnotatedTestItem] {
    guard let url = uri.fileURL else {
      logger.log("Not indexing \(uri.forLogging) for tests because it is not a file URL")
      return []
    }
    let syntaxTreeManager = SyntaxTreeManager()
    let snapshot = orLog("Getting document snapshot for syntactic Swift test scanning") {
      try DocumentSnapshot(withContentsFromDisk: url, language: .swift)
    }
    guard let snapshot else {
      return []
    }
    async let swiftTestingTests = SyntacticSwiftTestingTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    async let xcTests = SyntacticSwiftXCTestScanner.findTestSymbols(in: snapshot, syntaxTreeManager: syntaxTreeManager)

    return await swiftTestingTests + xcTests
  }
}
