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
@_spi(SourceKitLSP) package import BuildServerProtocol
import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SKOptions
package import SemanticIndex
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

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

/// Create an index instance based on the given options and response from the build server.
func createIndex(
  initializationData: SourceKitInitializeBuildResponseData?,
  mainFilesChangedCallback: @escaping @Sendable () async -> Void,
  rootUri: DocumentURI?,
  toolchainRegistry: ToolchainRegistry,
  options: SourceKitLSPOptions,
  hooks: Hooks,
) async -> UncheckedIndex? {
  let indexOptions = options.indexOrDefault
  let indexStorePath: URL? =
    if let indexStorePath = initializationData?.indexStorePath {
      URL(fileURLWithPath: indexStorePath, relativeTo: rootUri?.fileURL)
    } else {
      nil
    }
  let indexDatabasePath: URL? =
    if let indexDatabasePath = initializationData?.indexDatabasePath {
      URL(fileURLWithPath: indexDatabasePath, relativeTo: rootUri?.fileURL)
    } else {
      nil
    }
  let supportsOutputPaths = initializationData?.outputPathsProvider ?? false
  if let indexStorePath, let indexDatabasePath, let libPath = await toolchainRegistry.default?.libIndexStore {
    do {
      let indexDelegate = SourceKitIndexDelegate {
        await mainFilesChangedCallback()
      }
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
          delegate: indexDelegate,
          prefixMappings: prefixMappings
        )
        return UncheckedIndex(indexStoreDB, usesExplicitOutputPaths: await indexInjector.usesExplicitOutputPaths)
      } else {
        let indexStoreDB = try IndexStoreDB(
          storePath: indexStorePath.filePath,
          databasePath: indexDatabasePath.filePath,
          library: IndexStoreLibrary(dylibPath: libPath.filePath),
          delegate: indexDelegate,
          useExplicitOutputUnits: supportsOutputPaths,
          prefixMappings: prefixMappings
        )
        logger.debug(
          "Opened IndexStoreDB at \(indexDatabasePath) with store path \(indexStorePath) with explicit output files \(supportsOutputPaths)"
        )
        return UncheckedIndex(indexStoreDB, usesExplicitOutputPaths: supportsOutputPaths)
      }
    } catch {
      logger.error("Failed to open IndexStoreDB: \(error.localizedDescription)")
      return nil
    }
  } else {
    return nil
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

  private let sourceFilesWithSameRealpathInferrer: SourceFilesWithSameRealpathInferrer

  let options: SourceKitLSPOptions

  /// The source code index, if available.
  ///
  /// Usually a checked index (retrieved using `index(checkedFor:)`) should be used instead of the unchecked index.
  private var uncheckedIndex: UncheckedIndex? {
    get async {
      return await buildServerManager.mainFilesProvider(as: UncheckedIndex.self)
    }
  }

  /// The index that syntactically scans the workspace for Swift symbols.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private(set) nonisolated(unsafe) var syntacticIndex: SyntacticIndex! {
    didSet {
      precondition(oldValue == nil)
      precondition(syntacticIndex != nil)
    }
  }

  /// Language service for an open document, if available.
  private let languageServices: ThreadSafeBox<[DocumentURI: [any LanguageService]]> = ThreadSafeBox(initialValue: [:])

  /// All language services that are registered with this workspace.
  var allLanguageServices: [any LanguageService] {
    return languageServices.value.values.flatMap { $0 }
  }

  /// The task that constructs the `SemanticIndexManager`, which keeps track of whose file's index is up-to-date in the
  /// workspace and schedules indexing and preparation tasks for files with out-of-date index.
  ///
  /// This is a task because we need to wait for build server initialization to construct the `SemanticIndexManager` so
  /// that we know the index store and indexstore-db path. Since external build servers may take a while to initialize,
  /// we don't want to block the creation of a `Workspace` and thus all syntactic functionality until we have received
  /// the build server initialization response.
  ///
  /// `nil` if background indexing is not enabled.
  package let semanticIndexManagerTask: Task<SemanticIndexManager?, Never>

  package var semanticIndexManager: SemanticIndexManager? {
    get async {
      await semanticIndexManagerTask.value
    }
  }

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
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.rootUri = rootUri
    self.capabilityRegistry = capabilityRegistry
    self.options = options
    self.buildServerManager = buildServerManager
    self.sourceFilesWithSameRealpathInferrer = SourceFilesWithSameRealpathInferrer(
      buildServerManager: buildServerManager
    )
    self.semanticIndexManagerTask = Task {
      if options.backgroundIndexingOrDefault,
        let uncheckedIndex = await buildServerManager.mainFilesProvider(as: UncheckedIndex.self),
        await buildServerManager.initializationData?.prepareProvider ?? false
      {
        let semanticIndexManager = SemanticIndexManager(
          index: uncheckedIndex,
          buildServerManager: buildServerManager,
          updateIndexStoreTimeout: options.indexOrDefault.updateIndexStoreTimeoutOrDefault,
          hooks: hooks.indexHooks,
          indexTaskScheduler: indexTaskScheduler,
          preparationBatchingStrategy: options.preparationBatchingStrategy,
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
        await semanticIndexManager.scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(
          indexFilesWithUpToDateUnit: false
        )
        return semanticIndexManager
      } else {
        return nil
      }
    }
    // Trigger an initial population of `syntacticIndex`.
    self.syntacticIndex = SyntacticIndex(
      determineFilesToScan: { targets in
        await orLog("Getting list of files for syntactic index population") {
          try await buildServerManager.projectSourceFiles(in: targets).compactMap { ($0, $1) }
        } ?? []
      },
      syntacticTests: { [weak self] (snapshot) in
        guard let self else {
          return []
        }
        return await sourceKitLSPServer.languageServices(for: snapshot.uri, snapshot.language, in: self).asyncFlatMap {
          await $0.syntacticTestItems(for: snapshot)
        }
      },
      syntacticPlaygrounds: { [weak self] (snapshot) in
        guard let self,
          let toolchain = await sourceKitLSPServer.toolchainRegistry.preferredToolchain(containing: [\.swiftc]),
          toolchain.swiftPlay != nil
        else {
          return []
        }
        return await sourceKitLSPServer.languageServices(for: snapshot.uri, snapshot.language, in: self).asyncFlatMap {
          await $0.syntacticPlaygrounds(for: snapshot, in: self)
        }
      }
    )
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

      func logMessageToIndexLog(
        message: String,
        type: WindowMessageType,
        structure: LanguageServerProtocol.StructuredLogKind?
      ) {
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
      buildServerHooks: hooks.buildServerHooks,
      createMainFilesProvider: { (initializationData, mainFilesChangedCallback) -> (any MainFilesProvider)? in
        await createIndex(
          initializationData: initializationData,
          mainFilesChangedCallback: mainFilesChangedCallback,
          rootUri: rootUri,
          toolchainRegistry: toolchainRegistry,
          options: options,
          hooks: hooks
        )
      }
    )

    logger.log(
      "Created workspace at \(rootUri.forLogging) with project root \(buildServerSpec?.projectRoot.description ?? "<nil>")"
    )

    await self.init(
      sourceKitLSPServer: sourceKitLSPServer,
      rootUri: rootUri,
      capabilityRegistry: capabilityRegistry,
      options: options,
      hooks: hooks,
      buildServerManager: buildServerManager,
      indexTaskScheduler: indexTaskScheduler
    )
    await buildServerManager.setDelegate(self)

    // Populate the initial list of unit output paths in the index.
    await scheduleUpdateOfUnitOutputPathsInIndexIfNecessary()
  }

  /// Returns a `CheckedIndex` that verifies that all the returned entries are up-to-date with the given
  /// `IndexCheckLevel`.
  package func index(checkedFor checkLevel: IndexCheckLevel) async -> CheckedIndex? {
    return await uncheckedIndex?.checked(for: checkLevel)
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

    let eventsWithSourceFileInfo: [(FileEvent, SourceFileInfo)] = await events.asyncCompactMap {
      guard let sourceFileInfo = await buildServerManager.sourceFileInfo(for: $0.uri) else {
        return nil
      }
      return ($0, sourceFileInfo)
    }

    async let updateSyntacticIndex: Void = await syntacticIndex.filesDidChange(eventsWithSourceFileInfo)
    async let updateSemanticIndex: Void? = await semanticIndexManager?.filesDidChange(events)
    _ = await (updateSyntacticIndex, updateSemanticIndex)
  }

  /// The language services that can handle the given document. Callers should try to merge the results from the
  /// different language service or prefer results from language services that occur earlier in this array, whichever is
  /// more suitable.
  func languageServices(for uri: DocumentURI) -> [any LanguageService] {
    return languageServices.value[uri.buildSettingsFile] ?? []
  }

  /// The language service with the highest precedence that can handle the given document.
  func primaryLanguageService(for uri: DocumentURI) -> (any LanguageService)? {
    return languageServices(for: uri).first
  }

  /// Set a language service for a document uri and returns if none exists already.
  ///
  /// If language services already exist for this document, eg. because two requests start creating a language
  /// service for a document and race, `newLanguageServices` is dropped and the existing language services for the
  /// document are returned.
  func setLanguageServices(for uri: DocumentURI, _ newLanguageService: [any LanguageService]) -> [any LanguageService] {
    return languageServices.withLock { languageServices in
      if let languageService = languageServices[uri] {
        return languageService
      }

      languageServices[uri] = newLanguageService
      return newLanguageService
    }
  }

  /// Handle a build settings change notification from the build serveer.
  /// This has two primary cases:
  /// - Initial settings reported for a given file, now we can fully open it
  /// - Changed settings for an already open file
  package func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    for uri in changedFiles {
      for languageService in languageServices(for: uri) {
        await languageService.documentUpdatedBuildSettings(uri)
      }
    }
  }

  /// Handle a dependencies updated notification from the build server.
  /// We inform the respective language services as long as the given file is open
  /// (not queued for opening).
  package func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) async {
    var documentsByService: [ObjectIdentifier: (Set<DocumentURI>, any LanguageService)] = [:]
    for uri in changedFiles {
      logger.log("Dependencies updated for file \(uri.forLogging)")
      for languageService in languageServices(for: uri) {
        documentsByService[ObjectIdentifier(languageService), default: ([], languageService)].0.insert(uri)
      }
    }
    for (documents, service) in documentsByService.values {
      await service.documentDependenciesUpdated(documents)
    }
  }

  package func buildTargetsChanged(_ changedTargets: Set<BuildTargetIdentifier>?) async {
    await sourceKitLSPServer?.fileHandlingCapabilityChanged()
    await semanticIndexManager?.buildTargetsChanged(changedTargets)
    await orLog("Scheduling syntactic file re-indexing") {
      await syntacticIndex.buildTargetsChanged(changedTargets)
    }

    await scheduleUpdateOfUnitOutputPathsInIndexIfNecessary()
  }

  private func scheduleUpdateOfUnitOutputPathsInIndexIfNecessary() async {
    indexUnitOutputPathsUpdateQueue.async {
      guard await self.uncheckedIndex?.usesExplicitOutputPaths ?? false else {
        return
      }
      guard await self.buildServerManager.initializationData?.outputPathsProvider ?? false else {
        // This can only happen if an index got injected that uses explicit output paths but the build server does not
        // support output paths.
        logger.error("The index uses explicit output paths but the build server does not support output paths")
        return
      }
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
    if request.copyFileMap ?? false {
      // Not using `valuePropagatingCancellation` here because that could lead us to the following scenario:
      //  - An update of the copy file map is scheduled because of a change in the build graph
      //  - We get a synchronize request
      //  - Scheduling a new recomputation of the copy file map cancels the previous recomputation
      //  - We cancel the synchronize request, which would also cancel the copy file map recomputation, leaving us with
      //    an outdated version
      //
      // Technically, we might be doing unnecessary work here if the output file map is already up-to-date. But since
      // this option is mostly intended for testing purposes, this is acceptable.
      await buildServerManager.scheduleRecomputeCopyFileMap().value
    }
    if request.index ?? false {
      if let semanticIndexManager = await semanticIndexManager {
        await semanticIndexManager.waitForUpToDateIndex()
      } else {
        logger.debug("Skipping wait for background index in synchronize as it's disabled")

        // Might have index while building, so still need to poll for any changes
        await uncheckedIndex?.pollForUnitChangesAndWait()
      }
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
