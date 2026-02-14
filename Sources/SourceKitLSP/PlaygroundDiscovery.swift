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

struct PlaygroundDiscovery {
  let sourceKitLSPServer: SourceKitLSPServer

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
  }

  private func playgrounds(in workspace: Workspace) async -> [Playground] {
    let playgroundsFromSyntacticIndex = await workspace.syntacticIndex.playgrounds()

    // We don't need to sort the playgrounds here because they will get sorted by `workspacePlaygrounds`
    return playgroundsFromSyntacticIndex
  }

  func workspacePlaygrounds() async -> [Playground] {
    return await sourceKitLSPServer.workspaces
      .concurrentMap { await self.playgrounds(in: $0) }
      .flatMap { $0 }
      .sorted { $0.location < $1.location }
  }
}
