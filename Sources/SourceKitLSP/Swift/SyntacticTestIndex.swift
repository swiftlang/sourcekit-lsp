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

import Foundation
import LanguageServerProtocol
import SKLogging
import SKSupport
import SwiftExtensions

/// Task metadata for `SyntacticTestIndexer.indexingQueue`
fileprivate enum TaskMetadata: DependencyTracker, Equatable {
  case read
  case index(Set<DocumentURI>)

  /// Reads can be concurrent and files can be indexed concurrently. But we need to wait for all files to finish
  /// indexing before reading the index.
  func isDependency(of other: TaskMetadata) -> Bool {
    switch (self, other) {
    case (.read, .read):
      // We allow concurrent reads
      return false
    case (.read, .index(_)):
      // We allow index tasks scheduled after a read task to be be executed before the read.
      // This effectively means that a `read` requires the index to be updated *at least* up to the state at which the
      // read was scheduled. If more changes come in in the meantime, it is OK for the read to pick them up. This also
      // ensures that reads aren't parallelization barriers.
      return false
    case (.index(_), .read):
      // We require all index tasks scheduled before the read to be finished.
      // This ensures that the index has been updated at least to the state of file at which the read was scheduled.
      // Adding the dependency also elevates the index task's priorities.
      return true
    case (.index(let lhsUris), .index(let rhsUris)):
      // Technically, we should be able to allow simultaneous indexing of the same file. But conceptually the code
      // becomes simpler if we don't need to think racing indexing tasks for the same file and it shouldn't make a
      // performance impact in practice because if a first task indexes a file, a subsequent index task for the same
      // file will realize that the index is already up-to-date based on the file's mtime and early exit.
      return !lhsUris.intersection(rhsUris).isEmpty
    }
  }
}

/// Data from a syntactic scan of a source file for tests.
fileprivate struct IndexedTests {
  /// The tests within the source file.
  let tests: [AnnotatedTestItem]

  /// The modification date of the source file when it was scanned. A file won't get re-scanned if its modification date
  /// is older or the same as this date.
  let sourceFileModificationDate: Date
}

/// Syntactically scans the file at the given URL for tests declared within it.
///
/// Does not write the results to the index.
///
/// The order of the returned tests is not defined. The results should be sorted before being returned to the editor.
fileprivate func testItems(in url: URL) async -> [AnnotatedTestItem] {
  guard url.pathExtension == "swift" else {
    return []
  }
  let syntaxTreeManager = SyntaxTreeManager()
  let snapshot = orLog("Getting document snapshot for swift-testing scanning") {
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

/// An in-memory syntactic index of test items within a workspace.
///
/// The index does not get persisted to disk but instead gets rebuilt every time a workspace is opened (ie. usually when
/// sourcekit-lsp is launched). Building it takes only a few seconds, even for large projects.
actor SyntacticTestIndex {
  /// The tests discovered by the index.
  private var indexedTests: [DocumentURI: IndexedTests] = [:]

  /// Files that have been removed using `removeFileForIndex`.
  ///
  /// We need to keep track of these files because when the files get removed, there might be an in-progress indexing
  /// operation running for that file. We need to ensure that this indexing operation doesn't add the removed file
  /// back to `indexTests`.
  private var removedFiles: Set<DocumentURI> = []

  /// The queue on which the index is being updated and queried.
  ///
  /// Tracking dependencies between tasks within this queue allows us to start indexing tasks in parallel with low
  /// priority and elevate their priority once a read task comes in, which has higher priority and depends on the
  /// indexing tasks to finish.
  private let indexingQueue = AsyncQueue<TaskMetadata>()

  init() {}

  private func removeFilesFromIndex(_ removedFiles: Set<DocumentURI>) {
    self.removedFiles.formUnion(removedFiles)
    for removedFile in removedFiles {
      self.indexedTests[removedFile] = nil
    }
  }

  /// Called when the list of files that may contain tests is updated.
  ///
  /// All files that are not in the new list of test files will be removed from the index.
  func listOfTestFilesDidChange(_ testFiles: [DocumentURI]) {
    let removedFiles = Set(self.indexedTests.keys).subtracting(testFiles)
    removeFilesFromIndex(removedFiles)

    rescanFiles(testFiles)
  }

  func filesDidChange(_ events: [FileEvent]) {
    for fileEvent in events {
      switch fileEvent.type {
      case .created:
        // We don't know if this is a potential test file. It would need to be added to the index via
        // `listOfTestFilesDidChange`
        break
      case .changed:
        rescanFiles([fileEvent.uri])
      case .deleted:
        removeFilesFromIndex([fileEvent.uri])
      default:
        logger.error("Ignoring unknown FileEvent type \(fileEvent.type.rawValue) in SyntacticTestIndex")
      }
    }
  }

  /// Called when a list of files was updated. Re-scans those files
  private func rescanFiles(_ uris: [DocumentURI]) {
    logger.info("Syntactically scanning files for tests: \(uris)")

    // If we scan a file again, it might have been added after being removed before. Remove it from the list of removed
    // files.
    removedFiles.subtract(uris)

    // Divide the files into multiple batches. This is more efficient than spawning a new task for every file, mostly
    // because it keeps the number of pending items in `indexingQueue` low and adding a new task to `indexingQueue` is
    // in O(number of pending tasks), since we need to scan for dependency edges to add, which would make scanning files
    // be O(number of files).
    // Over-subscribe the processor count in case one batch finishes more quickly than another.
    let batches = uris.partition(intoNumberOfBatches: ProcessInfo.processInfo.processorCount * 4)
    for batch in batches {
      self.indexingQueue.async(priority: .low, metadata: .index(Set(batch))) {
        for uri in batch {
          await self.rescanFileAssumingOnQueue(uri)
        }
      }
    }
  }

  /// Re-scans a single file.
  ///
  /// - Important: This method must be called in a task that is executing on `indexingQueue`.
  private func rescanFileAssumingOnQueue(_ uri: DocumentURI) async {
    guard let url = uri.fileURL else {
      logger.log("Not indexing \(uri.forLogging) for swift-testing tests because it is not a file URL")
      return
    }
    if Task.isCancelled {
      return
    }
    guard !removedFiles.contains(uri) else {
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      // File no longer exists. Probably deleted since we scheduled it for indexing. Nothing to worry about.
      logger.info("Not indexing \(uri.forLogging) for tests because it does not exist")
      return
    }
    guard
      let fileModificationDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]
        as? Date
    else {
      logger.fault("Not indexing \(uri.forLogging) for tests because the modification date could not be determined")
      return
    }
    if let indexModificationDate = self.indexedTests[uri]?.sourceFileModificationDate,
      indexModificationDate >= fileModificationDate
    {
      // Index already up to date.
      return
    }
    if Task.isCancelled {
      return
    }
    let testItems = await testItems(in: url)

    guard !removedFiles.contains(uri) else {
      // Check whether the file got removed while we were scanning it for tests. If so, don't add it back to
      // `indexedTests`.
      return
    }
    self.indexedTests[uri] = IndexedTests(tests: testItems, sourceFileModificationDate: fileModificationDate)
  }

  /// Gets all the tests in the syntactic index.
  ///
  /// This waits for any pending document updates to be indexed before returning a result.
  nonisolated func tests() async -> [AnnotatedTestItem] {
    let readTask = indexingQueue.async(metadata: .read) {
      return await self.indexedTests.values.flatMap { $0.tests }
    }
    return await readTask.value
  }
}
