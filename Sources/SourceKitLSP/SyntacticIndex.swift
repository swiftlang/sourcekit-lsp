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

@_spi(SourceKitLSP) package import BuildServerIntegration
@_spi(SourceKitLSP) package import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Task metadata for `SyntacticIndex.indexingQueue`
private enum TaskMetadata: DependencyTracker, Equatable {
  /// Determine the list of files from the build server and scan them for tests / playgrounds. Only created when the
  /// `SyntacticIndex` is created
  case initialPopulation

  /// Index the files in the given set for tests / playgrounds
  case index(Set<DocumentURI>)

  /// Retrieve information about syntactically discovered tests / playgrounds from the index.
  case read

  /// Reads can be concurrent and files can be indexed concurrently. But we need to wait for all files to finish
  /// indexing before reading the index.
  func isDependency(of other: TaskMetadata) -> Bool {
    switch (self, other) {
    case (.initialPopulation, _):
      // The initial population need to finish before we can do anything with the task.
      return true
    case (_, .initialPopulation):
      // Should never happen because the initial population should only be scheduled once before any other operations
      // on the index. But be conservative in case we do get an `initialPopulation` somewhere in between and use it
      // as a full blocker on the queue.
      return true
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

/// Data from a syntactic scan of a source file for tests or playgrounds.
private struct IndexedSourceFile {
  /// The tests within the source file.
  let tests: [AnnotatedTestItem]

  /// The playgrounds within the source file.
  let playgrounds: [TextDocumentPlayground]

  /// The modification date of the source file when it was scanned. A file won't get re-scanned if its modification date
  /// is older or the same as this date.
  let sourceFileModificationDate: Date
}

/// An in-memory syntactic index of test and playground items within a workspace.
///
/// The index does not get persisted to disk but instead gets rebuilt every time a workspace is opened (ie. usually when
/// sourcekit-lsp is launched). Building it takes only a few seconds, even for large projects.
package actor SyntacticIndex: Sendable {
  /// The tests discovered by the index.
  private var indexedSources: [DocumentURI: IndexedSourceFile] = [:]

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

  /// Fetch the list of source files to scan for a given set of build targets
  private let determineFilesToScan:
    @Sendable (Set<BuildTargetIdentifier>?) async -> [(uri: DocumentURI, info: SourceFileInfo)]

  /// Syntactically parse tests from the given snapshot
  private let syntacticTests: @Sendable (DocumentSnapshot) async -> [AnnotatedTestItem]

  /// Syntactically parse playgrounds from the given snapshot
  private let syntacticPlaygrounds: @Sendable (DocumentSnapshot) async -> [TextDocumentPlayground]

  package init(
    determineFilesToScan:
      @Sendable @escaping (Set<BuildTargetIdentifier>?) async -> [(uri: DocumentURI, info: SourceFileInfo)],
    syntacticTests: @Sendable @escaping (DocumentSnapshot) async -> [AnnotatedTestItem],
    syntacticPlaygrounds: @Sendable @escaping (DocumentSnapshot) async -> [TextDocumentPlayground]
  ) {
    self.determineFilesToScan = determineFilesToScan
    self.syntacticTests = syntacticTests
    self.syntacticPlaygrounds = syntacticPlaygrounds

    indexingQueue.async(priority: .low, metadata: .initialPopulation) {
      let filesToScan = await self.determineFilesToScan(nil)
      // Divide the files into multiple batches. This is more efficient than spawning a new task for every file, mostly
      // because it keeps the number of pending items in `indexingQueue` low and adding a new task to `indexingQueue` is
      // in O(number of pending tasks), since we need to scan for dependency edges to add, which would make scanning files
      // be O(number of files).
      // Over-subscribe the processor count in case one batch finishes more quickly than another.
      let batches = filesToScan.partition(intoNumberOfBatches: ProcessInfo.processInfo.activeProcessorCount * 4)
      await batches.concurrentForEach { filesInBatch in
        for (uri, info) in filesInBatch {
          await self.rescanFileAssumingOnQueue(uri, scanForTests: info.mayContainTests)
        }
      }
    }
  }

  private func removeFilesFromIndex(_ removedFiles: Set<DocumentURI>) {
    self.removedFiles.formUnion(removedFiles)
    for removedFile in removedFiles {
      self.indexedSources[removedFile] = nil
    }
  }

  /// Called when the list of targets is updated.
  ///
  /// All files that are not in the new list of buildable files will be removed from the index.
  package func buildTargetsChanged(_ changedTargets: Set<BuildTargetIdentifier>?) async {
    let changedFiles = await determineFilesToScan(changedTargets)
    let removedFiles = Set(self.indexedSources.keys).subtracting(changedFiles.map(\.uri))
    removeFilesFromIndex(removedFiles)

    rescanFiles(changedFiles)
  }

  package func filesDidChange(_ events: [(FileEvent, SourceFileInfo)]) {
    var removedFiles: Set<DocumentURI> = []
    var filesToRescan: [(DocumentURI, SourceFileInfo)] = []
    for (fileEvent, sourceFileInfo) in events {
      switch fileEvent.type {
      case .created, .changed:
        filesToRescan.append((fileEvent.uri, sourceFileInfo))
      case .deleted:
        removedFiles.insert(fileEvent.uri)
      default:
        logger.error("Ignoring unknown FileEvent type \(fileEvent.type.rawValue) in SyntacticIndex")
      }
    }
    removeFilesFromIndex(removedFiles)
    rescanFiles(filesToRescan)
  }

  /// Called when a list of files was updated. Re-scans those files
  private func rescanFiles(_ filesToScan: [(uri: DocumentURI, info: SourceFileInfo)]) {
    // If we scan a file again, it might have been added after being removed before. Remove it from the list of removed
    // files.
    removedFiles.subtract(filesToScan.map(\.uri))

    // If we already know that the file has an up-to-date index, avoid re-scheduling it to be indexed. This ensures
    // that we don't bloat `indexingQueue` if the build server is sending us repeated `buildTarget/didChange`
    // notifications.
    // This check does not need to be perfect and there might be an in-progress index operation that is about to index
    // the file. In that case we still schedule another rescan of that file and notice in `rescanFilesAssumingOnQueue`
    // that the index is already up-to-date, which makes the rescan a no-op.
    let filesToScan = filesToScan.filter { (uri, _) in
      if let url = uri.fileURL,
        let indexModificationDate = self.indexedSources[uri]?.sourceFileModificationDate,
        let fileModificationDate = try? FileManager.default.attributesOfItem(atPath: url.filePath)[.modificationDate]
          as? Date,
        indexModificationDate >= fileModificationDate
      {
        return false
      }
      return true
    }

    guard !filesToScan.isEmpty else {
      return
    }

    logger.info(
      "Syntactically scanning \(filesToScan.count) files: \(filesToScan.map(\.uri).map(\.arbitrarySchemeURL.lastPathComponent).joined(separator: ", "))"
    )

    // Divide the files into multiple batches. This is more efficient than spawning a new task for every file, mostly
    // because it keeps the number of pending items in `indexingQueue` low and adding a new task to `indexingQueue` is
    // in O(number of pending tasks), since we need to scan for dependency edges to add, which would make scanning files
    // be O(number of files).
    // Over-subscribe the processor count in case one batch finishes more quickly than another.
    let batches = filesToScan.partition(intoNumberOfBatches: ProcessInfo.processInfo.activeProcessorCount * 4)
    for batch in batches {
      self.indexingQueue.async(priority: .low, metadata: .index(Set(batch.map(\.uri)))) {
        for (uri, info) in batch {
          await self.rescanFileAssumingOnQueue(uri, scanForTests: info.mayContainTests)
        }
      }
    }
  }

  /// Re-scans a single file.
  ///
  /// - Important: This method must be called in a task that is executing on `indexingQueue`.
  private func rescanFileAssumingOnQueue(_ uri: DocumentURI, scanForTests: Bool) async {
    guard let language = Language(inferredFromFileExtension: uri) else {
      return
    }

    guard let url = uri.fileURL else {
      logger.log("Not indexing \(uri.forLogging) because it is not a file URL")
      return
    }
    if Task.isCancelled {
      return
    }
    guard !removedFiles.contains(uri) else {
      return
    }
    guard FileManager.default.fileExists(at: url) else {
      // File no longer exists. Probably deleted since we scheduled it for indexing. Nothing to worry about.
      logger.info("Not indexing \(uri.forLogging) because it does not exist")
      return
    }
    guard
      let fileModificationDate = try? FileManager.default.attributesOfItem(atPath: url.filePath)[.modificationDate]
        as? Date
    else {
      logger.fault("Not indexing \(uri.forLogging) because the modification date could not be determined")
      return
    }
    if let indexModificationDate = self.indexedSources[uri]?.sourceFileModificationDate,
      indexModificationDate >= fileModificationDate
    {
      // Index already up to date.
      return
    }
    if Task.isCancelled {
      return
    }

    let snapshot: DocumentSnapshot? = orLog("Getting document snapshot for syntactic scanning") {
      try DocumentSnapshot(withContentsFromDisk: url, language: language)
    }
    guard let snapshot else {
      return
    }

    async let asyncTestItems = scanForTests ? syntacticTests(snapshot) : []
    async let asyncPlaygrounds = syntacticPlaygrounds(snapshot)

    let testItems = await asyncTestItems
    let playgrounds = await asyncPlaygrounds

    guard !removedFiles.contains(uri) else {
      // Check whether the file got removed while we were scanning it for tests. If so, don't add it back to
      // `indexedSources`.
      return
    }

    self.indexedSources[uri] = IndexedSourceFile(
      tests: testItems,
      playgrounds: playgrounds,
      sourceFileModificationDate: fileModificationDate
    )
  }

  /// Gets the syntactically indexed tests for the given files.
  ///
  /// This waits for any pending document updates to be indexed before returning a result.
  nonisolated package func tests(in files: [DocumentURI]) async -> [AnnotatedTestItem] {
    let readTask = indexingQueue.async(metadata: .read) {
      let indexedSources = await self.indexedSources
      return files.flatMap({ indexedSources[$0]?.tests ?? [] })
    }
    return await readTask.value
  }

  /// Gets all the playgrounds in the syntactic index.
  ///
  /// This waits for any pending document updates to be indexed before returning a result.
  nonisolated package func playgrounds() async -> [Playground] {
    let readTask = indexingQueue.async(metadata: .read) {
      return await self.indexedSources.flatMap { (uri, indexedFile) in
        indexedFile.playgrounds.map {
          Playground(id: $0.id, label: $0.label, location: Location(uri: uri, range: $0.range))
        }
      }
    }
    return await readTask.value
  }
}
