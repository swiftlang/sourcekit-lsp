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
  indexChangedCallback: @escaping @Sendable () async -> Void,
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
      let indexDelegate = SourceKitIndexDelegate(callback: indexChangedCallback)
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
  let hooks: Hooks
  let languageServiceRegistry: LanguageServiceRegistry

  /// Language service instances owned by this workspace, keyed by service type.
  private let languageServiceInstances: ThreadSafeBox<[LanguageServiceType: [any LanguageService]]> =
    ThreadSafeBox(initialValue: [:])

  /// The source code index, if available.
  ///
  /// Usually a checked index (retrieved using `index(checkedFor:)`) should be used instead of the unchecked index.
  package var uncheckedIndex: UncheckedIndex? {
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
    return languageServiceInstances.value.values.flatMap { $0 }
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
    languageServiceRegistry: LanguageServiceRegistry,
    buildServerManager: BuildServerManager,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.rootUri = rootUri
    self.capabilityRegistry = capabilityRegistry
    self.options = options
    self.hooks = hooks
    self.languageServiceRegistry = languageServiceRegistry
    self.buildServerManager = buildServerManager
    self.sourceFilesWithSameRealpathInferrer = SourceFilesWithSameRealpathInferrer(
      buildServerManager: buildServerManager
    )
    self.semanticIndexManagerTask = Task { [weak sourceKitLSPServer] in
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
          logMessageToIndexLog: {
            sourceKitLSPServer?.logMessageToIndexLog(message: $0, type: $1, structure: $2)
          },
          indexTasksWereScheduled: {
            sourceKitLSPServer?.indexProgressManager.indexTasksWereScheduled(count: $0)
          },
          indexProgressStatusDidChange: {
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
        return await self.languageServices(for: snapshot.uri, snapshot.language).asyncFlatMap {
          await $0.syntacticTestItems(for: snapshot) ?? []
        }
      },
      syntacticPlaygrounds: { [weak self] (snapshot) in
        guard let self,
          let toolchain = await sourceKitLSPServer.toolchainRegistry.preferredToolchain(containing: [\.swiftc]),
          toolchain.swiftPlay != nil
        else {
          return []
        }
        return await self.languageServices(for: snapshot.uri, snapshot.language).asyncFlatMap {
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
    languageServiceRegistry: LanguageServiceRegistry,
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
      createMainFilesProvider: {
        [weak sourceKitLSPServer] (initializationData, mainFilesChangedCallback) -> (any MainFilesProvider)? in
        await createIndex(
          initializationData: initializationData,
          indexChangedCallback: {
            // Notify that main files may have changed.
            await mainFilesChangedCallback()

            // Schedule updating entry point cache.
            // Set the debounce duration so rapid repeated calls won't start/cancel the task often.
            await sourceKitLSPServer?.entryPointManager.refresh(debounce: true)
          },
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
      languageServiceRegistry: languageServiceRegistry,
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

    async let updateSyntacticIndex = syntacticIndex.filesDidChange(eventsWithSourceFileInfo)
    async let updateSemanticIndex = semanticIndexManager?.filesDidChange(events)
    async let updateLanguageServices = allLanguageServices.concurrentForEach { [events] in
      await $0.filesDidChange(events)
    }
    _ = await (updateSyntacticIndex, updateSemanticIndex, updateLanguageServices)
  }

  // MARK: - Language service management

  /// Returns an existing service instance of the given type that can handle the given toolchain, or `nil`.
  private func existingLanguageService(
    _ serviceType: any LanguageService.Type,
    toolchain: Toolchain
  ) -> (any LanguageService)? {
    languageServiceInstances.value[LanguageServiceType(serviceType)]?.first {
      $0.canHandle(toolchain: toolchain)
    }
  }

  /// Get or create service instances for the given toolchain and language.
  ///
  /// Within the workspace, one service instance is reused for all documents that share the same
  /// toolchain, determined by `LanguageService.canHandle(toolchain:)`.
  private func languageServicesForToolchain(
    _ toolchain: Toolchain,
    _ language: Language
  ) async -> [any LanguageService] {
    guard let sourceKitLSPServer else { return [] }
    var result: [any LanguageService] = []
    for serviceType in languageServiceRegistry.languageServices(for: language) {
      if let service = existingLanguageService(serviceType, toolchain: toolchain) {
        result.append(service)
        continue
      }

      // Start a new service.
      let service: (any LanguageService)? = await orLog("Failed to start language service") {
        let svc = try await serviceType.init(
          sourceKitLSPServer: sourceKitLSPServer,
          toolchain: toolchain,
          options: options,
          hooks: hooks,
          workspace: self
        )

        if let concurrent = existingLanguageService(serviceType, toolchain: toolchain) {
          // Since we 'await' above, another call may have concurrently passed the
          // `existingLanguageService` check and started the same service. Shut down the
          // duplicate and return the one that won the race.
          await svc.shutdown()
          return concurrent
        }

        languageServiceInstances.withLock { $0[LanguageServiceType(serviceType), default: []].append(svc) }
        return svc
      }
      guard let service else {
        // If a language service fails to start, don't try starting language services with lower
        // precedence. Otherwise we get into a situation where e.g. `SwiftLanguageService` fails
        // to start (because the toolchain doesn't contain sourcekitd) and
        // `DocumentationLanguageService` becomes the primary service for Swift documents.
        break
      }
      result.append(service)
    }
    if result.isEmpty {
      logger.error("Unable to infer language server type for language '\(language)'")
    }
    return result
  }

  /// Find or create language services for the given URI and language.
  ///
  /// Use this only when the document may not have been opened yet (e.g. in `openDocument` itself,
  /// or for requests that can target non-open files). Do not use this as a substitute for the sync
  /// overload in document-lifecycle handlers.
  package func languageServices(
    for uri: DocumentURI,
    _ language: Language
  ) async -> [any LanguageService] {
    let cached = languageServices.value[uri.buildSettingsFile]
    if let cached, !cached.isEmpty {
      return cached
    }

    let toolchain = await buildServerManager.toolchain(
      for: await buildServerManager.canonicalTarget(for: uri),
      language: language
    )
    guard let toolchain else {
      logger.error("Failed to determine toolchain for \(uri)")
      return []
    }

    let services = await languageServicesForToolchain(toolchain, language)

    if services.isEmpty {
      logger.error("No language service found to handle \(uri.forLogging)")
    } else {
      logger.log(
        """
        Using toolchain at \(toolchain.path.description) (\(toolchain.identifier, privacy: .public)) \
        for \(uri.forLogging)
        """
      )
    }

    return services
  }

  /// Find or create the primary language service for the given URI and language.
  ///
  /// Convenience wrapper around `languageServices(for:_:)` that throws if no service is available.
  /// Use this only when the document may not have been opened yet.
  package func primaryLanguageService(
    for uri: DocumentURI,
    _ language: Language
  ) async throws -> any LanguageService {
    guard let service = await languageServices(for: uri, language).first else {
      throw ResponseError.unknown("No language service found for \(uri)")
    }
    return service
  }

  /// The language services for an open document.
  ///
  /// Returns the services established when the document was opened. Returns an empty array if the
  /// document has not been opened or has already been closed. Use this for document-lifecycle
  /// operations (change, save, close, diagnostics, etc.) where the document is known to be open.
  ///
  /// Callers should try to merge the results from the different language services or prefer results
  /// from language services that occur earlier in this array, whichever is more suitable.
  package func languageServices(for uri: DocumentURI) -> [any LanguageService] {
    return languageServices.value[uri.buildSettingsFile] ?? []
  }

  /// The primary language service for an open document.
  ///
  /// Convenience wrapper around the sync `languageServices(for:)`. Returns `nil` if the document
  /// has not been opened or has already been closed.
  package func primaryLanguageService(for uri: DocumentURI) -> (any LanguageService)? {
    return languageServices(for: uri).first
  }

  /// Set the language services for a document URI.
  ///
  /// This should only be called from `openDocument` to ensure there are no race conditions.
  func setLanguageServices(for uri: DocumentURI, _ newLanguageService: [any LanguageService]) {
    languageServices.withLock { languageServices in
      languageServices[uri.buildSettingsFile] = newLanguageService
    }
  }

  /// Remove the language services association for a document when it is closed.
  ///
  /// If any other open document shares the same build-settings file as `uri`, the language service
  /// is still in use and will not be removed.
  func removeLanguageServices(for uri: DocumentURI) {
    let key = uri.buildSettingsFile
    let openDocuments = sourceKitLSPServer?.documentManager.openDocuments ?? []
    guard !openDocuments.contains(where: { $0.buildSettingsFile == key }) else {
      return
    }
    languageServices.withLock { languageServices in
      languageServices[key] = nil
    }
  }

  func shutdown() async {
    logger.info("Shutting down workspace \(self.rootUri?.description ?? "<nil>")")
    async let languageServiceShutdown = shutdownAllLanguageServices()
    async let buildServerShutdown = buildServerManager.shutdown()
    async let indexClose = uncheckedIndex?.close()
    _ = await (languageServiceShutdown, buildServerShutdown, indexClose)
  }

  /// Shut down all language service instances owned by this workspace.
  private func shutdownAllLanguageServices() async {
    let services = languageServiceInstances.withLock { instances in
      let services = Array(instances.values.flatMap { $0 })
      instances = [:]
      return services
    }
    await services.concurrentForEach { await $0.shutdown() }
  }

  /// Handle a build settings change notification from the build server.
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

    // Schedule updating entry point cache.
    await sourceKitLSPServer?.entryPointManager.refresh()
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
      _ = await buildServerManager.scheduleRecomputeCopyFileMap().value
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
