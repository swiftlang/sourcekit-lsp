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

#if compiler(>=6)
package import BuildServerProtocol
package import BuildSystemIntegration
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
package import SKOptions
package import SemanticIndex
import SwiftExtensions
import ToolchainRegistry
import TSCExtensions

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath
#else
import BuildServerProtocol
import BuildSystemIntegration
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import SemanticIndex
import SwiftExtensions
import ToolchainRegistry
import TSCExtensions

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath
#endif

/// Actor that caches realpaths for `sourceFilesWithSameRealpath`.
fileprivate actor SourceFilesWithSameRealpathInferrer {
  private let buildSystemManager: BuildSystemManager
  private var realpathCache: [DocumentURI: DocumentURI] = [:]

  init(buildSystemManager: BuildSystemManager) {
    self.buildSystemManager = buildSystemManager
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
      let filesAndDirectories = try await buildSystemManager.sourceFiles(includeNonBuildableFiles: true)
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
package final class Workspace: Sendable, BuildSystemManagerDelegate {
  /// The ``SourceKitLSPServer`` instance that created this `Workspace`.
  private(set) weak nonisolated(unsafe) var sourceKitLSPServer: SourceKitLSPServer? {
    didSet {
      preconditionFailure("sourceKitLSPServer must not be modified. It is only a var because it is weak")
    }
  }

  /// The root directory of the workspace.
  package let rootUri: DocumentURI?

  /// Tracks dynamically registered server capabilities as well as the client's capabilities.
  package let capabilityRegistry: CapabilityRegistry

  /// The build system manager to use for documents in this workspace.
  package let buildSystemManager: BuildSystemManager

  private let sourceFilesWithSameRealpathInferrer: SourceFilesWithSameRealpathInferrer

  let options: SourceKitLSPOptions

  /// The source code index, if available.
  ///
  /// Usually a checked index (retrieved using `index(checkedFor:)`) should be used instead of the unchecked index.
  private let _uncheckedIndex: ThreadSafeBox<UncheckedIndex?>

  package var uncheckedIndex: UncheckedIndex? {
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
  let semanticIndexManager: SemanticIndexManager?

  private init(
    sourceKitLSPServer: SourceKitLSPServer?,
    rootUri: DocumentURI?,
    capabilityRegistry: CapabilityRegistry,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    buildSystemManager: BuildSystemManager,
    index uncheckedIndex: UncheckedIndex?,
    indexDelegate: SourceKitIndexDelegate?,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.rootUri = rootUri
    self.capabilityRegistry = capabilityRegistry
    self.options = options
    self._uncheckedIndex = ThreadSafeBox(initialValue: uncheckedIndex)
    self.buildSystemManager = buildSystemManager
    self.sourceFilesWithSameRealpathInferrer = SourceFilesWithSameRealpathInferrer(
      buildSystemManager: buildSystemManager
    )
    if options.backgroundIndexingOrDefault, let uncheckedIndex,
      await buildSystemManager.initializationData?.prepareProvider ?? false
    {
      self.semanticIndexManager = SemanticIndexManager(
        index: uncheckedIndex,
        buildSystemManager: buildSystemManager,
        updateIndexStoreTimeout: options.indexOrDefault.updateIndexStoreTimeoutOrDefault,
        hooks: hooks.indexHooks,
        indexTaskScheduler: indexTaskScheduler,
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
    self.syntacticTestIndex = SyntacticTestIndex(determineTestFiles: {
      await orLog("Getting list of test files for initial syntactic index population") {
        try await buildSystemManager.testFiles()
      } ?? []
    })
    await indexDelegate?.addMainFileChangedCallback { [weak self] in
      await self?.buildSystemManager.mainFilesChanged()
    }
    if let semanticIndexManager {
      await semanticIndexManager.scheduleBuildGraphGenerationAndBackgroundIndexAllFiles(
        filesToIndex: nil,
        ensureAllUnitsRegisteredInIndex: true,
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
    buildSystemSpec: BuildSystemSpec?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async {
    struct ConnectionToClient: BuildSystemManagerConnectionToClient {
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

    let buildSystemManager = await BuildSystemManager(
      buildSystemSpec: buildSystemSpec,
      toolchainRegistry: toolchainRegistry,
      options: options,
      connectionToClient: ConnectionToClient(sourceKitLSPServer: sourceKitLSPServer),
      buildSystemHooks: hooks.buildSystemHooks
    )

    logger.log(
      "Created workspace at \(rootUri.forLogging) with project root \(buildSystemSpec?.projectRoot.description ?? "<nil>")"
    )

    var indexDelegate: SourceKitIndexDelegate? = nil

    let indexOptions = options.indexOrDefault
    let indexStorePath: URL? =
      if let indexStorePath = await buildSystemManager.initializationData?.indexStorePath {
        URL(fileURLWithPath: indexStorePath, relativeTo: rootUri?.fileURL)
      } else {
        nil
      }
    let indexDatabasePath: URL? =
      if let indexDatabasePath = await buildSystemManager.initializationData?.indexDatabasePath {
        URL(fileURLWithPath: indexDatabasePath, relativeTo: rootUri?.fileURL)
      } else {
        nil
      }
    let supportsOutputPaths = await buildSystemManager.initializationData?.outputPathsProvider ?? false
    var index: UncheckedIndex? = nil
    if let indexStorePath, let indexDatabasePath, let libPath = await toolchainRegistry.default?.libIndexStore {
      do {
        indexDelegate = SourceKitIndexDelegate()
        let prefixMappings =
          (indexOptions.indexPrefixMap ?? [:])
          .map { PathMapping(original: $0.key, replacement: $0.value) }
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
        logger.error("Failed to open IndexStoreDB: \(error.localizedDescription)")
      }
    }

    await buildSystemManager.setMainFilesProvider(index)

    await self.init(
      sourceKitLSPServer: sourceKitLSPServer,
      rootUri: rootUri,
      capabilityRegistry: capabilityRegistry,
      options: options,
      hooks: hooks,
      buildSystemManager: buildSystemManager,
      index: index,
      indexDelegate: indexDelegate,
      indexTaskScheduler: indexTaskScheduler
    )
    await buildSystemManager.setDelegate(self)
  }

  package static func forTesting(
    options: SourceKitLSPOptions,
    testHooks: Hooks,
    buildSystemManager: BuildSystemManager,
    indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>
  ) async -> Workspace {
    return await Workspace(
      sourceKitLSPServer: nil,
      rootUri: nil,
      capabilityRegistry: CapabilityRegistry(clientCapabilities: ClientCapabilities()),
      options: options,
      hooks: testHooks,
      buildSystemManager: buildSystemManager,
      index: nil,
      indexDelegate: nil,
      indexTaskScheduler: indexTaskScheduler
    )
  }

  /// Returns a `CheckedIndex` that verifies that all the returned entries are up-to-date with the given
  /// `IndexCheckLevel`.
  func index(checkedFor checkLevel: IndexCheckLevel) -> CheckedIndex? {
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
    await buildSystemManager.filesDidChange(events)
    await syntacticTestIndex.filesDidChange(events)
    await semanticIndexManager?.filesDidChange(events)
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

  /// Handle a build settings change notification from the `BuildSystem`.
  /// This has two primary cases:
  /// - Initial settings reported for a given file, now we can fully open it
  /// - Changed settings for an already open file
  package func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    for uri in changedFiles {
      await self.documentService(for: uri)?.documentUpdatedBuildSettings(uri)
    }
  }

  /// Handle a dependencies updated notification from the `BuildSystem`.
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
      let testFiles = try await buildSystemManager.testFiles()
      await syntacticTestIndex.listOfTestFilesDidChange(testFiles)
    }

    if await self.uncheckedIndex?.usesExplicitOutputPaths ?? false {
      if await buildSystemManager.initializationData?.outputPathsProvider ?? false {
        await orLog("Setting new list of unit output paths") {
          try await self.uncheckedIndex?.setUnitOutputPaths(Set(buildSystemManager.outputPathInAllTargets()))
        }
      } else {
        // This can only happen if an index got injected that uses explicit output paths but the build system does not
        // support output paths.
        logger.error("The index uses explicit output paths but the build system does not support output paths")
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
}

/// Wrapper around a workspace that isn't being retained.
struct WeakWorkspace {
  weak var value: Workspace?

  init(_ value: Workspace? = nil) {
    self.value = value
  }
}
