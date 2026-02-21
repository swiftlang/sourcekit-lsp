//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

internal import BuildServerIntegration
import Foundation
import IndexStoreDB
import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Manages discovered tests and playgrounds.
actor EntryPointManager {
  weak let sourceKitLSPServer: SourceKitLSPServer?
  private var currentRefreshTask: Task<Void, any Error>?

  var onWorkspaceTestsChanged: (() -> Void)?
  var onWorkspacePlaygroundsChanged: (() -> Void)?

  // Collected entry points in the workspaces.
  private(set) var latestWorkspaceTests: [TestItem] = []
  private(set) var playgrounds: [Playground] = []

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
  }

  /// Setup the callbacks for each entry point kind.
  /// If `nil`, the entry point of the kind will not be monitored.
  func setCallbacks(
    onWorkspaceTestsChanged: (() -> Void)?,
    onWorkspacePlaygroundsChanged: (() -> Void)?,
  ) {
    self.onWorkspaceTestsChanged = onWorkspaceTestsChanged
    self.onWorkspacePlaygroundsChanged = onWorkspacePlaygroundsChanged
  }

  /// Start refreshing cached entry point lists job.
  func refresh() {
    guard onWorkspaceTestsChanged != nil || onWorkspacePlaygroundsChanged != nil else {
      // If there's no listener, no need to scan things.
      return
    }

    self.currentRefreshTask?.cancel()

    self.currentRefreshTask = Task { [weak self] in
      guard let self else {
        return
      }
      try Task.checkCancellation()

      async let testsTask = self.refreshTestsImpl()
      async let playgroundsTask = self.refreshPlaygroundsImpl()
      _ = await (testsTask, playgroundsTask)

      // We don't need to clear 'self.currentTask'.
    }
  }

  private func refreshTestsImpl() async {
    guard let onWorkspaceTestsChanged, let sourceKitLSPServer else {
      // 'onWorkspaceTestsChanged == nil' means the client is not interested in 'workspace/tests/refresh' request.
      return
    }
    let newTests = await TestDiscovery(sourceKitLSPServer: sourceKitLSPServer).workspaceTests()
    if let newTests, newTests != latestWorkspaceTests {
      latestWorkspaceTests = newTests
      onWorkspaceTestsChanged()
    }
  }

  private func refreshPlaygroundsImpl() async {
    guard let onWorkspacePlaygroundsChanged, let sourceKitLSPServer else {
      return
    }
    let newPlaygrounds = await PlaygroundDiscovery(sourceKitLSPServer: sourceKitLSPServer).workspacePlaygrounds()
    if let newPlaygrounds, newPlaygrounds != playgrounds {
      playgrounds = newPlaygrounds
      onWorkspacePlaygroundsChanged()
    }
  }
}
