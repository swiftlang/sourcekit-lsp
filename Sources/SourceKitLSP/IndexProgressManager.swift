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

import LanguageServerProtocol
import SKSupport
import SemanticIndex

/// Listens for index status updates from `SemanticIndexManagers`. From that information, it manages a
/// `WorkDoneProgress` that communicates the index progress to the editor.
actor IndexProgressManager {
  /// A queue on which `indexTaskWasQueued` and `indexStatusDidChange` are handled.
  ///
  /// This allows the two functions two be `nonisolated` (and eg. the caller of `indexStatusDidChange` doesn't have to
  /// wait for the work done progress to be updated) while still guaranteeing that we handle them in the order they
  /// were called.
  private let queue = AsyncQueue<Serial>()

  /// The `SourceKitLSPServer` for which this manages the index progress. It gathers all `SemanticIndexManagers` from
  /// the workspaces in the `SourceKitLSPServer`.
  private weak var sourceKitLSPServer: SourceKitLSPServer?

  /// This is the target number of index tasks (eg. the `3` in `1/3 done`).
  ///
  /// Every time a new index task is scheduled, this number gets incremented, so that it only ever increases.
  /// When indexing of one session is done (ie. when there are no more `scheduled` or `executing` tasks in any
  /// `SemanticIndexManager`), `queuedIndexTasks` gets reset to 0 and the work done progress gets ended.
  /// This way, when the next work done progress is started, it starts at zero again.
  ///
  /// The number of outstanding tasks is determined from the `scheduled` and `executing` tasks in all the
  /// `SemanticIndexManager`s.
  private var queuedIndexTasks = 0

  /// While there are ongoing index tasks, a `WorkDoneProgressManager` that displays the work done progress.
  private var workDoneProgress: WorkDoneProgressManager?

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
  }

  /// Called when a new file is scheduled to be indexed. Increments the target index count, eg. the 3 in `1/3`.
  nonisolated func indexTaskWasQueued(count: Int) {
    queue.async {
      await self.indexTaskWasQueuedImpl(count: count)
    }
  }

  private func indexTaskWasQueuedImpl(count: Int) async {
    queuedIndexTasks += count
    await indexStatusDidChangeImpl()
  }

  /// Called when a `SemanticIndexManager` finishes indexing a file. Adjusts the done index count, eg. the 1 in `1/3`.
  nonisolated func indexStatusDidChange() {
    queue.async {
      await self.indexStatusDidChangeImpl()
    }
  }

  private func indexStatusDidChangeImpl() async {
    guard let sourceKitLSPServer else {
      workDoneProgress = nil
      return
    }
    var scheduled: [DocumentURI] = []
    var executing: [DocumentURI] = []
    for indexManager in await sourceKitLSPServer.workspaces.compactMap({ $0.semanticIndexManager }) {
      let inProgress = await indexManager.inProgressIndexTasks
      scheduled += inProgress.scheduled
      executing += inProgress.executing
    }

    if scheduled.isEmpty && executing.isEmpty {
      // Nothing left to index. Reset the target count and dismiss the work done progress.
      queuedIndexTasks = 0
      workDoneProgress = nil
      return
    }

    let finishedTasks = queuedIndexTasks - scheduled.count - executing.count
    let message = "\(finishedTasks) / \(queuedIndexTasks)"

    let percentage = Int(Double(finishedTasks) / Double(queuedIndexTasks) * 100)
    if let workDoneProgress {
      workDoneProgress.update(message: message, percentage: percentage)
    } else {
      workDoneProgress = await WorkDoneProgressManager(
        server: sourceKitLSPServer,
        title: "Indexing",
        message: message,
        percentage: percentage
      )
    }
  }
}
