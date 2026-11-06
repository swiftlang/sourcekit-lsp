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
import SKUtilities

/// Manages discovered tests and playgrounds.
actor EntryPointManager {
  weak let sourceKitLSPServer: SourceKitLSPServer?

  // Implicitly-unwrapped because initializing it requires capturing `self`.
  private nonisolated(unsafe) var refreshDebouncer: Debouncer<Void>!

  /// The task performing refreshes, if a refresh is in progress.
  private var currentRefreshTask: Task<Void, Never>?

  /// Whether a refresh was requested while `currentRefreshTask` was running.
  private var needsAnotherRefresh = false

  // Collected entry points in the workspaces.
  private(set) var latestWorkspaceTests: [TestItem] = []
  private(set) var latestPlaygrounds: [Playground] = []

  // Callback functions when the list has changed. Non-nil means the client wants that entry point kind.
  var onWorkspaceTestsChanged: (() -> Void)? = nil
  var onWorkspacePlaygroundsChanged: (() -> Void)? = nil

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.refreshDebouncer = nil
    self.refreshDebouncer = Debouncer(debounceDuration: .seconds(2)) { [weak self] in
      await self?.refreshImpl()
    }
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

  /// Schedules a new refresh of the cached entry point lists.
  ///
  /// - Parameters:
  ///   - debounce: If `true`, the refresh is debounced to coalesce rapid successive refresh requests,
  ///     such as when multiple index changes arrive in quick succession. If `false` (default), the
  ///     refresh starts immediately.
  func refresh(debounce: Bool = false) {
    guard onWorkspaceTestsChanged != nil || onWorkspacePlaygroundsChanged != nil else {
      // If there's no listener, no need to scan things.
      return
    }

    Task {
      await refreshDebouncer.scheduleCall()
      if !debounce {
        await refreshDebouncer.flush()
      }
    }
  }

  private func refreshImpl() {
    guard currentRefreshTask == nil else {
      // The in-progress refresh might miss the latest changes. Refresh again once it finishes instead of cancelling it,
      // so that refreshes don't run concurrently and a steady stream of changes can't keep every refresh from finishing.
      needsAnotherRefresh = true
      return
    }
    currentRefreshTask = Task { [weak self] in
      await self?.runRefreshes()
    }
  }

  private func runRefreshes() async {
    repeat {
      needsAnotherRefresh = false
      async let testsTask: Void = self.refreshTestsImpl()
      async let playgroundsTask: Void = self.refreshPlaygroundsImpl()
      _ = await (testsTask, playgroundsTask)
    } while needsAnotherRefresh
    currentRefreshTask = nil
  }

  private func refreshTestsImpl() async {
    guard let onWorkspaceTestsChanged, let sourceKitLSPServer else {
      // 'onWorkspaceTestsChanged == nil' means the client is not interested in 'workspace/tests/refresh' request.
      return
    }
    let newTests = await TestDiscovery(sourceKitLSPServer: sourceKitLSPServer).workspaceTests()
    // Never modify the result here. modify 'workspaceTests()' if needed so other clients can gent the same result.
    if newTests != latestWorkspaceTests {
      self.latestWorkspaceTests = newTests
      onWorkspaceTestsChanged()
    }
  }

  private func refreshPlaygroundsImpl() async {
    guard let onWorkspacePlaygroundsChanged, let sourceKitLSPServer else {
      return
    }
    let newPlaygrounds = await PlaygroundDiscovery(sourceKitLSPServer: sourceKitLSPServer).workspacePlaygrounds()
    // Never modify the result here. modify 'workspacePlaygrounds()' if needed so other clients can get the same results.
    if newPlaygrounds != latestPlaygrounds {
      self.latestPlaygrounds = newPlaygrounds
      onWorkspacePlaygroundsChanged()
    }
  }
}
