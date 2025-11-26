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
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

extension SourceKitLSPServer {

  /// Return all the playgrounds in the given workspace.
  ///
  /// The returned list of playgrounds is not sorted. It should be sorted before being returned to the editor.
  private func playgrounds(in workspace: Workspace) async -> [Playground] {
    // If files have recently been added to the workspace (which is communicated by a `workspace/didChangeWatchedFiles`
    // notification, wait these changes to be reflected in the build server so we can include the updated files in the
    // playgrounds.
    await workspace.buildServerManager.waitForUpToDateBuildGraph()

    let playgroundsFromSyntacticIndex = await languageServices.values.asyncFlatMap {
      await $0.asyncFlatMap { await $0.syntacticPlaygrounds(in: workspace) }
    }

    // We don't need to sort the playgrounds here because they will get sorted by `workspacePlaygrounds` request handler
    return playgroundsFromSyntacticIndex
  }

  func workspacePlaygrounds(_ req: WorkspacePlaygroundsRequest) async throws -> [Playground] {
    return await self.workspaces
      .concurrentMap { await self.playgrounds(in: $0) }
      .flatMap { $0 }
      .sorted { $0.location < $1.location }
  }
}
