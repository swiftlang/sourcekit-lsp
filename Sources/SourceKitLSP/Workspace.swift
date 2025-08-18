//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import BuildServerIntegration
package import BuildServerProtocol
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
package import SKOptions
package import SemanticIndex
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

#if canImport(DocCDocumentation)
package import DocCDocumentation
#endif

/// Actor that caches realpaths for `sourceFilesWithSameRealpath`.
fileprivate actor SourceFilesWithSameRealpathInferrer {
  private let buildServerManager: BuildServerManager
  private var realpathCache: [DocumentURI: DocumentURI] = [:]

  init(buildServerManager: BuildServerManager) {
    self.buildServerManager = buildServerManager
  }

  private func realpath(of uri: DocumentURI) -> DocumentURI {
    if let cached = realpathCache[uri] {
      return cached
    }
    let value = uri.symlinkTarget ?? uri
    realpathCache[uri] = value
    return value
  }

  /// Returns the URIs of all source files in the project that have the same realpath as a document in `documents` but
  /// are not in `documents`.
  ///
  /// This is useful in the following scenario: A project has target A containing A.swift an target B containing B.swift
  /// B.swift is a symlink to A.swift. When A.swift is modified, both the dependencies of A and B need to be marked as
  /// having an out-of-date preparation status, not just A.
  package func sourceFilesWithSameRealpath(as documents: [DocumentURI]) async -> [DocumentURI] {
    let realPaths = Set(documents.map { realpath(of: $0) })
    return await orLog("Determining source files with same realpath") {
      var result: [DocumentURI] = []
      let filesAndDirectories = try await buildServerManager.sourceFiles(includeNonBuildableFiles: true)
      for file in filesAndDirectories.keys {
        if realPaths.contains(realpath(of: file)) && !documents.contains(file) {
          result.append(file)
        }
      }
      return result
    } ?? []
  }

  func filesDidChange(_ events: [FileEvent]) {
    for event in events {
      realpathCache[event.uri] = nil
    }
  }
}

/// Represents the configuration and state of a project or combination of projects being worked on
/// together.
///
/// In LSP, this represents the per-workspace state that is typically only available after the
/// "initialize" request has been made.
///
/// Typically a workspace is contained in a root directory.
package final class Workspace: Sendable, BuildServerManagerDelegate {
  /// The ``SourceKitLSPServer`` instance that created this `Workspace`.
  private(set) weak nonisolated(unsafe) var sourceKitLSPServer: SourceKitLSPServer? {
    didSet {
      preconditionFailure("sourceKitLSPServer must not be modified. It is only a var because it is weak")
    }
  }

  /// The root directory of the workspace.
  ///
  /// `nil` when SourceKit-LSP is launched without a workspace (ie. no workspace folder or rootURI).
  package let rootUri: DocumentURI?

  /// Tracks dynamically registered server capabilities as well as the client's capabilities.
  package let capabilityRegistry: CapabilityRegistry

  /// The build server manager to use for documents in this workspace.
  package let buildServerManager: BuildServerManager

  #if canImport(DocCDocumentation)
  package let doccDocumentationManager: DocCDocumentationManager
  #endif

  private let sourceFilesWithSameRealpathInferrer: SourceFilesWithSameRealpathInferrer

  let options: SourceKitLSPOptions

  /// The source code index, if available.
  ///
  /// Usually a checked index (retrieved using `index(checkedFor:)`) should be used instead of the unchecked index.
  private let _uncheckedIndex: ThreadSafeBox<UncheckedIndex?>

  private var uncheckedIndex: UncheckedIndex? {
    return _uncheckedIndex.value
  }

  /// The index that syntactically scans the workspace for tests.
  let syntacticTestIndex: SyntacticTestIndex

  /// Language service for an open document, if available.
  private let documentService: ThreadSafeBox<[DocumentURI: LanguageService]> = ThreadSafeBox(initialValue: [:])

  /// The `SemanticIndexManager` that keeps track of whose file's index is up-to-date in the workspace and schedules
  /// indexing and preparation tasks for files with out-of-date index.
  ///
  /// `nil` if background indexing is not enabled.
  package let semanticIndexManager: SemanticIndexManager?

  /// If the index uses explicit output paths, the queue on which we update the explicit output paths.
  ///
  /// The reason we perform these update on a queue is that we can wait for all of them to finish when polling the
  /// index.
  private let indexUnitOutputPathsUpdateQueue = AsyncQueue<Serial>()

  private init(
    sourceKitLSPServer: SourceKitLSPServer,
    rootUri: DocumentURI?,
    capabilityRegistry: CapabilityRegistry,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    buildServerManager: BuildServerManager,
    index uncheckedIndex: UncheckedIndex?,
    indexDelegate: SourceKitIndexDelegate?,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.rootUri = rootUri
    self.capabilityRegistry = capabilityRegistry
    self.options = options
    self._uncheckedIndex = ThreadSafeBox(initialValue: uncheckedIndex)
    self.buildServerManager = buildServerManager
    #if canImport(DocCDocumentation)
    self.doccDocumentationManager = DocCDocumentationManager(buildServerManager: buildServerManager)
    #endif
    self.sourceFilesWithSameRealpathInferrer = SourceFilesWithSameRealpathInferrer(
      buildServerManager: buildServerManager
    )
    if options.backgroundIndexingOrDefault, let uncheckedIndex,
      await buildServerManager.initializationData?.prepareProvider ?? false
    {
      let shouldIndexInParallel = await buildServerManager.initializationData?.multiTargetPreparation?.supported ?? true
      let batchSize: Int
      if shouldIndexInParallel {
        if let customBatchSize = await buildServerManager.initializationData?.multiTargetPreparation?.batchSize {
          batchSize = customBatchSize
        } else {
          let processorCount = ProcessInfo.processInfo.activeProcessorCount
          batchSize = max(1, processorCount / 2)
        }
      } else {
        batchSize = 1
      }
      self.semanticIndexManager = SemanticIndexManager(
        index: uncheckedIndex,
        buildServerManager: buildServerManager,
        updateIndexStoreTimeout: options.indexOrDefault.updateIndexStoreTimeoutOrDefault,
        hooks: hooks.indexHooks,
        indexTaskScheduler: indexTaskScheduler,
        indexTaskBatchSize: batchSize,
        logMessageToIndexLog: { [weak sourceKitLSPServer] in
          sourceKitLSPServer?.logMessageToIndexLog(message: $0, type: $1, structure: $2)
        },
        indexTasksWereScheduled: { [weak sourceKitLSPServer] in
          sourceKitLSPServer?.indexProgressManager.indexTasksWereScheduled(count: $0)
        },
        indexProgressStatusDidChange: { [weak sourceKitLSPServer] in
          sourceKitLSPServer?.indexProgressManager.indexProgressStatusDidChange()
        }
      )
    } else {
      self.semanticIndexManager = nil
    }
    // Trigger an initial population of `syntacticTestIndex`.
    self.syntacticTestIndex = SyntacticTestIndex(
      languageServiceRegistry: sourceKitLSPServer.languageServiceRegistry,
      determineTestFiles: {
        await orLog("Getting list of test files for initial syntactic index population") {
          try await buildServerManager.testFiles()
        } ?? []
      }
    )
    await indexDelegate?.addMainFileChangedCallback { [weak self] in
      await self?.buildServerManager.mainFilesChanged()
    }
    if let semanticIndexManager {
      await semanticIndexManager.scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(
        indexFilesWithUpToDateUnit: false
      )
    }
  }

  /// Creates a workspace for a given root `DocumentURI`, inferring the `ExternalWorkspace` if possible.
  ///
  /// - Parameters:
  ///   - url: The root directory of the workspace, which must be a valid path.
  ///   - clientCapabilities: The client capabilities provided during server initialization.
  ///   - toolchainRegistry: The toolchain registry.
  convenience init(
    sourceKitLSPServer: SourceKitLSPServer,
    documentManager: DocumentManager,
    rootUri: DocumentURI?,
    capabilityRegistry: CapabilityRegistry,
    buildServerSpec: BuildServerSpec?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async {
    struct ConnectionToClient: BuildServerManagerConnectionToClient {
      func waitUntilInitialized() async {
        await sourceKitLSPServer?.waitUntilInitialized()
      }

      weak var sourceKitLSPServer: SourceKitLSPServer?
      func send(_ notification: some NotificationType) {
        guard let sourceKitLSPServer else {
          // `SourceKitLSPServer` has been destructed. We are tearing down the
          // language server. Nothing left to do.
          logger.error(
            "Ignoring notification \(type(of: notification).method) because connection to editor has been closed"
          )
          return
        }
        sourceKitLSPServer.sendNotificationToClient(notification)
      }

      func nextRequestID() -> RequestID {
        return .string(UUID().uuidString)
      }

      func send<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
      ) {
        guard let sourceKitLSPServer else {
          // `SourceKitLSPServer` has been destructed. We are tearing down the
          // language server. Nothing left to do.
          reply(.failure(ResponseError.unknown("Connection to the editor closed")))
          return
        }
        sourceKitLSPServer.client.send(request, id: id, reply: reply)
      }

      /// Whether the client can handle `WorkDoneProgress` requests.
      var clientSupportsWorkDoneProgress: Bool {
        get async {
          await sourceKitLSPServer?.capabilityRegistry?.clientCapabilities.window?.workDoneProgress ?? false
        }
      }

      func watchFiles(_ fileWatchers: [FileSystemWatcher]) async {
        await sourceKitLSPServer?.watchFiles(fileWatchers)
      }

      func logMessageToIndexLog(message: String, type: WindowMessageType, structure: StructuredLogKind?) {
        guard let sourceKitLSPServer else {
          // `SourceKitLSPServer` has been destructed. We are tearing down the
          // language server. Nothing left to do.
          logger.error("Ignoring index log notification because connection to editor has been closed")
          return
        }
        sourceKitLSPServer.logMessageToIndexLog(message: message, type: type, structure: structure)
      }
    }

    let buildServerManager = await BuildServerManager(
      buildServerSpec: buildServerSpec,
      toolchainRegistry: toolchainRegistry,
      options: options,
      connectionToClient: ConnectionToClient(sourceKitLSPServer: sourceKitLSPServer),
      buildServerHooks: hooks.buildServerHooks
    )

    logger.log(
      "Created workspace at \(rootUri.forLogging) with project root \(buildServerSpec?.projectRoot.description ?? "<nil>")"
    )

    var indexDelegate: SourceKitIndexDelegate? = nil

    let indexOptions = options.indexOrDefault
    let indexStorePath: URL? =
      if let indexStorePath = await buildServerManager.initializationData?.indexStorePath {
        URL(fileURLWithPath: indexStorePath, relativeTo: rootUri?.fileURL)
      } else {
        nil
      }
    let indexDatabasePath: URL? =
      if let indexDatabasePath = await buildServerManager.initializationData?.indexDatabasePath {
        URL(fileURLWithPath: indexDatabasePath, relativeTo: rootUri?.fileURL)
      } else {
        nil
      }
    let supportsOutputPaths = await buildServerManager.initializationData?.outputPathsProvider ?? false
    let index: UncheckedIndex?
    if let indexStorePath, let indexDatabasePath, let libPath = await toolchainRegistry.default?.libIndexStore {
      do {
        indexDelegate = SourceKitIndexDelegate()
        let prefixMappings =
          (indexOptions.indexPrefixMap ?? [:])
          .map { PathMapping(original: $0.key, replacement: $0.value) }
          .sorted {
            // Fixes an issue where remapPath might match the shortest path first when multiple common prefixes exist
            // Sort by path length descending to prioritize more specific paths;
            // when lengths are equal, sort lexicographically in ascending order
            if $0.original.count != $1.original.count {
              return $0.original.count > $1.original.count  // Prefer longer paths (more specific)
            } else {
              return $0.original < $1.original  // Alphabetical sort when lengths are equal, ensures stable ordering
            }
          }
        if let indexInjector = hooks.indexHooks.indexInjector {
          let indexStoreDB = try await indexInjector.createIndex(
            storePath: indexStorePath,
            databasePath: indexDatabasePath,
            indexStoreLibraryPath: libPath,
            delegate: indexDelegate!,
            prefixMappings: prefixMappings
          )
          index = UncheckedIndex(indexStoreDB, usesExplicitOutputPaths: await indexInjector.usesExplicitOutputPaths)
        } else {
          let indexStoreDB = try IndexStoreDB(
            storePath: indexStorePath.filePath,
            databasePath: indexDatabasePath.filePath,
            library: IndexStoreLibrary(dylibPath: libPath.filePath),
            delegate: indexDelegate,
            useExplicitOutputUnits: supportsOutputPaths,
            prefixMappings: prefixMappings
          )
          index = UncheckedIndex(indexStoreDB, usesExplicitOutputPaths: supportsOutputPaths)
          logger.debug(
            "Opened IndexStoreDB at \(indexDatabasePath) with store path \(indexStorePath) with explicit output files \(supportsOutputPaths)"
          )
        }
      } catch {
        index = nil
        logger.error("Failed to open IndexStoreDB: \(error.localizedDescription)")
      }
    } else {
      index = nil
    }

    await buildServerManager.setMainFilesProvider(index)

    await self.init(
      sourceKitLSPServer: sourceKitLSPServer,
      rootUri: rootUri,
      capabilityRegistry: capabilityRegistry,
      options: options,
      hooks: hooks,
      buildServerManager: buildServerManager,
      index: index,
      indexDelegate: indexDelegate,
      indexTaskScheduler: indexTaskScheduler
    )
    await buildServerManager.setDelegate(self)

    // Populate the initial list of unit output paths in the index.
    await scheduleUpdateOfUnitOutputPathsInIndexIfNecessary()
  }

  package static func forTesting(
    options: SourceKitLSPOptions,
    sourceKitLSPServer: SourceKitLSPServer,
    testHooks: Hooks,
    buildServerManager: BuildServerManager,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async -> Workspace {
    return await Workspace(
      sourceKitLSPServer: sourceKitLSPServer,
      rootUri: nil,
      capabilityRegistry: CapabilityRegistry(clientCapabilities: ClientCapabilities()),
      options: options,
      hooks: testHooks,
      buildServerManager: buildServerManager,
      index: nil,
      indexDelegate: nil,
      indexTaskScheduler: indexTaskScheduler
    )
  }

  /// Returns a `CheckedIndex` that verifies that all the returned entries are up-to-date with the given
  /// `IndexCheckLevel`.
  package func index(checkedFor checkLevel: IndexCheckLevel) -> CheckedIndex? {
    return _uncheckedIndex.value?.checked(for: checkLevel)
  }

  /// Write the index to disk.
  ///
  /// After this method is called, the workspace will no longer have an index associated with it. It should only be
  /// called when SourceKit-LSP shuts down.
  func closeIndex() {
    _uncheckedIndex.value = nil
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    // First clear any cached realpaths in `sourceFilesWithSameRealpathInferrer`.
    await sourceFilesWithSameRealpathInferrer.filesDidChange(events)

    // Now infer any edits for source files that share the same realpath as one of the modified files.
    var events = events
    events +=
      await sourceFilesWithSameRealpathInferrer
      .sourceFilesWithSameRealpath(as: events.filter { $0.type == .changed }.map(\.uri))
      .map { FileEvent(uri: $0, type: .changed) }

    // Notify all clients about the reported and inferred edits.
    await buildServerManager.filesDidChange(events)
    #if canImport(DocCDocumentation)
    await doccDocumentationManager.filesDidChange(events)
    #endif

    async let updateSyntacticIndex: Void = await syntacticTestIndex.filesDidChange(events)
    async let updateSemanticIndex: Void? = await semanticIndexManager?.filesDidChange(events)
    _ = await (updateSyntacticIndex, updateSemanticIndex)
  }

  func documentService(for uri: DocumentURI) -> LanguageService? {
    return documentService.value[uri.buildSettingsFile]
  }

  /// Set a language service for a document uri and returns if none exists already.
  /// If a language service already exists for this document, eg. because two requests start creating a language
  /// service for a document and race, `newLanguageService` is dropped and the existing language service for the
  /// document is returned.
  func setDocumentService(for uri: DocumentURI, _ newLanguageService: any LanguageService) -> LanguageService {
    return documentService.withLock { service in
      if let languageService = service[uri] {
        return languageService
      }

      service[uri] = newLanguageService
      return newLanguageService
    }
  }

  /// Handle a build settings change notification from the build serveer.
  /// This has two primary cases:
  /// - Initial settings reported for a given file, now we can fully open it
  /// - Changed settings for an already open file
  package func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    for uri in changedFiles {
      await self.documentService(for: uri)?.documentUpdatedBuildSettings(uri)
    }
  }

  /// Handle a dependencies updated notification from the build server.
  /// We inform the respective language services as long as the given file is open
  /// (not queued for opening).
  package func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) async {
    var documentsByService: [ObjectIdentifier: (Set<DocumentURI>, LanguageService)] = [:]
    for uri in changedFiles {
      logger.log("Dependencies updated for file \(uri.forLogging)")
      guard let languageService = documentService(for: uri) else {
        logger.error("No document service exists for \(uri.forLogging)")
        continue
      }
      documentsByService[ObjectIdentifier(languageService), default: ([], languageService)].0.insert(uri)
    }
    for (documents, service) in documentsByService.values {
      await service.documentDependenciesUpdated(documents)
    }
  }

  package func buildTargetsChanged(_ changes: [BuildTargetEvent]?) async {
    await sourceKitLSPServer?.fileHandlingCapabilityChanged()
    await semanticIndexManager?.buildTargetsChanged(changes)
    await orLog("Scheduling syntactic test re-indexing") {
      let testFiles = try await buildServerManager.testFiles()
      await syntacticTestIndex.listOfTestFilesDidChange(testFiles)
    }

    await scheduleUpdateOfUnitOutputPathsInIndexIfNecessary()
  }

  private func scheduleUpdateOfUnitOutputPathsInIndexIfNecessary() async {
    guard await self.uncheckedIndex?.usesExplicitOutputPaths ?? false else {
      return
    }
    guard await buildServerManager.initializationData?.outputPathsProvider ?? false else {
      // This can only happen if an index got injected that uses explicit output paths but the build server does not
      // support output paths.
      logger.error("The index uses explicit output paths but the build server does not support output paths")
      return
    }

    indexUnitOutputPathsUpdateQueue.async {
      await orLog("Setting new list of unit output paths") {
        let outputPaths = try await Set(self.buildServerManager.outputPathsInAllTargets())
        await self.uncheckedIndex?.setUnitOutputPaths(outputPaths)
      }
    }
  }

  package var clientSupportsWorkDoneProgress: Bool {
    get async {
      await sourceKitLSPServer?.capabilityRegistry?.clientCapabilities.window?.workDoneProgress ?? false
    }
  }

  package func waitUntilInitialized() async {
    await sourceKitLSPServer?.waitUntilInitialized()
  }

  package func synchronize(_ request: SynchronizeRequest) async {
    if request.buildServerUpdates ?? false || request.index ?? false {
      await buildServerManager.waitForUpToDateBuildGraph()
      await indexUnitOutputPathsUpdateQueue.async {}.value
    }
    if request.index ?? false {
      await semanticIndexManager?.waitForUpToDateIndex()
      uncheckedIndex?.pollForUnitChangesAndWait()
    }
  }
}

/// Wrapper around a workspace that isn't being retained.
package struct WeakWorkspace {
  package weak var value: Workspace?

  package init(_ value: Workspace? = nil) {
    self.value = value
  }
}
