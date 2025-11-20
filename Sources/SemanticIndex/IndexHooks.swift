//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation
package import IndexStoreDB

/// When running SourceKit-LSP in-process, allows the creator of `SourceKitLSPServer` to provide the `IndexStoreDB`
/// instead of SourceKit-LSP creating the instance when needed.
package protocol IndexInjector: Sendable {
  func createIndex(
    storePath: URL,
    databasePath: URL,
    indexStoreLibraryPath: URL,
    delegate: any IndexDelegate,
    prefixMappings: [PathMapping]
  ) async throws -> IndexStoreDB

  /// Whether the injected index uses explicit output paths and whether SourceKit-LSP should thus set the unit output
  /// paths on the index as they change.
  var usesExplicitOutputPaths: Bool { get async }
}

/// Callbacks that allow inspection of internal state modifications during testing.
package struct IndexHooks: Sendable {
  package var indexInjector: (any IndexInjector)?

  package var buildGraphGenerationDidStart: (@Sendable () async -> Void)?

  package var buildGraphGenerationDidFinish: (@Sendable () async -> Void)?

  package var preparationTaskDidStart: (@Sendable (PreparationTaskDescription) async -> Void)?

  package var preparationTaskDidFinish: (@Sendable (PreparationTaskDescription) async -> Void)?

  package var updateIndexStoreTaskDidStart: (@Sendable (UpdateIndexStoreTaskDescription) async -> Void)?

  /// A callback that is called when an index task finishes.
  package var updateIndexStoreTaskDidFinish: (@Sendable (UpdateIndexStoreTaskDescription) async -> Void)?

  package init(
    indexInjector: (any IndexInjector)? = nil,
    buildGraphGenerationDidStart: (@Sendable () async -> Void)? = nil,
    buildGraphGenerationDidFinish: (@Sendable () async -> Void)? = nil,
    preparationTaskDidStart: (@Sendable (PreparationTaskDescription) async -> Void)? = nil,
    preparationTaskDidFinish: (@Sendable (PreparationTaskDescription) async -> Void)? = nil,
    updateIndexStoreTaskDidStart: (@Sendable (UpdateIndexStoreTaskDescription) async -> Void)? = nil,
    updateIndexStoreTaskDidFinish: (@Sendable (UpdateIndexStoreTaskDescription) async -> Void)? = nil
  ) {
    self.indexInjector = indexInjector
    self.buildGraphGenerationDidStart = buildGraphGenerationDidStart
    self.buildGraphGenerationDidFinish = buildGraphGenerationDidFinish
    self.preparationTaskDidStart = preparationTaskDidStart
    self.preparationTaskDidFinish = preparationTaskDidFinish
    self.updateIndexStoreTaskDidStart = updateIndexStoreTaskDidStart
    self.updateIndexStoreTaskDidFinish = updateIndexStoreTaskDidFinish
  }
}
