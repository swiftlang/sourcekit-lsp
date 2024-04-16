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
import LSPLogging
import LanguageServerProtocol
import SKSupport

/// Task metadata for `SyntacticTestIndexer.indexingQueue`
fileprivate enum TaskMetadata: DependencyTracker, Equatable {
  case read
  case index(DocumentURI)

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
    case (.index(let lhsUri), .index(let rhsUri)):
      // Technically, we should be able to allow simultaneous indexing of the same file. But conceptually the code
      // becomes simpler if we don't need to think racing indexing tasks for the same file and it shouldn't make a
      // performance impact because if the same file state is indexed twice, the second one will realize that the mtime
      // hasn't changed and thus be a no-op.
      return lhsUri == rhsUri
    }
  }
}

/// Data from a syntactic scan of a source file for tests.
fileprivate struct IndexedTests {
  /// The tests within the source file.
  let tests: [TestItem]

  /// The modification date of the source file when it was scanned. A file won't get re-scanned if its modification date
  /// is older or the same as this date.
  let sourceFileModificationDate: Date
}

/// Syntactically scans the file at the given URL for tests declared within it.
///
/// Does not write the results to the index.
///
/// The order of the returned tests is not defined. The results should be sorted before being returned to the editor.
fileprivate func testItems(in url: URL) async -> [TestItem] {
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

actor SyntacticTestIndex {
  /// The tests discovered by the index.
  private var indexedTests: [DocumentURI: IndexedTests] = [:]

  /// The queue on which the index is being updated and queried.
  ///
  /// Tracking dependencies between tasks within this queue allows us to start indexing tasks in parallel with low
  /// priority and elevate their priority once a read task comes in, which has higher priority and depends on the
  /// indexing tasks to finish.
  private let indexingQueue = AsyncQueue<TaskMetadata>()

  init() {}

  private func removeFilesFromIndex(_ removedFiles: Set<DocumentURI>) {
    // Cancel any tasks for the removed files to ensure any pending indexing tasks don't re-add index data for the
    // removed files.
    self.indexingQueue.cancelTasks(where: { taskMetadata in
      guard case .index(let uri) = taskMetadata else {
        return false
      }
      return removedFiles.contains(uri)
    })
    for removedFile in removedFiles {
      self.indexedTests[removedFile] = nil
    }
  }

  /// Called when the list of files that may contain tests is updated.
  ///
  /// All files that are not in the new list of test files will be removed from the index.
  func listOfTestFilesDidChange(_ testFiles: Set<DocumentURI>) {
    let testFiles = Set(testFiles)
    let removedFiles = Set(self.indexedTests.keys.filter { !testFiles.contains($0) })
    removeFilesFromIndex(removedFiles)

    for testFile in testFiles {
      rescanFile(testFile)
    }
  }

  func filesDidChange(_ events: [FileEvent]) {
    for fileEvent in events {
      switch fileEvent.type {
      case .created:
        // We don't know if this is a potential test file. It would need to be added to the index via
        // `listOfTestFilesDidChange`
        break
      case .changed:
        rescanFile(fileEvent.uri)
      case .deleted:
        removeFilesFromIndex([fileEvent.uri])
      default:
        logger.error("Ignoring unknown FileEvent type \(fileEvent.type.rawValue) in SyntacticTestIndex")
      }
    }
  }

  /// Called when a single file was updated. Just re-scans that file.
  private func rescanFile(_ uri: DocumentURI) {
    self.indexingQueue.async(priority: .low, metadata: .index(uri)) {
      guard let url = uri.fileURL else {
        logger.log("Not indexing \(uri.forLogging) for swift-testing tests because it is not a file URL")
        return
      }
      if Task.isCancelled {
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

      if Task.isCancelled {
        // This `isCancelled` check is essential for correctness. When `testFilesDidChange` is called, it cancels all
        // indexing tasks for files that have been removed. If we didn't have this check, an index task that was already
        // started might add the file back into `indexedTests`.
        return
      }
      self.indexedTests[uri] = IndexedTests(tests: testItems, sourceFileModificationDate: fileModificationDate)
    }
  }

  /// Gets all the tests in the syntactic index.
  ///
  /// This waits for any pending document updates to be indexed before returning a result.
  nonisolated func tests() async -> [TestItem] {
    let readTask = indexingQueue.async(metadata: .read) {
      return await self.indexedTests.values.flatMap { $0.tests }
    }
    return await readTask.value
  }
}
