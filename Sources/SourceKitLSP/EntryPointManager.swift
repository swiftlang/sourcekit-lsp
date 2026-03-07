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

import LanguageServerProtocol

/// Manages discovered tests and playgrounds.
actor EntryPointManager {
  weak let sourceKitLSPServer: SourceKitLSPServer?
  private var currentRefreshTask: Task<Void, any Error>?

  // Collected entry points in the workspaces.
  private(set) var latestWorkspaceTests: [TestItem] = []
  private(set) var latestPlaygrounds: [Playground] = []

  // Callback functions when the list has changed. Non-nil means the client wants that entry point kind.
  var onWorkspaceTestsChanged: (() -> Void)? = nil
  var onWorkspacePlaygroundsChanged: (() -> Void)? = nil

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
  }

  /// Sets up the callbacks for each entry point kind.
  /// If `nil`, the entry point of the kind will not be monitored.
  func setCallbacks(
    onWorkspaceTestsChanged: (() -> Void)?,
    onWorkspacePlaygroundsChanged: (() -> Void)?,
  ) {
    self.onWorkspaceTestsChanged = onWorkspaceTestsChanged
    self.onWorkspacePlaygroundsChanged = onWorkspacePlaygroundsChanged
  }

  /// Cancels any in-progress refresh and schedules a new refresh of the cached entry point lists.
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

      // No need to clear 'self.currentRefreshTask'; the next call to `refresh()` will cancel and replace it.
    }
  }

  private func refreshTestsImpl() async {
    guard let onWorkspaceTestsChanged, let sourceKitLSPServer else {
      // 'onWorkspaceTestsChanged == nil' means the client is not interested in 'workspace/tests/refresh' request.
      return
    }
    let newTests = await TestDiscovery(sourceKitLSPServer: sourceKitLSPServer).workspaceTests()
    if !Task.isCancelled, newTests != latestWorkspaceTests {
      self.latestWorkspaceTests = newTests
      onWorkspaceTestsChanged()
    }
  }

  private func refreshPlaygroundsImpl() async {
    guard let onWorkspacePlaygroundsChanged, let sourceKitLSPServer else {
      return
    }
    let newPlaygrounds = await PlaygroundDiscovery(sourceKitLSPServer: sourceKitLSPServer).workspacePlaygrounds()
    if !Task.isCancelled, newPlaygrounds != latestPlaygrounds {
      self.latestPlaygrounds = newPlaygrounds
      onWorkspacePlaygroundsChanged()
    }
  }
}
