//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if compiler(>=6)
package import BuildServerProtocol
import Dispatch
package import Foundation
package import LanguageServerProtocol
package import LanguageServerProtocolExtensions
import SKLogging
package import SKOptions
import SKUtilities
package import SwiftExtensions
package import ToolchainRegistry
import TSCExtensions

import struct TSCBasic.RelativePath
#else
import BuildServerProtocol
import Dispatch
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import SKUtilities
import SwiftExtensions
import ToolchainRegistry
import TSCExtensions

import struct TSCBasic.RelativePath
#endif

fileprivate typealias RequestCache<Request: RequestType & Hashable> = Cache<Request, Request.Response>

package struct SourceFileInfo: Sendable {
  /// The targets that this source file is a member of
  package var targets: Set<BuildTargetIdentifier>

  /// `true` if this file belongs to the root project that the user is working on. It is false, if the file belongs
  /// to a dependency of the project.
  package var isPartOfRootProject: Bool

  /// Whether the file might contain test cases. This property is an over-approximation. It might be true for files
  /// from non-test targets or files that don't actually contain any tests.
  package var mayContainTests: Bool

  fileprivate func merging(_ other: SourceFileInfo?) -> SourceFileInfo {
    guard let other else {
      return self
    }
    return SourceFileInfo(
      targets: targets.union(other.targets),
      isPartOfRootProject: other.isPartOfRootProject || isPartOfRootProject,
      mayContainTests: other.mayContainTests || mayContainTests
    )
  }
}

private struct BuildTargetInfo {
  /// The build target itself.
  var target: BuildTarget

  /// The maximum depth at which this target occurs at the build graph, ie. the number of edges on the longest path
  /// from this target to a root target (eg. an executable)
  var depth: Int

  /// The targets that depend on this target, ie. the inverse of `BuildTarget.dependencies`.
  var dependents: Set<BuildTargetIdentifier>
}

fileprivate extension SourceItem {
  var sourceKitData: SourceKitSourceItemData? {
    guard dataKind == .sourceKit else {
      return nil
    }
    return SourceKitSourceItemData(fromLSPAny: data)
  }
}

fileprivate extension BuildTarget {
  var sourceKitData: SourceKitBuildTarget? {
    guard dataKind == .sourceKit else {
      return nil
    }
    return SourceKitBuildTarget(fromLSPAny: data)
  }
}

fileprivate extension InitializeBuildResponse {
  var sourceKitData: SourceKitInitializeBuildResponseData? {
    guard dataKind == nil || dataKind == .sourceKit else {
      return nil
    }
    return SourceKitInitializeBuildResponseData(fromLSPAny: data)
  }
}

/// A build system adapter is responsible for receiving messages from the `BuildSystemManager` and forwarding them to
/// the build system. For built-in build systems, this means that we need to translate the BSP messages to methods in
/// the `BuiltInBuildSystem` protocol. For external (aka. out-of-process, aka. BSP servers) build systems, this means
/// that we need to manage the external build system's lifetime.
private enum BuildSystemAdapter {
  case builtIn(BuiltInBuildSystemAdapter, connectionToBuildSystem: any Connection)
  case external(ExternalBuildSystemAdapter)

  /// Send a notification to the build server.
  func send(_ notification: some NotificationType) async {
    switch self {
    case .builtIn(_, let connectionToBuildSystem):
      connectionToBuildSystem.send(notification)
    case .external(let external):
      await external.send(notification)
    }
  }

  /// Send a request to the build server.
  func send<Request: RequestType>(_ request: Request) async throws -> Request.Response {
    switch self {
    case .builtIn(_, let connectionToBuildSystem):
      return try await connectionToBuildSystem.send(request)
    case .external(let external):
      return try await external.send(request)
    }
  }
}

private extension BuildSystemSpec {
  private static func createBuiltInBuildSystemAdapter(
    projectRoot: URL,
    messagesToSourceKitLSPHandler: any MessageHandler,
    buildSystemTestHooks: BuildSystemTestHooks,
    _ createBuildSystem: @Sendable (_ connectionToSourceKitLSP: any Connection) async throws -> BuiltInBuildSystem?
  ) async -> BuildSystemAdapter? {
    let connectionToSourceKitLSP = LocalConnection(
      receiverName: "BuildSystemManager for \(projectRoot.lastPathComponent)"
    )
    connectionToSourceKitLSP.start(handler: messagesToSourceKitLSPHandler)

    let buildSystem = await orLog("Creating build system") {
      try await createBuildSystem(connectionToSourceKitLSP)
    }
    guard let buildSystem else {
      logger.log("Failed to create build system at \(projectRoot)")
      return nil
    }
    logger.log("Created \(type(of: buildSystem), privacy: .public) at \(projectRoot)")
    let buildSystemAdapter = BuiltInBuildSystemAdapter(
      underlyingBuildSystem: buildSystem,
      connectionToSourceKitLSP: connectionToSourceKitLSP,
      buildSystemTestHooks: buildSystemTestHooks
    )
    let connectionToBuildSystem = LocalConnection(
      receiverName: "\(type(of: buildSystem)) for \(projectRoot.lastPathComponent)"
    )
    connectionToBuildSystem.start(handler: buildSystemAdapter)
    return .builtIn(buildSystemAdapter, connectionToBuildSystem: connectionToBuildSystem)
  }

  /// Create a `BuildSystemAdapter` that manages a build system of this kind and return a connection that can be used
  /// to send messages to the build system.
  func createBuildSystemAdapter(
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    buildSystemTestHooks testHooks: BuildSystemTestHooks,
    messagesToSourceKitLSPHandler: any MessageHandler
  ) async -> BuildSystemAdapter? {
    switch self.kind {
    case .buildServer:
      let buildSystem = await orLog("Creating external build system") {
        try await ExternalBuildSystemAdapter(
          projectRoot: projectRoot,
          messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler
        )
      }
      guard let buildSystem else {
        logger.log("Failed to create external build system at \(projectRoot)")
        return nil
      }
      logger.log("Created external build server at \(projectRoot)")
      return .external(buildSystem)
    case .compilationDatabase:
      return await Self.createBuiltInBuildSystemAdapter(
        projectRoot: projectRoot,
        messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler,
        buildSystemTestHooks: testHooks
      ) { connectionToSourceKitLSP in
        CompilationDatabaseBuildSystem(
          projectRoot: projectRoot,
          searchPaths: (options.compilationDatabaseOrDefault.searchPaths ?? []).compactMap {
            try? RelativePath(validating: $0)
          },
          connectionToSourceKitLSP: connectionToSourceKitLSP
        )
      }
    case .swiftPM:
      return await Self.createBuiltInBuildSystemAdapter(
        projectRoot: projectRoot,
        messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler,
        buildSystemTestHooks: testHooks
      ) { connectionToSourceKitLSP in
        try await SwiftPMBuildSystem(
          projectRoot: projectRoot,
          toolchainRegistry: toolchainRegistry,
          options: options,
          connectionToSourceKitLSP: connectionToSourceKitLSP,
          testHooks: testHooks.swiftPMTestHooks
        )
      }
    case .testBuildSystem:
      return await Self.createBuiltInBuildSystemAdapter(
        projectRoot: projectRoot,
        messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler,
        buildSystemTestHooks: testHooks
      ) { connectionToSourceKitLSP in
        TestBuildSystem(projectRoot: projectRoot, connectionToSourceKitLSP: connectionToSourceKitLSP)
      }
    }
  }
}

/// Entry point for all build system queries.
package actor BuildSystemManager: QueueBasedMessageHandler {
  package let messageHandlingHelper = QueueBasedMessageHandlerHelper(
    signpostLoggingCategory: "build-system-manager-message-handling",
    createLoggingScope: false
  )

  package let messageHandlingQueue = AsyncQueue<BuildSystemMessageDependencyTracker>()

  /// The root of the project that this build system manages.
  ///
  /// For example, in SwiftPM packages this is the folder containing Package.swift.
  /// For compilation databases it is the root folder based on which the compilation database was found.
  ///
  /// `nil` if the `BuildSystemManager` does not have an underlying build system.
  package let projectRoot: URL?

  /// The files for which the delegate has requested change notifications, ie. the files for which the delegate wants to
  /// get `fileBuildSettingsChanged` and `filesDependenciesUpdated` callbacks.
  private var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  private var connectionToClient: BuildSystemManagerConnectionToClient

  /// The build system adapter that is used to answer build system queries.
  private var buildSystemAdapter: BuildSystemAdapter?

  /// The build system adapter after initialization finishes. When sending messages to the BSP server, this should be
  /// preferred over `buildSystemAdapter` because no messages must be sent to the build server before initialization
  /// finishes.
  private var buildSystemAdapterAfterInitialized: BuildSystemAdapter? {
    get async {
      _ = await initializeResult.value
      return buildSystemAdapter
    }
  }

  /// If the underlying build system is a `TestBuildSystem`, return it. Otherwise, `nil`
  ///
  /// - Important: For testing purposes only.
  package var testBuildSystem: TestBuildSystem? {
    get async {
      switch buildSystemAdapter {
      case .builtIn(let builtInBuildSystemAdapter, _): return await builtInBuildSystemAdapter.testBuildSystem
      case .external: return nil
      case nil: return nil
      }
    }
  }

  /// Provider of file to main file mappings.
  private var mainFilesProvider: MainFilesProvider?

  /// Build system delegate that will receive notifications about setting changes, etc.
  private weak var delegate: BuildSystemManagerDelegate?

  /// The list of toolchains that are available.
  ///
  /// Used to determine which toolchain to use for a given document.
  private let toolchainRegistry: ToolchainRegistry

  private let options: SourceKitLSPOptions

  /// A task that stores the result of the `build/initialize` request once it is received.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private var initializeResult: Task<InitializeBuildResponse?, Never>! {
    didSet {
      // Must only be set once
      precondition(oldValue == nil)
      precondition(initializeResult != nil)
    }
  }

  /// For tasks from the build system that should create a work done progress in the client, a mapping from the `TaskId`
  /// in the build system to a `WorkDoneProgressManager` that manages that work done progress in the client.
  private var workDoneProgressManagers: [TaskIdentifier: WorkDoneProgressManager] = [:]

  /// Debounces calls to `delegate.filesDependenciesUpdated`.
  ///
  /// This is to ensure we don't call `filesDependenciesUpdated` for the same file multiple time if the client does not
  /// debounce `workspace/didChangeWatchedFiles` and sends a separate notification eg. for every file within a target as
  /// it's being updated by a git checkout, which would cause other files within that target to receive a
  /// `fileDependenciesUpdated` call once for every updated file within the target.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private var filesDependenciesUpdatedDebouncer: Debouncer<Set<DocumentURI>>! = nil {
    didSet {
      // Must only be set once
      precondition(oldValue == nil)
      precondition(filesDependenciesUpdatedDebouncer != nil)
    }
  }

  private var cachedSourceKitOptions = RequestCache<TextDocumentSourceKitOptionsRequest>()

  private var cachedBuildTargets = Cache<WorkspaceBuildTargetsRequest, [BuildTargetIdentifier: BuildTargetInfo]>()

  private var cachedTargetSources = RequestCache<BuildTargetSourcesRequest>()

  /// The parameters with which `SourceFilesAndDirectories` can be cached in `cachedSourceFilesAndDirectories`.
  private struct SourceFilesAndDirectoriesKey: Hashable {
    let includeNonBuildableFiles: Bool
    let sourcesItems: [SourcesItem]
  }

  private struct SourceFilesAndDirectories {
    /// The source files in the workspace, ie. all `SourceItem`s that have `kind == .file`.
    let files: [DocumentURI: SourceFileInfo]

    /// The source directories in the workspace, ie. all `SourceItem`s that have `kind == .directory`.
    let directories: [DocumentURI: SourceFileInfo]
  }

  private let cachedSourceFilesAndDirectories = Cache<SourceFilesAndDirectoriesKey, SourceFilesAndDirectories>()

  /// The `SourceKitInitializeBuildResponseData` received from the `build/initialize` request, if any.
  package var initializationData: SourceKitInitializeBuildResponseData? {
    get async {
      return await initializeResult.value?.sourceKitData
    }
  }

  package init(
    buildSystemSpec: BuildSystemSpec?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    connectionToClient: BuildSystemManagerConnectionToClient,
    buildSystemTestHooks: BuildSystemTestHooks
  ) async {
    self.toolchainRegistry = toolchainRegistry
    self.options = options
    self.connectionToClient = connectionToClient
    self.projectRoot = buildSystemSpec?.projectRoot
    self.buildSystemAdapter = await buildSystemSpec?.createBuildSystemAdapter(
      toolchainRegistry: toolchainRegistry,
      options: options,
      buildSystemTestHooks: buildSystemTestHooks,
      messagesToSourceKitLSPHandler: WeakMessageHandler(self)
    )

    // The debounce duration of 500ms was chosen arbitrarily without any measurements.
    self.filesDependenciesUpdatedDebouncer = Debouncer(
      debounceDuration: .milliseconds(500),
      combineResults: { $0.union($1) }
    ) {
      [weak self] (filesWithUpdatedDependencies) in
      guard let self, let delegate = await self.delegate else {
        logger.fault("Not calling filesDependenciesUpdated because no delegate exists in SwiftPMBuildSystem")
        return
      }
      let changedWatchedFiles = await self.watchedFilesReferencing(mainFiles: filesWithUpdatedDependencies)
      if !changedWatchedFiles.isEmpty {
        await delegate.filesDependenciesUpdated(changedWatchedFiles)
      }
    }

    // TODO: Forward file watch patterns from this initialize request to the client
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1671)
    initializeResult = Task { () -> InitializeBuildResponse? in
      guard let buildSystemAdapter else {
        return nil
      }
      guard let buildSystemSpec else {
        logger.fault("If we have a connectionToBuildSystem, we must have had a buildSystemSpec")
        return nil
      }
      let initializeResponse = await orLog("Initializing build system") {
        try await buildSystemAdapter.send(
          InitializeBuildRequest(
            displayName: "SourceKit-LSP",
            version: "",
            bspVersion: "2.2.0",
            rootUri: URI(buildSystemSpec.projectRoot),
            capabilities: BuildClientCapabilities(languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift])
          )
        )
      }
      if let initializeResponse, !(initializeResponse.sourceKitData?.sourceKitOptionsProvider ?? false),
        case .external(let externalBuildSystemAdapter) = buildSystemAdapter
      {
        // The BSP server does not support the pull-based settings model. Inject a `LegacyBuildServerBuildSystem` that
        // offers the pull-based model to `BuildSystemManager` and uses the push-based model to get build settings from
        // the build server.
        logger.log("Launched a legacy BSP server. Using push-based build settings model.")
        let legacyBuildServer = await LegacyBuildServerBuildSystem(
          projectRoot: buildSystemSpec.projectRoot,
          initializationData: initializeResponse,
          externalBuildSystemAdapter
        )
        let adapter = BuiltInBuildSystemAdapter(
          underlyingBuildSystem: legacyBuildServer,
          connectionToSourceKitLSP: legacyBuildServer.connectionToSourceKitLSP,
          buildSystemTestHooks: buildSystemTestHooks
        )
        let connectionToBuildSystem = LocalConnection(receiverName: "Legacy BSP server")
        connectionToBuildSystem.start(handler: adapter)
        self.buildSystemAdapter = .builtIn(adapter, connectionToBuildSystem: connectionToBuildSystem)
      }
      Task {
        var filesToWatch = initializeResponse?.sourceKitData?.watchers ?? []
        filesToWatch.append(FileSystemWatcher(globPattern: "**/*.swift", kind: [.change]))
        if !options.backgroundIndexingOrDefault {
          filesToWatch.append(FileSystemWatcher(globPattern: "**/*.swiftmodule", kind: [.create, .change, .delete]))
        }
        await connectionToClient.watchFiles(filesToWatch)
      }
      await buildSystemAdapter.send(OnBuildInitializedNotification())
      return initializeResponse
    }
  }

  /// Explicitly shut down the build server.
  ///
  /// The build server is automatically shut down using a background task when `BuildSystemManager` is deallocated.
  /// This, however, leads to possible race conditions where the shutdown task might not finish before the test is done,
  /// which could result in the connection being reported as a leak. To avoid this problem, we want to explicitly shut
  /// down the build server when the `SourceKitLSPServer` gets shut down.
  package func shutdown() async {
    // Clear any pending work done progresses from the build server.
    self.workDoneProgressManagers.removeAll()
    guard let buildSystemAdapter = await self.buildSystemAdapterAfterInitialized else {
      return
    }
    await orLog("Sending shutdown request to build server") {
      _ = try await buildSystemAdapter.send(BuildShutdownRequest())
      await buildSystemAdapter.send(OnBuildExitNotification())
    }
    self.buildSystemAdapter = nil
  }

  deinit {
    // Shut down the build server before closing the connection to it
    Task { [buildSystemAdapter, initializeResult] in
      guard let buildSystemAdapter else {
        return
      }
      // We are accessing the raw connection to the build server, so we need to ensure that it has been initialized here
      _ = await initializeResult?.value
      await orLog("Sending shutdown request to build server") {
        _ = try await buildSystemAdapter.send(BuildShutdownRequest())
        await buildSystemAdapter.send(OnBuildExitNotification())
      }
    }
  }

  /// - Note: Needed because `BuildSystemManager` is created before `Workspace` is initialized and `Workspace` needs to
  ///   create the `BuildSystemManager`, then initialize itself and then set itself as the delegate.
  package func setDelegate(_ delegate: BuildSystemManagerDelegate?) {
    self.delegate = delegate
  }

  /// - Note: Needed because we need the `indexStorePath` and `indexDatabasePath` from the build system to create an
  ///   IndexStoreDB, which serves as the `MainFilesProvider`. And thus this can't be set during initialization.
  package func setMainFilesProvider(_ mainFilesProvider: MainFilesProvider?) {
    self.mainFilesProvider = mainFilesProvider
  }

  // MARK: Handling messages from the build system

  package func handle(notification: some NotificationType) async {
    switch notification {
    case let notification as OnBuildTargetDidChangeNotification:
      await self.didChangeBuildTarget(notification: notification)
    case let notification as OnBuildLogMessageNotification:
      await self.logMessage(notification: notification)
    case let notification as TaskFinishNotification:
      await self.taskFinish(notification: notification)
    case let notification as TaskProgressNotification:
      await self.taskProgress(notification: notification)
    case let notification as TaskStartNotification:
      await self.taskStart(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method)")
    }
  }

  package func handle<Request: RequestType>(
    request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) async {
    let request = RequestAndReply(request, reply: reply)
    switch request {
    default:
      await request.reply { throw ResponseError.methodNotFound(Request.method) }
    }
  }

  private func didChangeBuildTarget(notification: OnBuildTargetDidChangeNotification) async {
    let updatedTargets: Set<BuildTargetIdentifier>? =
      if let changes = notification.changes {
        Set(changes.map(\.target))
      } else {
        nil
      }
    self.cachedSourceKitOptions.clear(isolation: self) { cacheKey in
      guard let updatedTargets else {
        // All targets might have changed
        return true
      }
      return updatedTargets.contains(cacheKey.target)
    }
    self.cachedBuildTargets.clearAll(isolation: self)
    self.cachedTargetSources.clear(isolation: self) { cacheKey in
      guard let updatedTargets else {
        // All targets might have changed
        return true
      }
      return !updatedTargets.intersection(cacheKey.targets).isEmpty
    }
    self.cachedSourceFilesAndDirectories.clearAll(isolation: self)

    await delegate?.buildTargetsChanged(notification.changes)
    await delegate?.fileBuildSettingsChanged(Set(watchedFiles.keys))
  }

  private func logMessage(notification: BuildServerProtocol.OnBuildLogMessageNotification) async {
    let message =
      if let taskID = notification.task?.id {
        prefixMessageWithTaskEmoji(taskID: taskID, message: notification.message)
      } else {
        notification.message
      }
    await connectionToClient.waitUntilInitialized()
    connectionToClient.send(
      LanguageServerProtocol.LogMessageNotification(type: .info, message: message, logName: "SourceKit-LSP: Indexing")
    )
  }

  private func taskStart(notification: TaskStartNotification) async {
    guard let workDoneProgressTitle = WorkDoneProgressTask(fromLSPAny: notification.data)?.title,
      await connectionToClient.clientSupportsWorkDoneProgress
    else {
      return
    }

    guard workDoneProgressManagers[notification.taskId.id] == nil else {
      logger.error("Client is already tracking a work done progress for task \(notification.taskId.id)")
      return
    }
    workDoneProgressManagers[notification.taskId.id] = WorkDoneProgressManager(
      connectionToClient: connectionToClient,
      waitUntilClientInitialized: connectionToClient.waitUntilInitialized,
      tokenPrefix: notification.taskId.id,
      initialDebounce: options.workDoneProgressDebounceDurationOrDefault,
      title: workDoneProgressTitle
    )
  }

  private func taskProgress(notification: TaskProgressNotification) async {
    guard let progressManager = workDoneProgressManagers[notification.taskId.id] else {
      return
    }
    let percentage: Int? =
      if let progress = notification.progress, let total = notification.total {
        Int((Double(progress) / Double(total) * 100).rounded())
      } else {
        nil
      }
    await progressManager.update(message: notification.message, percentage: percentage)
  }

  private func taskFinish(notification: TaskFinishNotification) async {
    guard let progressManager = workDoneProgressManagers[notification.taskId.id] else {
      return
    }
    await progressManager.end()
    workDoneProgressManagers[notification.taskId.id] = nil
  }

  // MARK: Build System queries

  /// Returns the toolchain that should be used to process the given document.
  package func toolchain(
    for uri: DocumentURI,
    in target: BuildTargetIdentifier?,
    language: Language
  ) async -> Toolchain? {
    let toolchainPath = await orLog("Getting toolchain from build targets") { () -> URL? in
      guard let target else {
        return nil
      }
      let targets = try await self.buildTargets()
      guard let target = targets[target]?.target else {
        logger.error("Failed to find target \(target.forLogging) to determine toolchain")
        return nil
      }
      guard let toolchain = target.sourceKitData?.toolchain else {
        return nil
      }
      guard let toolchainUrl = toolchain.fileURL else {
        logger.error("Toolchain is not a file URL")
        return nil
      }
      return toolchainUrl
    }
    if let toolchainPath {
      if let toolchain = await self.toolchainRegistry.toolchain(withPath: toolchainPath) {
        return toolchain
      }
      logger.error("Toolchain at \(toolchainPath) not registered in toolchain registry.")
    }

    switch language {
    case .swift:
      return await toolchainRegistry.preferredToolchain(containing: [\.sourcekitd, \.swift, \.swiftc])
    case .c, .cpp, .objective_c, .objective_cpp:
      return await toolchainRegistry.preferredToolchain(containing: [\.clang, \.clangd])
    default:
      return nil
    }
  }

  /// Ask the build system if it explicitly specifies a language for this document. Return `nil` if it does not.
  private func languageInferredFromBuildSystem(
    for document: DocumentURI,
    in target: BuildTargetIdentifier
  ) async throws -> Language? {
    let sourcesItems = try await self.sourceFiles(in: [target])
    let sourceFiles = sourcesItems.flatMap(\.sources)
    var result: Language? = nil
    for sourceFile in sourceFiles where sourceFile.uri == document {
      guard let language = sourceFile.sourceKitData?.language else {
        continue
      }
      if result != nil && result != language {
        logger.error("Conflicting languages for \(document.forLogging) in \(target)")
        return nil
      }
      result = language
    }
    return result
  }

  /// Returns the language that a document should be interpreted in for background tasks where the editor doesn't
  /// specify the document's language.
  package func defaultLanguage(for document: DocumentURI, in target: BuildTargetIdentifier) async -> Language? {
    let languageFromBuildSystem = await orLog("Getting source files to determine default language") {
      try await languageInferredFromBuildSystem(for: document, in: target)
    }
    return languageFromBuildSystem ?? Language(inferredFromFileExtension: document)
  }

  /// Returns all the targets that the document is part of.
  package func targets(for document: DocumentURI) async -> Set<BuildTargetIdentifier> {
    return await orLog("Getting targets for source file") {
      var result: Set<BuildTargetIdentifier> = []
      let filesAndDirectories = try await sourceFilesAndDirectories(includeNonBuildableFiles: true)
      if let targets = filesAndDirectories.files[document]?.targets {
        result.formUnion(targets)
      }
      if !filesAndDirectories.directories.isEmpty, let documentPath = document.fileURL {
        for (directory, info) in filesAndDirectories.directories {
          guard let directoryPath = directory.fileURL else {
            continue
          }
          if documentPath.isDescendant(of: directoryPath) {
            result.formUnion(info.targets)
          }
        }
      }
      return result
    } ?? []
  }

  /// Returns the `BuildTargetIdentifier` that should be used for semantic functionality of the given document.
  package func canonicalTarget(for document: DocumentURI) async -> BuildTargetIdentifier? {
    // Sort the targets to deterministically pick the same `BuildTargetIdentifier` every time.
    // We could allow the user to specify a preference of one target over another.
    return await targets(for: document)
      .sorted { $0.uri.stringValue < $1.uri.stringValue }
      .first
  }

  /// Returns the target's module name as parsed from the `BuildTargetIdentifier`'s compiler arguments.
  package func moduleName(for document: DocumentURI, in target: BuildTargetIdentifier) async -> String? {
    guard let language = await self.defaultLanguage(for: document, in: target),
      let buildSettings = await buildSettings(
        for: document,
        in: target,
        language: language,
        fallbackAfterTimeout: false
      )
    else {
      return nil
    }

    switch language {
    case .swift:
      // Module name is specified in the form -module-name MyLibrary
      guard let moduleNameFlagIndex = buildSettings.compilerArguments.lastIndex(of: "-module-name") else {
        return nil
      }
      return buildSettings.compilerArguments[safe: moduleNameFlagIndex + 1]
    case .objective_c:
      // Specified in the form -fmodule-name=MyLibrary
      guard
        let moduleNameArgument = buildSettings.compilerArguments.last(where: { $0.starts(with: "-fmodule-name=") }),
        let moduleName = moduleNameArgument.split(separator: "=").last
      else {
        return nil
      }
      return String(moduleName)
    default:
      return nil
    }
  }

  /// Returns the build settings for `document` from `buildSystem`.
  ///
  /// Implementation detail of `buildSettings(for:language:)`.
  private func buildSettingsFromBuildSystem(
    for document: DocumentURI,
    in target: BuildTargetIdentifier,
    language: Language
  ) async throws -> FileBuildSettings? {
    guard let buildSystemAdapter = await buildSystemAdapterAfterInitialized else {
      return nil
    }
    let request = TextDocumentSourceKitOptionsRequest(
      textDocument: TextDocumentIdentifier(document),
      target: target,
      language: language
    )

    let response = try await cachedSourceKitOptions.get(request, isolation: self) { request in
      try await buildSystemAdapter.send(request)
    }
    guard let response else {
      return nil
    }
    return FileBuildSettings(
      compilerArguments: response.compilerArguments,
      workingDirectory: response.workingDirectory,
      isFallback: false
    )
  }

  /// Returns the build settings for the given file in the given target.
  ///
  /// If no target is given, this always returns fallback build settings.
  ///
  /// Only call this method if it is known that `document` is a main file. Prefer `buildSettingsInferredFromMainFile`
  /// otherwise. If `document` is a header file, this will most likely return fallback settings because header files
  /// don't have build settings by themselves.
  ///
  /// If `fallbackAfterTimeout` is true fallback build settings will be returned if no build settings can be found in
  /// `SourceKitLSPOptions.buildSettingsTimeoutOrDefault`.
  package func buildSettings(
    for document: DocumentURI,
    in target: BuildTargetIdentifier?,
    language: Language,
    fallbackAfterTimeout: Bool
  ) async -> FileBuildSettings? {
    if let target {
      let buildSettingsFromBuildSystem = await orLog("Getting build settings") {
        if fallbackAfterTimeout {
          try await withTimeout(options.buildSettingsTimeoutOrDefault) {
            return try await self.buildSettingsFromBuildSystem(for: document, in: target, language: language)
          } resultReceivedAfterTimeout: {
            await self.delegate?.fileBuildSettingsChanged([document])
          }
        } else {
          try await self.buildSettingsFromBuildSystem(for: document, in: target, language: language)
        }
      }
      if let buildSettingsFromBuildSystem {
        return buildSettingsFromBuildSystem
      }
    }

    guard
      var settings = fallbackBuildSettings(
        for: document,
        language: language,
        options: options.fallbackBuildSystemOrDefault
      )
    else {
      return nil
    }
    if buildSystemAdapter == nil {
      // If there is no build system and we only have the fallback build system, we will never get real build settings.
      // Consider the build settings non-fallback.
      settings.isFallback = false
    }
    return settings
  }

  /// Returns the build settings for the given document.
  ///
  /// If the document doesn't have builds settings by itself, eg. because it is a C header file, the build settings will
  /// be inferred from the primary main file of the document. In practice this means that we will compute the build
  /// settings of a C file that includes the header and replace any file references to that C file in the build settings
  /// by the header file.
  package func buildSettingsInferredFromMainFile(
    for document: DocumentURI,
    language: Language,
    fallbackAfterTimeout: Bool
  ) async -> FileBuildSettings? {
    func mainFileAndSettings(
      basedOn document: DocumentURI
    ) async -> (mainFile: DocumentURI, settings: FileBuildSettings)? {
      let mainFile = await self.mainFile(for: document, language: language)
      let settings = await orLog("Getting build settings") {
        let target = try await withTimeout(options.buildSettingsTimeoutOrDefault) {
          await self.canonicalTarget(for: mainFile)
        } resultReceivedAfterTimeout: {
          await self.delegate?.fileBuildSettingsChanged([document])
        }
        return await self.buildSettings(
          for: mainFile,
          in: target,
          language: language,
          fallbackAfterTimeout: fallbackAfterTimeout
        )
      }
      guard let settings else {
        return nil
      }
      return (mainFile, settings)
    }

    var settings: FileBuildSettings?
    var mainFile: DocumentURI?
    if let mainFileAndSettings = await mainFileAndSettings(basedOn: document) {
      (mainFile, settings) = mainFileAndSettings
    }
    if settings?.isFallback ?? true, let symlinkTarget = document.symlinkTarget,
      let mainFileAndSettings = await mainFileAndSettings(basedOn: symlinkTarget)
    {
      (mainFile, settings) = mainFileAndSettings
    }
    guard var settings, let mainFile else {
      return nil
    }

    if mainFile != document {
      // If the main file isn't the file itself, we need to patch the build settings
      // to reference `document` instead of `mainFile`.
      settings = settings.patching(newFile: document, originalFile: mainFile)
    }

    await BuildSettingsLogger.shared.log(settings: settings, for: document)
    return settings
  }

  package func waitForUpToDateBuildGraph() async {
    await orLog("Waiting for build system updates") {
      let _: VoidResponse? = try await buildSystemAdapterAfterInitialized?.send(
        WorkspaceWaitForBuildSystemUpdatesRequest()
      )
    }
    // Handle any messages the build system might have sent us while updating.
    await messageHandlingQueue.async(metadata: .stateChange) {}.valuePropagatingCancellation
  }

  /// The root targets of the project have depth of 0 and all target dependencies have a greater depth than the target
  /// itself.
  private func targetDepthsAndDependents(
    for buildTargets: [BuildTarget]
  ) -> (depths: [BuildTargetIdentifier: Int], dependents: [BuildTargetIdentifier: Set<BuildTargetIdentifier>]) {
    var nonRoots: Set<BuildTargetIdentifier> = []
    for buildTarget in buildTargets {
      nonRoots.formUnion(buildTarget.dependencies)
    }
    let targetsById = Dictionary(elements: buildTargets, keyedBy: \.id)
    var dependents: [BuildTargetIdentifier: Set<BuildTargetIdentifier>] = [:]
    var depths: [BuildTargetIdentifier: Int] = [:]
    let rootTargets = buildTargets.filter { !nonRoots.contains($0.id) }
    var worksList: [(target: BuildTargetIdentifier, depth: Int)] = rootTargets.map { ($0.id, 0) }
    while let (target, depth) = worksList.popLast() {
      depths[target] = max(depths[target, default: 0], depth)
      for dependency in targetsById[target]?.dependencies ?? [] {
        dependents[dependency, default: []].insert(target)
        // Check if we have already recorded this target with a greater depth, in which case visiting it again will
        // not increase its depth or any of its children.
        if depths[target, default: 0] < depth + 1 {
          worksList.append((dependency, depth + 1))
        }
      }
    }
    return (depths, dependents)
  }

  /// Sort the targets so that low-level targets occur before high-level targets.
  ///
  /// This sorting is best effort but allows the indexer to prepare and index low-level targets first, which allows
  /// index data to be available earlier.
  package func topologicalSort(of targets: [BuildTargetIdentifier]) async throws -> [BuildTargetIdentifier] {
    guard let buildTargets = await orLog("Getting build targets for topological sort", { try await buildTargets() })
    else {
      return targets.sorted { $0.uri.stringValue < $1.uri.stringValue }
    }

    return targets.sorted { (lhs: BuildTargetIdentifier, rhs: BuildTargetIdentifier) -> Bool in
      let lhsDepth = buildTargets[lhs]?.depth ?? 0
      let rhsDepth = buildTargets[rhs]?.depth ?? 0
      if lhsDepth != rhsDepth {
        return rhsDepth > lhsDepth
      }
      return lhs.uri.stringValue < rhs.uri.stringValue
    }
  }

  /// Returns the list of targets that might depend on the given target and that need to be re-prepared when a file in
  /// `target` is modified.
  package func targets(dependingOn targetIds: Set<BuildTargetIdentifier>) async -> [BuildTargetIdentifier] {
    guard
      let buildTargets = await orLog("Getting build targets for dependents", { try await self.buildTargets() })
    else {
      return []
    }

    return transitiveClosure(of: targetIds, successors: { buildTargets[$0]?.dependents ?? [] })
      .sorted { $0.uri.stringValue < $1.uri.stringValue }
  }

  package func prepare(targets: Set<BuildTargetIdentifier>) async throws {
    let _: VoidResponse? = try await buildSystemAdapterAfterInitialized?.send(
      BuildTargetPrepareRequest(targets: targets.sorted { $0.uri.stringValue < $1.uri.stringValue })
    )
    await orLog("Calling fileDependenciesUpdated") {
      let filesInPreparedTargets = try await self.sourceFiles(in: targets).flatMap(\.sources).map(\.uri)
      await filesDependenciesUpdatedDebouncer.scheduleCall(Set(filesInPreparedTargets))
    }
  }

  package func registerForChangeNotifications(for uri: DocumentURI, language: Language) async {
    let mainFile = await mainFile(for: uri, language: language)
    self.watchedFiles[uri] = (mainFile, language)
  }

  package func unregisterForChangeNotifications(for uri: DocumentURI) async {
    self.watchedFiles[uri] = nil
  }

  private func buildTargets() async throws -> [BuildTargetIdentifier: BuildTargetInfo] {
    guard let buildSystemAdapter = await buildSystemAdapterAfterInitialized else {
      return [:]
    }

    let request = WorkspaceBuildTargetsRequest()
    let result = try await cachedBuildTargets.get(request, isolation: self) { request in
      let buildTargets = try await buildSystemAdapter.send(request).targets
      let (depths, dependents) = await self.targetDepthsAndDependents(for: buildTargets)
      var result: [BuildTargetIdentifier: BuildTargetInfo] = [:]
      result.reserveCapacity(buildTargets.count)
      for buildTarget in buildTargets {
        guard result[buildTarget.id] == nil else {
          logger.error("Found two targets with the same ID \(buildTarget.id)")
          continue
        }
        let depth: Int
        if let d = depths[buildTarget.id] {
          depth = d
        } else {
          logger.fault("Did not compute depth for target \(buildTarget.id)")
          depth = 0
        }
        result[buildTarget.id] = BuildTargetInfo(
          target: buildTarget,
          depth: depth,
          dependents: dependents[buildTarget.id] ?? []
        )
      }
      return result
    }
    return result
  }

  package func buildTarget(named identifier: BuildTargetIdentifier) async -> BuildTarget? {
    return await orLog("Getting built target with ID") {
      try await buildTargets()[identifier]?.target
    }
  }

  package func sourceFiles(in targets: Set<BuildTargetIdentifier>) async throws -> [SourcesItem] {
    guard let buildSystemAdapter = await buildSystemAdapterAfterInitialized, !targets.isEmpty else {
      return []
    }

    // If we have a cached request for a superset of the targets, serve the result from that cache entry.
    let fromSuperset = await orLog("Getting source files from superset request") {
      try await cachedTargetSources.get(isolation: self) { request in
        targets.isSubset(of: request.targets)
      } transform: { response in
        return BuildTargetSourcesResponse(items: response.items.filter { targets.contains($0.target) })
      }
    }
    if let fromSuperset {
      return fromSuperset.items
    }

    let request = BuildTargetSourcesRequest(targets: targets.sorted { $0.uri.stringValue < $1.uri.stringValue })
    let response = try await cachedTargetSources.get(request, isolation: self) { request in
      try await buildSystemAdapter.send(request)
    }
    return response.items
  }

  /// Returns all source files in the project that can be built.
  ///
  /// - SeeAlso: Comment in `sourceFilesAndDirectories` for a definition of what `buildable` means.
  package func buildableSourceFiles() async throws -> [DocumentURI: SourceFileInfo] {
    return try await sourceFilesAndDirectories(includeNonBuildableFiles: false).files
  }

  /// Get all files and directories that are known to the build system, ie. that are returned by a `buildTarget/sources`
  /// request for any target in the project.
  ///
  /// Source files returned here fall into two categories:
  ///  - Buildable source files are files that can be built by the build system and that make sense to background index
  ///  - Non-buildable source files include eg. the SwiftPM package manifest or header files. We have sufficient
  ///    compiler arguments for these files to provide semantic editor functionality but we can't build them.
  ///
  /// `includeNonBuildableFiles` determines whether non-buildable files should be included.
  private func sourceFilesAndDirectories(includeNonBuildableFiles: Bool) async throws -> SourceFilesAndDirectories {
    let targets = try await self.buildTargets()
    let sourcesItems = try await self.sourceFiles(in: Set(targets.keys))

    let key = SourceFilesAndDirectoriesKey(
      includeNonBuildableFiles: includeNonBuildableFiles,
      sourcesItems: sourcesItems
    )

    return try await cachedSourceFilesAndDirectories.get(key, isolation: self) { key in
      var files: [DocumentURI: SourceFileInfo] = [:]
      var directories: [DocumentURI: SourceFileInfo] = [:]
      for sourcesItem in key.sourcesItems {
        let target = targets[sourcesItem.target]?.target
        let isPartOfRootProject = !(target?.tags.contains(.dependency) ?? false)
        let mayContainTests = target?.tags.contains(.test) ?? true
        if !key.includeNonBuildableFiles && (target?.tags.contains(.notBuildable) ?? false) {
          continue
        }

        for sourceItem in sourcesItem.sources {
          if !key.includeNonBuildableFiles && sourceItem.sourceKitData?.isHeader ?? false {
            continue
          }
          let info = SourceFileInfo(
            targets: [sourcesItem.target],
            isPartOfRootProject: isPartOfRootProject,
            mayContainTests: mayContainTests
          )
          switch sourceItem.kind {
          case .file:
            files[sourceItem.uri] = info.merging(files[sourceItem.uri])
          case .directory:
            directories[sourceItem.uri] = info.merging(directories[sourceItem.uri])
          }
        }
      }
      return SourceFilesAndDirectories(files: files, directories: directories)
    }
  }

  package func testFiles() async throws -> [DocumentURI] {
    return try await buildableSourceFiles().compactMap { (uri, info) -> DocumentURI? in
      guard info.isPartOfRootProject, info.mayContainTests else {
        return nil
      }
      return uri
    }
  }

  private func watchedFilesReferencing(mainFiles: Set<DocumentURI>) -> Set<DocumentURI> {
    return Set(
      watchedFiles.compactMap { (watchedFile, mainFileAndLanguage) in
        if mainFiles.contains(mainFileAndLanguage.mainFile) {
          return watchedFile
        } else {
          return nil
        }
      }
    )
  }

  /// Return the main file that should be used to get build settings for `uri`.
  ///
  /// For Swift or normal C files, this will be the file itself. For header
  /// files, we pick a main file that includes the header since header files
  /// don't have build settings by themselves.
  package func mainFile(for uri: DocumentURI, language: Language, useCache: Bool = true) async -> DocumentURI {
    if language == .swift {
      // Swift doesn't have main files. Skip the main file provider query.
      return uri
    }
    if useCache, let mainFile = self.watchedFiles[uri]?.mainFile {
      // Performance optimization: We did already compute the main file and have
      // it cached. We can just return it.
      return mainFile
    }
    guard let mainFilesProvider else {
      return uri
    }

    let mainFiles = await mainFilesProvider.mainFilesContainingFile(uri)
    if mainFiles.contains(uri) {
      // If the main files contain the file itself, prefer to use that one
      return uri
    } else if let mainFile = mainFiles.min(by: { $0.pseudoPath < $1.pseudoPath }) {
      // Pick the lexicographically first main file if it exists.
      // This makes sure that picking a main file is deterministic.
      return mainFile
    } else {
      return uri
    }
  }

  /// Returns the main file used for `uri`, if this is a registered file.
  ///
  /// For testing purposes only.
  package func cachedMainFile(for uri: DocumentURI) -> DocumentURI? {
    return self.watchedFiles[uri]?.mainFile
  }

  // MARK: Informing BuildSystemManager about changes

  package func filesDidChange(_ events: [FileEvent]) async {
    if let buildSystemAdapter = await buildSystemAdapterAfterInitialized {
      await buildSystemAdapter.send(OnWatchedFilesDidChangeNotification(changes: events))
    }

    var targetsWithUpdatedDependencies: Set<BuildTargetIdentifier> = []
    // If a Swift file within a target is updated, reload all the other files within the target since they might be
    // referring to a function in the updated file.
    let targetsWithChangedSwiftFiles =
      await events
      .filter { Language(inferredFromFileExtension: $0.uri) == .swift }
      .asyncFlatMap { await self.targets(for: $0.uri) }
    targetsWithUpdatedDependencies.formUnion(targetsWithChangedSwiftFiles)

    // If a `.swiftmodule` file is updated, this means that we have performed a build / are
    // performing a build and files that depend on this module have updated dependencies.
    // We don't have access to the build graph from the SwiftPM API offered to SourceKit-LSP to figure out which files
    // depend on the updated module, so assume that all files have updated dependencies.
    // The file watching here is somewhat fragile as well because it assumes that the `.swiftmodule` files are being
    // written to a directory within the project root. This is not necessarily true if the user specifies a build
    // directory outside the source tree.
    // If we have background indexing enabled, this is not necessary because we call `fileDependenciesUpdated` when
    // preparation of a target finishes.
    if !options.backgroundIndexingOrDefault,
      events.contains(where: { $0.uri.fileURL?.pathExtension == "swiftmodule" })
    {
      await orLog("Getting build targets") {
        targetsWithUpdatedDependencies.formUnion(try await self.buildTargets().keys)
      }
    }

    var filesWithUpdatedDependencies: Set<DocumentURI> = []

    await orLog("Getting source files in targets") {
      let sourceFiles = try await self.sourceFiles(in: Set(targetsWithUpdatedDependencies))
      filesWithUpdatedDependencies.formUnion(sourceFiles.flatMap(\.sources).map(\.uri))
    }

    if let mainFilesProvider {
      var mainFiles = await Set(events.asyncFlatMap { await mainFilesProvider.mainFilesContainingFile($0.uri) })
      mainFiles.subtract(events.map(\.uri))
      filesWithUpdatedDependencies.formUnion(mainFiles)
    }

    await self.filesDependenciesUpdatedDebouncer.scheduleCall(filesWithUpdatedDependencies)
  }

  /// Checks if there are any files in `mainFileAssociations` where the main file
  /// that we have stored has changed.
  ///
  /// For all of these files, re-associate the file with the new main file and
  /// inform the delegate that the build settings for it might have changed.
  package func mainFilesChanged() async {
    var changedMainFileAssociations: Set<DocumentURI> = []
    for (file, (oldMainFile, language)) in self.watchedFiles {
      let newMainFile = await self.mainFile(for: file, language: language, useCache: false)
      if newMainFile != oldMainFile {
        self.watchedFiles[file] = (newMainFile, language)
        changedMainFileAssociations.insert(file)
      }
    }

    for file in changedMainFileAssociations {
      guard let language = watchedFiles[file]?.language else {
        continue
      }
      // Re-register for notifications of this file within the build system.
      // This is the easiest way to make sure we are watching for build setting
      // changes of the new main file and stop watching for build setting
      // changes in the old main file if no other watched file depends on it.
      await self.unregisterForChangeNotifications(for: file)
      await self.registerForChangeNotifications(for: file, language: language)
    }

    if let delegate, !changedMainFileAssociations.isEmpty {
      await delegate.fileBuildSettingsChanged(changedMainFileAssociations)
    }
  }
}
