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

@_spi(SourceKitLSP) package import BuildServerProtocol
import Dispatch
package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) package import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
import SKUtilities
import SwiftExtensions
import TSCExtensions
package import ToolchainRegistry
@_spi(SourceKitLSP) package import ToolsProtocolsSwiftExtensions

import struct TSCBasic.RelativePath

private typealias RequestCache<Request: RequestType & Hashable> = Cache<Request, Request.Response>

/// An output path returned from the build server in the `SourceItem.data.outputPath` field.
package enum OutputPath: Hashable, Comparable, CustomLogStringConvertible {
  /// An output path returned from the build server.
  case path(String)

  /// The build server does not support output paths.
  case notSupported

  package var description: String {
    switch self {
    case .notSupported: return "<output path not supported>"
    case .path(let path): return path
    }
  }

  package var redactedDescription: String {
    switch self {
    case .notSupported: return "<output path not supported>"
    case .path(let path): return path.hashForLogging
    }
  }
}

package struct SourceFileInfo: Sendable {
  /// Maps the targets that this source file is a member of to the output path the file has within that target.
  ///
  /// The value in the dictionary can be:
  ///  - `.path` if the build server supports output paths and produced a result
  ///  - `.notSupported` if the build server does not support output paths.
  ///  - `nil` if the build server supports output paths but did not return an output path for this file in this target.
  package var targetsToOutputPath: [BuildTargetIdentifier: OutputPath?]

  /// The targets that this source file is a member of
  package var targets: some Collection<BuildTargetIdentifier> & Sendable { targetsToOutputPath.keys }

  /// `true` if this file belongs to the root project that the user is working on. It is false, if the file belongs
  /// to a dependency of the project.
  package var isPartOfRootProject: Bool

  /// Whether the file might contain test cases. This property is an over-approximation. It might be true for files
  /// from non-test targets or files that don't actually contain any tests.
  package var mayContainTests: Bool

  /// Source files returned here fall into two categories:
  ///  - Buildable source files are files that can be built by the build server and that make sense to background index
  ///  - Non-buildable source files include eg. the SwiftPM package manifest or header files. We have sufficient
  ///    compiler arguments for these files to provide semantic editor functionality but we can't build them.
  package var isBuildable: Bool

  /// If this source item gets copied to a different destination during preparation, the destinations it will be copied
  /// to.
  package var copyDestinations: Set<DocumentURI>

  fileprivate func merging(_ other: SourceFileInfo?) -> SourceFileInfo {
    guard let other else {
      return self
    }
    let mergedTargetsToOutputPaths = targetsToOutputPath.merging(
      other.targetsToOutputPath,
      uniquingKeysWith: { lhs, rhs in
        if lhs == rhs {
          return lhs
        }
        logger.error("Received mismatching output files: \(lhs?.forLogging) vs \(rhs?.forLogging)")
        // Deterministically pick an output file if they mismatch. But really, this shouldn't happen.
        switch (lhs, rhs) {
        case (let lhs?, nil): return lhs
        case (nil, let rhs?): return rhs
        case (nil, nil): return nil  // Should be handled above already
        case (let lhs?, let rhs?): return min(lhs, rhs)
        }
      }
    )
    return SourceFileInfo(
      targetsToOutputPath: mergedTargetsToOutputPaths,
      isPartOfRootProject: other.isPartOfRootProject || isPartOfRootProject,
      mayContainTests: other.mayContainTests || mayContainTests,
      isBuildable: other.isBuildable || isBuildable,
      copyDestinations: copyDestinations.union(other.copyDestinations)
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

/// A build server adapter is responsible for receiving messages from the `BuildServerManager` and forwarding them to
/// the build server. For built-in build servers, this means that we need to translate the BSP messages to methods in
/// the `BuiltInBuildServer` protocol. For external (aka. out-of-process, aka. BSP servers) build servers, this means
/// that we need to manage the external build server's lifetime.
private enum BuildServerAdapter {
  case builtIn(BuiltInBuildServerAdapter, connectionToBuildServer: any Connection)
  case external(ExternalBuildServerAdapter)
  /// A message handler that was created by `injectBuildServer` and will handle all BSP messages.
  case injected(any Connection)

  /// Send a notification to the build server.
  func send(_ notification: some NotificationType) async {
    switch self {
    case .builtIn(_, let connectionToBuildServer):
      connectionToBuildServer.send(notification)
    case .external(let external):
      await external.send(notification)
    case .injected(let connection):
      connection.send(notification)
    }
  }

  /// Send a request to the build server.
  func send<Request: RequestType>(_ request: Request) async throws -> Request.Response {
    switch self {
    case .builtIn(_, let connectionToBuildServer):
      return try await connectionToBuildServer.send(request)
    case .external(let external):
      return try await external.send(request)
    case .injected(let messageHandler):
      // After we sent the request, the ID of the request.
      // When we send a `CancelRequestNotification` this is reset to `nil` so that we don't send another cancellation
      // notification.
      let requestID = ThreadSafeBox<RequestID?>(initialValue: nil)

      return try await withTaskCancellationHandler {
        return try await withCheckedThrowingContinuation { continuation in
          if Task.isCancelled {
            return continuation.resume(throwing: CancellationError())
          }
          requestID.value = messageHandler.send(request) { response in
            continuation.resume(with: response)
          }
          if Task.isCancelled {
            // The task might have been cancelled after we checked `Task.isCancelled` above but before `requestID.value`
            // is set, we won't send a `CancelRequestNotification` from the `onCancel` handler. Send it from here.
            if let requestID = requestID.takeValue() {
              messageHandler.send(CancelRequestNotification(id: requestID))
            }
          }
        }
      } onCancel: {
        if let requestID = requestID.takeValue() {
          messageHandler.send(CancelRequestNotification(id: requestID))
        }
      }
    }
  }
}

private extension BuildServerSpec {
  private func createBuiltInBuildServerAdapter(
    messagesToSourceKitLSPHandler: any MessageHandler,
    buildServerHooks: BuildServerHooks,
    _ createBuildServer:
      @Sendable (
        _ connectionToSourceKitLSP: any Connection
      ) async throws -> (any BuiltInBuildServer)?
  ) async -> BuildServerAdapter? {
    let connectionToSourceKitLSP = LocalConnection(
      receiverName: "BuildServerManager for \(projectRoot.lastPathComponent)",
      handler: messagesToSourceKitLSPHandler
    )

    let buildServer = await orLog("Creating build server") {
      try await createBuildServer(connectionToSourceKitLSP)
    }
    guard let buildServer else {
      logger.log("Failed to create build server at \(projectRoot)")
      return nil
    }
    logger.log("Created \(type(of: buildServer), privacy: .public) at \(projectRoot)")
    let buildServerAdapter = BuiltInBuildServerAdapter(
      underlyingBuildServer: buildServer,
      connectionToSourceKitLSP: connectionToSourceKitLSP,
      buildServerHooks: buildServerHooks
    )
    let connectionToBuildServer = LocalConnection(
      receiverName: "\(type(of: buildServer)) for \(projectRoot.lastPathComponent)",
      handler: buildServerAdapter
    )
    return .builtIn(buildServerAdapter, connectionToBuildServer: connectionToBuildServer)
  }

  /// Create a `BuildServerAdapter` that manages a build server of this kind and return a connection that can be used
  /// to send messages to the build server.
  func createBuildServerAdapter(
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    buildServerHooks: BuildServerHooks,
    messagesToSourceKitLSPHandler: any MessageHandler
  ) async -> BuildServerAdapter? {
    switch self.kind {
    case .externalBuildServer:
      let buildServer = await orLog("Creating external build server") {
        try await ExternalBuildServerAdapter(
          projectRoot: projectRoot,
          configPath: configPath,
          messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler
        )
      }
      guard let buildServer else {
        logger.log("Failed to create external build server at \(projectRoot)")
        return nil
      }
      logger.log("Created external build server at \(projectRoot)")
      return .external(buildServer)
    case .jsonCompilationDatabase:
      return await createBuiltInBuildServerAdapter(
        messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler,
        buildServerHooks: buildServerHooks
      ) { connectionToSourceKitLSP in
        try JSONCompilationDatabaseBuildServer(
          configPath: configPath,
          toolchainRegistry: toolchainRegistry,
          connectionToSourceKitLSP: connectionToSourceKitLSP
        )
      }
    case .fixedCompilationDatabase:
      return await createBuiltInBuildServerAdapter(
        messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler,
        buildServerHooks: buildServerHooks
      ) { connectionToSourceKitLSP in
        try FixedCompilationDatabaseBuildServer(
          configPath: configPath,
          connectionToSourceKitLSP: connectionToSourceKitLSP
        )
      }
    case .swiftPM:
      #if !NO_SWIFTPM_DEPENDENCY
      return await createBuiltInBuildServerAdapter(
        messagesToSourceKitLSPHandler: messagesToSourceKitLSPHandler,
        buildServerHooks: buildServerHooks
      ) { connectionToSourceKitLSP in
        try await SwiftPMBuildServer(
          projectRoot: projectRoot,
          toolchainRegistry: toolchainRegistry,
          options: options,
          connectionToSourceKitLSP: connectionToSourceKitLSP,
          testHooks: buildServerHooks.swiftPMTestHooks
        )
      }
      #else
      return nil
      #endif
    case .injected(let injector):
      let connectionToSourceKitLSP = LocalConnection(
        receiverName: "BuildServerManager for \(projectRoot.lastPathComponent)",
        handler: messagesToSourceKitLSPHandler
      )
      return .injected(
        await injector(projectRoot, connectionToSourceKitLSP)
      )
    }
  }
}

/// Entry point for all build server queries.
package actor BuildServerManager: QueueBasedMessageHandler {
  package let messageHandlingHelper = QueueBasedMessageHandlerHelper(
    signpostLoggingCategory: "build-server-manager-message-handling",
    createLoggingScope: false
  )

  package let messageHandlingQueue = AsyncQueue<BuildServerMessageDependencyTracker>()

  /// The path to the main configuration file (or directory) that this build server manages.
  ///
  /// Some examples:
  ///   - The path to `Package.swift` for SwiftPM packages
  ///   - The path to `compile_commands.json` for a JSON compilation database
  ///
  /// `nil` if the `BuildServerManager` does not have an underlying build server.
  package let configPath: URL?

  /// The files for which the delegate has requested change notifications, ie. the files for which the delegate wants to
  /// get `fileBuildSettingsChanged` and `filesDependenciesUpdated` callbacks.
  private var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  private var connectionToClient: any BuildServerManagerConnectionToClient

  /// The build serer adapter that is used to answer build server queries.
  private var buildServerAdapter: BuildServerAdapter?

  /// The build server adapter after initialization finishes. When sending messages to the BSP server, this should be
  /// preferred over `buildServerAdapter` because no messages must be sent to the build server before initialization
  /// finishes.
  private var buildServerAdapterAfterInitialized: BuildServerAdapter? {
    get async throws {
      guard await initializeResult.value != nil else {
        throw ResponseError.unknown("Build server failed to initialize")
      }
      return buildServerAdapter
    }
  }

  /// Provider of file to main file mappings.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private var mainFilesProvider: Task<(any MainFilesProvider)?, Never>! {
    didSet {
      // Must only be set once
      precondition(oldValue == nil)
      precondition(mainFilesProvider != nil)
    }
  }

  package func mainFilesProvider<T: MainFilesProvider>(as: T.Type) async -> T? {
    guard let mainFilesProvider = mainFilesProvider else {
      return nil
    }
    guard let index = await mainFilesProvider.value as? T else {
      logger.fault("Expected the main files provider of the build server manager to be an `\(T.self)`")
      return nil
    }
    return index
  }

  /// Build server delegate that will receive notifications about setting changes, etc.
  private weak var delegate: (any BuildServerManagerDelegate)?

  private let buildSettingsLogger = BuildSettingsLogger()

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

  /// For tasks from the build server that should create a work done progress in the client, a mapping from the `TaskId`
  /// in the build server to a `WorkDoneProgressManager` that manages that work done progress in the client.
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

  /// Debounces calls to `delegate.fileBuildSettingsChanged`.
  ///
  /// This helps in the following situation: A build server takes 5s to return build settings for a file and we have 10
  /// requests for those build settings coming in that time period. Once we get build settings, we get 10 calls to
  /// `resultReceivedAfterTimeout` in `buildSettings(for:in:language:fallbackAfterTimeout:)`, all for the same document.
  /// But calling `fileBuildSettingsChanged` once is totally sufficient.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private var filesBuildSettingsChangedDebouncer: Debouncer<Set<DocumentURI>>! = nil {
    didSet {
      // Must only be set once
      precondition(oldValue == nil)
      precondition(filesBuildSettingsChangedDebouncer != nil)
    }
  }

  private var cachedAdjustedSourceKitOptions = RequestCache<TextDocumentSourceKitOptionsRequest>()

  private var cachedBuildTargets = Cache<WorkspaceBuildTargetsRequest, [BuildTargetIdentifier: BuildTargetInfo]>()

  private var cachedTargetSources = RequestCache<BuildTargetSourcesRequest>()

  /// `SourceFilesAndDirectories` is a global property that only gets reset when the build targets change and thus
  /// has no real key.
  private struct SourceFilesAndDirectoriesKey: Hashable {}

  private struct SourceFilesAndDirectories {
    /// The source files in the workspace, ie. all `SourceItem`s that have `kind == .file`.
    let files: [DocumentURI: SourceFileInfo]

    /// The source directories in the workspace, ie. all `SourceItem`s that have `kind == .directory`.
    ///
    /// `pathComponents` is the result of `key.fileURL?.pathComponents`. We frequently need these path components to
    /// determine if a file is descendent of the directory and computing them from the `DocumentURI` is expensive.
    let directories: [DocumentURI: (pathComponents: [String]?, info: SourceFileInfo)]

    /// Same as `Set(files.filter(\.value.isBuildable).keys)`. Pre-computed because we need this pretty frequently in
    /// `SemanticIndexManager.filesToIndex`.
    let buildableSourceFiles: Set<DocumentURI>

    internal init(
      files: [DocumentURI: SourceFileInfo],
      directories: [DocumentURI: (pathComponents: [String]?, info: SourceFileInfo)]
    ) {
      self.files = files
      self.directories = directories
      self.buildableSourceFiles = Set(files.filter(\.value.isBuildable).keys)
    }

  }

  private let cachedSourceFilesAndDirectories = Cache<SourceFilesAndDirectoriesKey, SourceFilesAndDirectories>()

  /// The latest map of copied file URIs to their original source locations.
  ///
  /// We don't use a `Cache` for this because we can provide reasonable functionality even without or with an
  /// out-of-date copied file map - in the worst case we jump to a file in the build directory instead of the source
  /// directory.
  /// We don't want to block requests like definition on receiving up-to-date index information from the build server.
  private var cachedCopiedFileMap: [DocumentURI: DocumentURI] = [:]

  /// The latest task to update the `cachedCopiedFileMap`. This allows us to cancel previous tasks to update the copied
  /// file map when a new update is requested.
  private var copiedFileMapUpdateTask: Task<Void, Never>?

  /// The `SourceKitInitializeBuildResponseData` received from the `build/initialize` request, if any.
  package var initializationData: SourceKitInitializeBuildResponseData? {
    get async {
      return await initializeResult.value?.sourceKitData
    }
  }

  package init(
    buildServerSpec: BuildServerSpec?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    connectionToClient: any BuildServerManagerConnectionToClient,
    buildServerHooks: BuildServerHooks,
    createMainFilesProvider:
      @escaping @Sendable (
        SourceKitInitializeBuildResponseData?, _ mainFilesChangedCallback: @escaping @Sendable () async -> Void
      ) async -> (any MainFilesProvider)?
  ) async {
    self.toolchainRegistry = toolchainRegistry
    self.options = options
    self.connectionToClient = connectionToClient
    self.configPath = buildServerSpec?.configPath
    self.buildServerAdapter = await buildServerSpec?.createBuildServerAdapter(
      toolchainRegistry: toolchainRegistry,
      options: options,
      buildServerHooks: buildServerHooks,
      messagesToSourceKitLSPHandler: WeakMessageHandler(self)
    )

    // The debounce duration of 500ms was chosen arbitrarily without any measurements.
    self.filesDependenciesUpdatedDebouncer = Debouncer(
      debounceDuration: .milliseconds(500),
      combineResults: { $0.union($1) },
      makeCall: { [weak self] (filesWithUpdatedDependencies) in
        guard let self, let delegate = await self.delegate else {
          logger.fault("Not calling filesDependenciesUpdated because no delegate exists in SwiftPMBuildServer")
          return
        }
        let changedWatchedFiles = await self.watchedFilesReferencing(mainFiles: filesWithUpdatedDependencies)
        if !changedWatchedFiles.isEmpty {
          await delegate.filesDependenciesUpdated(changedWatchedFiles)
        }
      }
    )

    // We don't need a large debounce duration here. It just needs to be big enough to accumulate
    // `resultReceivedAfterTimeout` calls for the same document (see comment on `filesBuildSettingsChangedDebouncer`).
    // Since they should all come in at the same time, a couple of milliseconds should be sufficient here, an 20ms be
    // plenty while still not causing a noticeable delay to the user.
    self.filesBuildSettingsChangedDebouncer = Debouncer(
      debounceDuration: .milliseconds(20),
      combineResults: { $0.union($1) },
      makeCall: { [weak self] (filesWithChangedBuildSettings) in
        guard let self, let delegate = await self.delegate else {
          logger.fault("Not calling fileBuildSettingsChanged because no delegate exists in SwiftPMBuildServer")
          return
        }
        if !filesWithChangedBuildSettings.isEmpty {
          await delegate.fileBuildSettingsChanged(filesWithChangedBuildSettings)
        }
      }
    )

    // TODO: Forward file watch patterns from this initialize request to the client
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1671)
    initializeResult = Task { () -> InitializeBuildResponse? in
      guard let buildServerAdapter else {
        return nil
      }
      guard let buildServerSpec else {
        logger.fault("If we have a connectionToBuildServer, we must have had a buildServerSpec")
        return nil
      }
      let initializeResponse: InitializeBuildResponse?
      do {
        initializeResponse = try await buildServerAdapter.send(
          InitializeBuildRequest(
            displayName: "SourceKit-LSP",
            version: "",
            bspVersion: "2.2.0",
            rootUri: URI(buildServerSpec.projectRoot),
            capabilities: BuildClientCapabilities(languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift])
          )
        )
      } catch {
        initializeResponse = nil
        let errorMessage: String
        if let error = error as? ResponseError {
          errorMessage = error.message
        } else {
          errorMessage = "\(error)"
        }
        connectionToClient.send(
          ShowMessageNotification(type: .error, message: "Failed to initialize build server: \(errorMessage)")
        )
      }

      if let initializeResponse, !(initializeResponse.sourceKitData?.sourceKitOptionsProvider ?? false),
        case .external(let externalBuildServerAdapter) = buildServerAdapter
      {
        // The BSP server does not support the pull-based settings model. Inject a `LegacyBuildServerBuildServer` that
        // offers the pull-based model to `BuildServerManager` and uses the push-based model to get build settings from
        // the build server.
        logger.log("Launched a legacy BSP server. Using push-based build settings model.")
        let legacyBuildServer = await LegacyBuildServer(
          projectRoot: buildServerSpec.projectRoot,
          configPath: buildServerSpec.configPath,
          initializationData: initializeResponse,
          externalBuildServerAdapter
        )
        let adapter = BuiltInBuildServerAdapter(
          underlyingBuildServer: legacyBuildServer,
          connectionToSourceKitLSP: legacyBuildServer.connectionToSourceKitLSP,
          buildServerHooks: buildServerHooks
        )
        let connectionToBuildSerer = LocalConnection(receiverName: "Legacy BSP server", handler: adapter)
        self.buildServerAdapter = .builtIn(adapter, connectionToBuildServer: connectionToBuildSerer)
      }
      Task {
        var filesToWatch = initializeResponse?.sourceKitData?.watchers ?? []
        filesToWatch.append(FileSystemWatcher(globPattern: "**/*.swift", kind: [.change]))
        if !options.backgroundIndexingOrDefault {
          filesToWatch.append(FileSystemWatcher(globPattern: "**/*.swiftmodule", kind: [.create, .change, .delete]))
        }
        await connectionToClient.watchFiles(filesToWatch)
      }
      await buildServerAdapter.send(OnBuildInitializedNotification())
      return initializeResponse
    }
    self.mainFilesProvider = Task {
      await createMainFilesProvider(initializationData) { [weak self] in
        await self?.mainFilesChanged()
      }
    }
  }

  /// Explicitly shut down the build server.
  ///
  /// The build server is automatically shut down using a background task when `BuildServerManager` is deallocated.
  /// This, however, leads to possible race conditions where the shutdown task might not finish before the test is done,
  /// which could result in the connection being reported as a leak. To avoid this problem, we want to explicitly shut
  /// down the build server when the `SourceKitLSPServer` gets shut down.
  package func shutdown() async {
    // Clear any pending work done progresses from the build server.
    self.workDoneProgressManagers.removeAll()
    guard let buildServerAdapter = try? await self.buildServerAdapterAfterInitialized else {
      return
    }
    await orLog("Sending shutdown request to build server") {
      // Give the build server 2 seconds to shut down by itself. If it doesn't shut down within that time, terminate it.
      try await withTimeout(.seconds(2)) {
        _ = try await buildServerAdapter.send(BuildShutdownRequest())
        await buildServerAdapter.send(OnBuildExitNotification())
      }
    }
    if case .external(let externalBuildServerAdapter) = buildServerAdapter {
      await orLog("Terminating external build server") {
        // Give the build server 1 second to exit after receiving the `build/exit` notification. If it doesn't exit
        // within that time, terminate it.
        try await externalBuildServerAdapter.terminateIfRunning(after: .seconds(1))
      }
    }
    self.buildServerAdapter = nil
  }

  deinit {
    // Shut down the build server before closing the connection to it
    Task { [buildServerAdapter, initializeResult] in
      guard let buildServerAdapter else {
        return
      }
      // We are accessing the raw connection to the build server, so we need to ensure that it has been initialized here
      _ = await initializeResult?.value
      await orLog("Sending shutdown request to build server") {
        _ = try await buildServerAdapter.send(BuildShutdownRequest())
        await buildServerAdapter.send(OnBuildExitNotification())
      }
    }
  }

  /// - Note: Needed because `BuildSererManager` is created before `Workspace` is initialized and `Workspace` needs to
  ///   create the `BuildServerManager`, then initialize itself and then set itself as the delegate.
  package func setDelegate(_ delegate: (any BuildServerManagerDelegate)?) {
    self.delegate = delegate
  }

  // MARK: Handling messages from the build server

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
    let changedTargets: Set<BuildTargetIdentifier>? =
      if let changes = notification.changes {
        Set(changes.map(\.target))
      } else {
        nil
      }
    await self.buildTargetsDidChange(.didChangeBuildTargets(changedTargets: changedTargets))
  }

  private enum BuildTargetsChange {
    case didChangeBuildTargets(changedTargets: Set<BuildTargetIdentifier>?)
    case buildTargetsReceivedResultAfterTimeout(
      request: WorkspaceBuildTargetsRequest,
      newResult: [BuildTargetIdentifier: BuildTargetInfo]
    )
    case sourceFilesReceivedResultAfterTimeout(
      request: BuildTargetSourcesRequest,
      newResult: BuildTargetSourcesResponse
    )
  }

  /// Update the cached state in `BuildServerManager` because new data was received from the BSP server.
  ///
  /// This handles a few seemingly unrelated reasons to ensure that we think about which caches to invalidate in the
  /// other scenarios as well, when making changes in here.
  private func buildTargetsDidChange(_ stateChange: BuildTargetsChange) async {
    let changedTargets: Set<BuildTargetIdentifier>?

    switch stateChange {
    case .didChangeBuildTargets(let changedTargetsValue):
      changedTargets = changedTargetsValue
      self.cachedAdjustedSourceKitOptions.clear(isolation: self) { cacheKey in
        guard let changedTargets else {
          // All targets might have changed
          return true
        }
        return changedTargets.contains(cacheKey.target)
      }
      self.cachedBuildTargets.clearAll(isolation: self)
      self.cachedTargetSources.clear(isolation: self) { cacheKey in
        guard let changedTargets else {
          // All targets might have changed
          return true
        }
        return !changedTargets.intersection(cacheKey.targets).isEmpty
      }
    case .buildTargetsReceivedResultAfterTimeout(let request, let newResult):
      changedTargets = nil

      // Caches not invalidated:
      // - cachedAdjustedSourceKitOptions: We would not have requested SourceKit options for targets that we didn't
      //   know about. Even if we did, the build server now telling us about the target should not change the options of
      //   the file within the target
      // - cachedTargetSources: Similar to cachedAdjustedSourceKitOptions, we would not have requested sources for
      //   targets that we didn't know about and if we did, they wouldn't be affected
      self.cachedBuildTargets.set(request, to: newResult)
    case .sourceFilesReceivedResultAfterTimeout(let request, let newResult):
      changedTargets = Set(request.targets)

      // Caches not invalidated:
      // - cachedAdjustedSourceKitOptions: Same as for buildTargetsReceivedResultAfterTimeout.
      // - cachedBuildTargets: Getting a result for the source files in a target doesn't change anything about the
      //   target's existence.
      self.cachedTargetSources.set(request, to: newResult)
    }
    // Clear caches that capture global state and are affected by all changes
    self.cachedSourceFilesAndDirectories.clearAll(isolation: self)
    self.scheduleRecomputeCopyFileMap()

    await delegate?.buildTargetsChanged(changedTargets)
    await filesBuildSettingsChangedDebouncer.scheduleCall(Set(watchedFiles.keys))
  }

  private func logMessage(notification: OnBuildLogMessageNotification) async {
    await connectionToClient.waitUntilInitialized()
    let type: WindowMessageType =
      switch notification.type {
      case .error: .error
      case .warning: .warning
      case .info: .info
      case .log: .log
      }
    connectionToClient.logMessageToIndexLog(
      message: notification.message,
      type: type,
      structure: notification.lspStructure
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

  // MARK: Build server queries

  /// Returns the toolchain that should be used to process the given target.
  ///
  /// If `target` is `nil` or the build server does not explicitly specify a toolchain for this target, the preferred
  /// toolchain for the given language is returned.
  package func toolchain(
    for target: BuildTargetIdentifier?,
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
    case .swift, .markdown, .tutorial:
      return await toolchainRegistry.preferredToolchain(containing: [\.sourcekitd, \.swift, \.swiftc])
    case .c, .cpp, .objective_c, .objective_cpp:
      return await toolchainRegistry.preferredToolchain(containing: [\.clang, \.clangd])
    default:
      return nil
    }
  }

  /// Ask the build server if it explicitly specifies a language for this document. Return `nil` if it does not.
  private func languageInferredFromBuildServer(
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
    let languageFromBuildServer = await orLog("Getting source files to determine default language") {
      try await languageInferredFromBuildServer(for: document, in: target)
    }
    return languageFromBuildServer ?? Language(inferredFromFileExtension: document)
  }

  /// Returns the language that a document should be interpreted in for background tasks where the editor doesn't
  /// specify the document's language.
  ///
  /// If the language could not be determined, this method throws an error.
  package func defaultLanguageInCanonicalTarget(for document: DocumentURI) async throws -> Language {
    struct UnableToInferLanguage: Error, CustomStringConvertible {
      let document: DocumentURI
      var description: String { "Unable to infer language for \(document)" }
    }

    guard let canonicalTarget = await self.canonicalTarget(for: document) else {
      guard let language = Language(inferredFromFileExtension: document) else {
        throw UnableToInferLanguage(document: document)
      }
      return language
    }
    guard let language = await defaultLanguage(for: document, in: canonicalTarget) else {
      throw UnableToInferLanguage(document: document)
    }
    return language
  }

  /// Retrieve information about the given source file within the build server.
  package func sourceFileInfo(for document: DocumentURI) async -> SourceFileInfo? {
    return await orLog("Getting targets for source file") {
      var result: SourceFileInfo? = nil
      let filesAndDirectories = try await sourceFilesAndDirectories()
      if let info = filesAndDirectories.files[document] {
        result = result?.merging(info) ?? info
      }
      if !filesAndDirectories.directories.isEmpty, let documentPathComponents = document.fileURL?.pathComponents {
        for (_, (directoryPathComponents, info)) in filesAndDirectories.directories {
          guard let directoryPathComponents else {
            continue
          }
          if isDescendant(documentPathComponents, of: directoryPathComponents) {
            result = result?.merging(info) ?? info
          }
        }
      }
      return result
    }
  }

  /// Check if the URI referenced by `location` has been copied during the preparation phase. If so, adjust the URI to
  /// the original source file.
  package func locationAdjustedForCopiedFiles(_ location: Location) -> Location {
    guard let originalUri = cachedCopiedFileMap[location.uri] else {
      return location
    }
    // If we regularly get issues that the copied file is out-of-sync with its original, we can check that the contents
    // of the lines touched by the location match and only return the original URI if they do. For now, we avoid this
    // check due to its performance cost of reading files from disk.
    return Location(uri: originalUri, range: location.range)
  }

  /// Check if the URI referenced by `location` has been copied during the preparation phase. If so, adjust the URI to
  /// the original source file.
  package func locationsAdjustedForCopiedFiles(_ locations: [Location]) -> [Location] {
    return locations.map { locationAdjustedForCopiedFiles($0) }
  }

  private func uriAdjustedForCopiedFiles(_ uri: DocumentURI) -> DocumentURI {
    guard let originalUri = cachedCopiedFileMap[uri] else {
      return uri
    }
    return originalUri
  }

  package func workspaceEditAdjustedForCopiedFiles(_ workspaceEdit: WorkspaceEdit?) -> WorkspaceEdit? {
    guard var edit = workspaceEdit else {
      return nil
    }
    if let changes = edit.changes {
      var newChanges: [DocumentURI: [TextEdit]] = [:]
      for (uri, edits) in changes {
        let newUri = self.uriAdjustedForCopiedFiles(uri)
        newChanges[newUri, default: []] += edits
      }
      edit.changes = newChanges
    }
    if let documentChanges = edit.documentChanges {
      var newDocumentChanges: [WorkspaceEditDocumentChange] = []
      for change in documentChanges {
        switch change {
        case .textDocumentEdit(var textEdit):
          textEdit.textDocument.uri = self.uriAdjustedForCopiedFiles(textEdit.textDocument.uri)
          newDocumentChanges.append(.textDocumentEdit(textEdit))
        case .createFile(var create):
          create.uri = self.uriAdjustedForCopiedFiles(create.uri)
          newDocumentChanges.append(.createFile(create))
        case .renameFile(var rename):
          rename.oldUri = self.uriAdjustedForCopiedFiles(rename.oldUri)
          rename.newUri = self.uriAdjustedForCopiedFiles(rename.newUri)
          newDocumentChanges.append(.renameFile(rename))
        case .deleteFile(var delete):
          delete.uri = self.uriAdjustedForCopiedFiles(delete.uri)
          newDocumentChanges.append(.deleteFile(delete))
        }
      }
      edit.documentChanges = newDocumentChanges
    }
    return edit
  }

  package func locationsOrLocationLinksAdjustedForCopiedFiles(_ response: LocationsOrLocationLinksResponse?) -> LocationsOrLocationLinksResponse? {
    guard let response = response else {
      return nil
    }
    switch response {
    case .locations(let locations):
      let remappedLocations = self.locationsAdjustedForCopiedFiles(locations)
      return .locations(remappedLocations)
    case .locationLinks(let locationLinks):
      var remappedLinks: [LocationLink] = []
      for link in locationLinks {
        let adjustedTargetLocation = self.locationAdjustedForCopiedFiles(Location(uri: link.targetUri, range: link.targetRange))
        let adjustedTargetSelectionLocation = self.locationAdjustedForCopiedFiles(Location(uri: link.targetUri, range: link.targetSelectionRange))
        remappedLinks.append(LocationLink(
          originSelectionRange: link.originSelectionRange,
          targetUri: adjustedTargetLocation.uri,
          targetRange: adjustedTargetLocation.range,
          targetSelectionRange: adjustedTargetSelectionLocation.range
        ))
      }
      return .locationLinks(remappedLinks)
    }
  }

  package func typeHierarchyItemAdjustedForCopiedFiles(_ item: TypeHierarchyItem) -> TypeHierarchyItem {
    let adjustedLocation = self.locationAdjustedForCopiedFiles(Location(uri: item.uri, range: item.range))
    let adjustedSelectionLocation = self.locationAdjustedForCopiedFiles(Location(uri: item.uri, range: item.selectionRange))
    return TypeHierarchyItem(
      name: item.name,
      kind: item.kind,
      tags: item.tags,
      detail: item.detail,
      uri: adjustedLocation.uri,
      range: adjustedLocation.range,
      selectionRange: adjustedSelectionLocation.range,
      data: item.data
    )
  }

  @discardableResult
  package func scheduleRecomputeCopyFileMap() -> Task<Void, Never> {
    let task = Task { [previousUpdateTask = copiedFileMapUpdateTask] in
      previousUpdateTask?.cancel()
      await orLog("Re-computing copy file map") {
        let sourceFilesAndDirectories = try await self.sourceFilesAndDirectories()
        try Task.checkCancellation()
        var copiedFileMap: [DocumentURI: DocumentURI] = [:]
        for (file, fileInfo) in sourceFilesAndDirectories.files {
          for copyDestination in fileInfo.copyDestinations {
            copiedFileMap[copyDestination] = file
          }
        }
        self.cachedCopiedFileMap = copiedFileMap
      }
    }
    copiedFileMapUpdateTask = task
    return task
  }

  /// Returns all the targets that the document is part of.
  package func targets(for document: DocumentURI) async -> [BuildTargetIdentifier] {
    guard let targets = await sourceFileInfo(for: document)?.targets else {
      return []
    }
    return Array(targets)
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

  /// Returns the build settings for `document` from `buildServer`.
  ///
  /// Implementation detail of `buildSettings(for:language:)`.
  private func buildSettingsFromBuildServer(
    for document: DocumentURI,
    in target: BuildTargetIdentifier,
    language: Language
  ) async throws -> FileBuildSettings? {
    guard let buildServerAdapter = try await buildServerAdapterAfterInitialized else {
      return nil
    }
    let request = TextDocumentSourceKitOptionsRequest(
      textDocument: TextDocumentIdentifier(document),
      target: target,
      language: language
    )
    let response = try await cachedAdjustedSourceKitOptions.get(request, isolation: self) { request in
      let options = try await buildServerAdapter.send(request)
      switch language.semanticKind {
      case .swift:
        return options?.adjustArgsForSemanticSwiftFunctionality(fileToIndex: document)
      case .clang:
        return options?.adjustingArgsForSemanticClangFunctionality()
      default:
        return options
      }
    }

    guard let response else {
      return nil
    }

    return FileBuildSettings(
      compilerArguments: response.compilerArguments,
      workingDirectory: response.workingDirectory,
      language: language,
      data: response.data,
      isFallback: false
    )
  }

  /// Returns the build settings for the given file in the given target.
  ///
  /// Only call this method if it is known that `document` is a main file. Prefer `buildSettingsInferredFromMainFile`
  /// otherwise. If `document` is a header file, this will most likely return fallback settings because header files
  /// don't have build settings by themselves.
  ///
  /// If `fallbackAfterTimeout` is true fallback build settings will be returned if no build settings can be found in
  /// `SourceKitLSPOptions.buildSettingsTimeoutOrDefault`.
  package func buildSettings(
    for document: DocumentURI,
    in target: BuildTargetIdentifier,
    language: Language,
    fallbackAfterTimeout: Bool
  ) async -> FileBuildSettings? {
    let buildSettingsFromBuildServer = await orLog("Getting build settings") {
      if fallbackAfterTimeout {
        try await withTimeout(options.buildSettingsTimeoutOrDefault) {
          return try await self.buildSettingsFromBuildServer(for: document, in: target, language: language)
        } resultReceivedAfterTimeout: { _ in
          await self.filesBuildSettingsChangedDebouncer.scheduleCall([document])
        }
      } else {
        try await self.buildSettingsFromBuildServer(for: document, in: target, language: language)
      }
    }
    guard let buildSettingsFromBuildServer else {
      return fallbackBuildSettings(
        for: document,
        language: language,
        options: options.fallbackBuildSystemOrDefault
      )
    }
    return buildSettingsFromBuildServer

  }

  /// Try finding a source file with the same language as `document` in the same directory as `document` and patch its
  /// build settings to provide more accurate fallback settings than the generic fallback settings.
  private func fallbackBuildSettingsInferredFromSiblingFile(
    of document: DocumentURI,
    target explicitlyRequestedTarget: BuildTargetIdentifier?,
    language: Language?,
    fallbackAfterTimeout: Bool
  ) async throws -> FileBuildSettings? {
    guard let documentFileURL = document.fileURL else {
      return nil
    }
    let directory = documentFileURL.deletingLastPathComponent()
    guard let language = language ?? Language(inferredFromFileExtension: document) else {
      return nil
    }
    let siblingFile = try await self.sourceFilesAndDirectories().files.compactMap { (uri, info) -> DocumentURI? in
      guard info.isBuildable, uri.fileURL?.deletingLastPathComponent() == directory else {
        return nil
      }
      if let explicitlyRequestedTarget, !info.targets.contains(explicitlyRequestedTarget) {
        return nil
      }
      // Only consider build settings from sibling files that appear to have the same language. In theory, we might skip
      // valid sibling files because of this since non-standard file extension might be mapped to `language` by the
      // build server, but this is a good first check to avoid requesting build settings for too many documents. And
      // since all of this is fallback-logic, skipping over possibly valid files is not a correctness issue.
      guard let siblingLanguage = Language(inferredFromFileExtension: uri), siblingLanguage == language else {
        return nil
      }
      return uri
    }.sorted(by: { $0.pseudoPath < $1.pseudoPath }).first

    guard let siblingFile else {
      return nil
    }

    let siblingSettings = await self.buildSettingsInferredFromMainFile(
      for: siblingFile,
      target: explicitlyRequestedTarget,
      language: language,
      fallbackAfterTimeout: fallbackAfterTimeout,
      allowInferenceFromSiblingFile: false
    )
    guard var siblingSettings, !siblingSettings.isFallback else {
      return nil
    }
    siblingSettings.isFallback = true
    switch language.semanticKind {
    case .swift:
      siblingSettings.compilerArguments += [try documentFileURL.filePath]
    case .clang:
      siblingSettings = siblingSettings.patching(newFile: document, originalFile: siblingFile)
    case nil:
      return nil
    }
    return siblingSettings
  }

  /// Returns the build settings for the given document.
  ///
  /// If the document doesn't have builds settings by itself, eg. because it is a C header file, the build settings will
  /// be inferred from the primary main file of the document. In practice this means that we will compute the build
  /// settings of a C file that includes the header and replace any file references to that C file in the build settings
  /// by the header file.
  ///
  /// When a target is passed in, the build settings for the document, interpreted as part of that target, are returned,
  /// otherwise a canonical target is inferred for the source file.
  ///
  /// If no language is passed, this method tries to infer the language of the document from the build server. If that
  /// fails, it returns `nil`.
  package func buildSettingsInferredFromMainFile(
    for document: DocumentURI,
    target explicitlyRequestedTarget: BuildTargetIdentifier? = nil,
    language: Language?,
    fallbackAfterTimeout: Bool,
    allowInferenceFromSiblingFile: Bool = true
  ) async -> FileBuildSettings? {
    if buildServerAdapter == nil {
      guard let language = language ?? Language(inferredFromFileExtension: document) else {
        return nil
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
      // If there is no build server and we only have the fallback build server, we will never get real build settings.
      // Consider the build settings non-fallback.
      settings.isFallback = false
      return settings
    }

    func mainFileAndSettings(
      basedOn document: DocumentURI
    ) async -> (mainFile: DocumentURI, settings: FileBuildSettings)? {
      let mainFile = await self.mainFile(for: document, language: language)
      let settings: FileBuildSettings? = await orLog("Getting build settings") { () -> FileBuildSettings? in
        let target: WithTimeoutResult<BuildTargetIdentifier?> =
          if let explicitlyRequestedTarget {
            .result(explicitlyRequestedTarget)
          } else {
            try await withTimeoutResult(options.buildSettingsTimeoutOrDefault) {
              return await self.canonicalTarget(for: mainFile)
            } resultReceivedAfterTimeout: { _ in
              await self.filesBuildSettingsChangedDebouncer.scheduleCall([document])
            }
          }
        var languageForFile: Language
        if let language {
          languageForFile = language
        } else if case let .result(target?) = target,
          let language = await self.defaultLanguage(for: mainFile, in: target)
        {
          languageForFile = language
        } else if let language = Language(inferredFromFileExtension: mainFile) {
          languageForFile = language
        } else {
          // We don't know the language as which to interpret the document, so we can't ask the build server for its
          // settings.
          return nil
        }
        switch target {
        case .result(let target?):
          return await self.buildSettings(
            for: mainFile,
            in: target,
            language: languageForFile,
            fallbackAfterTimeout: fallbackAfterTimeout
          )
        case .result(nil):
          if allowInferenceFromSiblingFile {
            let settingsFromSibling = await orLog("Inferring build settings from sibling file") {
              try await self.fallbackBuildSettingsInferredFromSiblingFile(
                of: document,
                target: explicitlyRequestedTarget,
                language: language,
                fallbackAfterTimeout: fallbackAfterTimeout
              )
            }
            if let settingsFromSibling {
              return settingsFromSibling
            }
          }
          fallthrough
        case .timedOut:
          // If we timed out, we don't want to try inferring the build settings from a sibling since that would kick off
          // new requests to the build server, which will likely also time out.
          return fallbackBuildSettings(
            for: document,
            language: languageForFile,
            options: options.fallbackBuildSystemOrDefault
          )
        }
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

    await buildSettingsLogger.log(settings: settings, for: document)
    return settings
  }

  package func waitForUpToDateBuildGraph() async {
    await orLog("Waiting for build server updates") {
      let _: VoidResponse? = try await buildServerAdapterAfterInitialized?.send(
        WorkspaceWaitForBuildSystemUpdatesRequest()
      )
    }
    // Handle any messages the build server might have sent us while updating.
    await messageHandlingQueue.async(metadata: .stateChange) {}.valuePropagatingCancellation

    // Ensure that we send out all delegate calls so that everybody is informed about the changes.
    await filesBuildSettingsChangedDebouncer.flush()
    await filesDependenciesUpdatedDebouncer.flush()
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
        if depths[dependency, default: 0] < depth + 1 {
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
        return lhsDepth > rhsDepth
      }
      return lhs.uri.stringValue < rhs.uri.stringValue
    }
  }

  /// Returns the list of targets that might depend on the given target and that need to be re-prepared when a file in
  /// `target` is modified.
  package func targets(dependingOn targetIds: some Collection<BuildTargetIdentifier>) async -> [BuildTargetIdentifier] {
    guard
      let buildTargets = await orLog("Getting build targets for dependents", { try await self.buildTargets() })
    else {
      return []
    }

    return transitiveClosure(of: targetIds, successors: { buildTargets[$0]?.dependents ?? [] })
      .sorted { $0.uri.stringValue < $1.uri.stringValue }
  }

  package func prepare(targets: Set<BuildTargetIdentifier>) async throws {
    let _: VoidResponse? = try await buildServerAdapterAfterInitialized?.send(
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
    let request = WorkspaceBuildTargetsRequest()
    let result = try await cachedBuildTargets.get(request, isolation: self) { request in
      let result = try await withTimeout(self.options.buildServerWorkspaceRequestsTimeoutOrDefault) {
        guard let buildServerAdapter = try await self.buildServerAdapterAfterInitialized else {
          return [:]
        }
        let buildTargets = try await buildServerAdapter.send(request).targets
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
      } resultReceivedAfterTimeout: { newResult in
        await self.buildTargetsDidChange(
          .buildTargetsReceivedResultAfterTimeout(request: request, newResult: newResult)
        )
      }
      guard let result else {
        logger.error("Failed to get targets of workspace within timeout")
        return [:]
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
    guard !targets.isEmpty else {
      return []
    }

    let request = BuildTargetSourcesRequest(targets: targets.sorted { $0.uri.stringValue < $1.uri.stringValue })

    // If we have a cached request for a superset of the targets, serve the result from that cache entry.
    let fromSuperset = await orLog("Getting source files from superset request") {
      try await cachedTargetSources.getDerived(
        isolation: self,
        request,
        canReuseKey: { targets.isSubset(of: $0.targets) },
        transform: { BuildTargetSourcesResponse(items: $0.items.filter { targets.contains($0.target) }) }
      )
    }
    if let fromSuperset {
      return fromSuperset.items
    }

    let response = try await cachedTargetSources.get(request, isolation: self) { request in
      try await withTimeout(self.options.buildServerWorkspaceRequestsTimeoutOrDefault) {
        guard let buildServerAdapter = try await self.buildServerAdapterAfterInitialized else {
          return BuildTargetSourcesResponse(items: [])
        }
        return try await buildServerAdapter.send(request)
      } resultReceivedAfterTimeout: { newResult in
        await self.buildTargetsDidChange(.sourceFilesReceivedResultAfterTimeout(request: request, newResult: newResult))
      } ?? BuildTargetSourcesResponse(items: [])
    }
    return response.items
  }

  /// Return the output paths for all source files known to the build server.
  ///
  /// See `SourceKitSourceItemData.outputFilePath` for details.
  package func outputPathsInAllTargets() async throws -> [String] {
    return try await outputPaths(in: Set(buildTargets().map(\.key)))
  }

  /// For all source files in the given targets, return their output file paths.
  ///
  /// See `BuildTargetOutputPathsRequest` for details.
  package func outputPaths(in targets: Set<BuildTargetIdentifier>) async throws -> [String] {
    return try await sourceFiles(in: targets).flatMap(\.sources).compactMap(\.sourceKitData?.outputPath)
  }

  /// Returns all source files in the project.
  ///
  /// - SeeAlso: Comment in `sourceFilesAndDirectories` for a definition of what `buildable` means.
  package func sourceFiles(includeNonBuildableFiles: Bool) async throws -> [DocumentURI: SourceFileInfo] {
    let files = try await sourceFilesAndDirectories().files
    if includeNonBuildableFiles {
      return files
    } else {
      return files.filter(\.value.isBuildable)
    }
  }

  /// Returns all source files in the project that are considered buildable.
  ///
  /// - SeeAlso: Comment in `sourceFilesAndDirectories` for a definition of what `buildable` means.
  package func buildableSourceFiles() async throws -> Set<DocumentURI> {
    return try await sourceFilesAndDirectories().buildableSourceFiles
  }

  /// Get all files and directories that are known to the build server, ie. that are returned by a `buildTarget/sources`
  /// request for any target in the project.
  ///
  /// - Important: This method returns both buildable and non-buildable source files. Callers need to check
  /// `SourceFileInfo.isBuildable` if they are only interested in buildable source files.
  private func sourceFilesAndDirectories() async throws -> SourceFilesAndDirectories {

    return try await cachedSourceFilesAndDirectories.get(
      SourceFilesAndDirectoriesKey(),
      isolation: self
    ) { key in
      let targets = try await self.buildTargets()
      let sourcesItems = try await self.sourceFiles(in: Set(targets.keys))

      var files: [DocumentURI: SourceFileInfo] = [:]
      var directories: [DocumentURI: (pathComponents: [String]?, info: SourceFileInfo)] = [:]
      for sourcesItem in sourcesItems {
        let target = targets[sourcesItem.target]?.target
        let isPartOfRootProject = !(target?.tags.contains(.dependency) ?? false)
        let mayContainTests = target?.tags.contains(.test) ?? true
        for sourceItem in sourcesItem.sources {
          let sourceKitData = sourceItem.sourceKitData
          let outputPath: OutputPath? =
            if !(await self.initializationData?.outputPathsProvider ?? false) {
              .notSupported
            } else if let outputPath = sourceKitData?.outputPath {
              .path(outputPath)
            } else {
              nil
            }
          let info = SourceFileInfo(
            targetsToOutputPath: [sourcesItem.target: outputPath],
            isPartOfRootProject: isPartOfRootProject,
            mayContainTests: mayContainTests,
            isBuildable: !(target?.tags.contains(.notBuildable) ?? false)
              && (sourceKitData?.kind ?? .source) == .source,
            copyDestinations: Set(sourceKitData?.copyDestinations ?? [])
          )
          switch sourceItem.kind {
          case .file:
            files[sourceItem.uri] = info.merging(files[sourceItem.uri])
          case .directory:
            directories[sourceItem.uri] = (
              sourceItem.uri.fileURL?.pathComponents, info.merging(directories[sourceItem.uri]?.info)
            )
          }
        }
      }
      return SourceFilesAndDirectories(files: files, directories: directories)
    }
  }

  package func testFiles() async throws -> [DocumentURI] {
    return try await sourceFiles(includeNonBuildableFiles: false).compactMap { (uri, info) -> DocumentURI? in
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
  /// For Swift or normal C files, this will be the file itself. For header files, we pick a main file that includes the
  /// header since header files don't have build settings by themselves.
  ///
  /// `language` is a hint of the document's language to speed up the `main` file lookup. Passing `nil` if the language
  /// is unknown should always be safe.
  package func mainFile(for uri: DocumentURI, language: Language?, useCache: Bool = true) async -> DocumentURI {
    if language == .swift {
      // Swift doesn't have main files. Skip the main file provider query.
      return uri
    }
    if useCache, let mainFile = self.watchedFiles[uri]?.mainFile {
      // Performance optimization: We did already compute the main file and have
      // it cached. We can just return it.
      return mainFile
    }

    let mainFiles = await mainFiles(containing: uri)
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

  /// Returns all main files that include the given document.
  ///
  /// On Darwin platforms, this also performs the following normalization: indexstore-db by itself returns realpaths
  /// but the build server might be using standardized Darwin paths (eg. realpath is `/private/tmp` but the standardized
  /// path is `/tmp`). If the realpath that indexstore-db returns could not be found in the build server's source files
  /// but the standardized path is part of the source files, return the standardized path instead.
  package func mainFiles(containing uri: DocumentURI) async -> [DocumentURI] {
    guard let mainFilesProvider = await mainFilesProvider.value else {
      return [uri]
    }
    let mainFiles = Array(await mainFilesProvider.mainFiles(containing: uri, crossLanguage: false))
    if Platform.current == .darwin {
      if let buildableSourceFiles = try? await self.buildableSourceFiles() {
        return mainFiles.map { mainFile in
          if mainFile == uri {
            // Do not apply the standardized file normalization to the source file itself. Otherwise we would get the
            // following behavior:
            //  - We have a build server that uses standardized file paths and index a file as /tmp/test.c
            //  - We are asking for the main files of /private/tmp/test.c
            //  - Since indexstore-db uses realpath for everything, we find the unit for /tmp/test.c as a unit containg
            //    /private/tmp/test.c, which has /private/tmp/test.c as the main file.
            //  - If we applied the path normalization, we would normalize /private/tmp/test.c to /tmp/test.c, thus
            //    reporting that /tmp/test.c is a main file containing /private/tmp/test.c,
            // But that doesn't make sense (it would, in fact cause us to treat /private/tmp/test.c as a header file that
            // we should index using /tmp/test.c as a main file.
            return mainFile
          }
          if buildableSourceFiles.contains(mainFile) {
            return mainFile
          }
          guard let fileURL = mainFile.fileURL else {
            return mainFile
          }
          let standardized = DocumentURI(fileURL.standardizedFileURL)
          if buildableSourceFiles.contains(standardized) {
            return standardized
          }
          return mainFile
        }
      }
    }
    return mainFiles
  }

  /// Returns the main file used for `uri`, if this is a registered file.
  ///
  /// For testing purposes only.
  package func cachedMainFile(for uri: DocumentURI) -> DocumentURI? {
    return self.watchedFiles[uri]?.mainFile
  }

  // MARK: Informing BuildSererManager about changes

  package func filesDidChange(_ events: [FileEvent]) async {
    if let buildServerAdapter = try? await buildServerAdapterAfterInitialized {
      await buildServerAdapter.send(OnWatchedFilesDidChangeNotification(changes: events))
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

    var mainFiles = await Set(events.asyncFlatMap { await self.mainFiles(containing: $0.uri) })
    mainFiles.subtract(events.map(\.uri))
    filesWithUpdatedDependencies.formUnion(mainFiles)

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
      // Re-register for notifications of this file within the build server.
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

/// Returns `true` if the path components `selfPathComponents`, retrieved from `URL.pathComponents` are a descendent
/// of the other path components.
///
/// This operates directly on path components instead of `URL`s because computing the path components of a URL is
/// expensive and this allows us to cache the path components.
private func isDescendant(_ selfPathComponents: [String], of otherPathComponents: [String]) -> Bool {
  return selfPathComponents.dropLast().starts(with: otherPathComponents)
}

fileprivate extension TextDocumentSourceKitOptionsResponse {
  /// Adjust compiler arguments that were created for building to compiler arguments that should be used for indexing
  /// or background AST builds.
  ///
  /// This removes compiler arguments that produce output files and adds arguments to eg. allow errors and index the
  /// file.
  func adjustArgsForSemanticSwiftFunctionality(fileToIndex: DocumentURI) -> TextDocumentSourceKitOptionsResponse {
    // Technically, `-o` and the output file don't need to be separated by a space. Eg. `swiftc -oa file.swift` is
    // valid and will write to an output file named `a`.
    // We can't support that because the only way to know that `-output-file-map` is a different flag and not an option
    // to write to an output file named `utput-file-map` is to know all compiler arguments of `swiftc`, which we don't.
    let outputPathOption = CompilerCommandLineOption.option("o", [.singleDash], [.separatedBySpace])

    let indexUnitOutputPathOption =
      CompilerCommandLineOption.option("index-unit-output-path", [.singleDash], [.separatedBySpace])

    let optionsToRemove: [CompilerCommandLineOption] = [
      .flag("c", [.singleDash]),
      .flag("disable-cmo", [.singleDash]),
      .flag("emit-dependencies", [.singleDash]),
      .flag("emit-module-interface", [.singleDash]),
      .flag("emit-module", [.singleDash]),
      .flag("emit-objc-header", [.singleDash]),
      .flag("incremental", [.singleDash]),
      .flag("no-color-diagnostics", [.singleDash]),
      .flag("parseable-output", [.singleDash]),
      .flag("save-temps", [.singleDash]),
      .flag("serialize-diagnostics", [.singleDash]),
      .flag("use-frontend-parseable-output", [.singleDash]),
      .flag("validate-clang-modules-once", [.singleDash]),
      .flag("whole-module-optimization", [.singleDash]),
      .flag("experimental-skip-all-function-bodies", frontendName: "Xfrontend", [.singleDash]),
      .flag("experimental-skip-non-inlinable-function-bodies", frontendName: "Xfrontend", [.singleDash]),
      .flag("experimental-skip-non-exportable-decls", frontendName: "Xfrontend", [.singleDash]),
      .flag("experimental-lazy-typecheck", frontendName: "Xfrontend", [.singleDash]),

      .option("clang-build-session-file", [.singleDash], [.separatedBySpace]),
      .option("emit-module-interface-path", [.singleDash], [.separatedBySpace]),
      .option("emit-module-path", [.singleDash], [.separatedBySpace]),
      .option("emit-objc-header-path", [.singleDash], [.separatedBySpace]),
      .option("emit-package-module-interface-path", [.singleDash], [.separatedBySpace]),
      .option("emit-private-module-interface-path", [.singleDash], [.separatedBySpace]),
      .option("num-threads", [.singleDash], [.separatedBySpace]),
      outputPathOption,
      .option("output-file-map", [.singleDash], [.separatedBySpace, .separatedByEqualSign]),
    ]

    var result: [String] = []
    result.reserveCapacity(compilerArguments.count)
    var iterator = compilerArguments.makeIterator()
    while let argument = iterator.next() {
      switch optionsToRemove.firstMatch(for: argument) {
      case .removeOption:
        continue
      case .removeOptionAndNextArgument:
        _ = iterator.next()
        continue
      case .removeOptionAndPreviousArgument(let name):
        if let previousArg = result.last, previousArg.hasSuffix("-\(name)") {
          _ = result.popLast()
        }
        continue
      case nil:
        break
      }
      result.append(argument)
    }

    result += [
      // Avoid emitting the ABI descriptor, we don't need it
      "-Xfrontend", "-empty-abi-descriptor",
    ]

    result += supplementalClangIndexingArgs.flatMap { ["-Xcc", $0] }

    if let outputPathIndex = compilerArguments.lastIndex(where: { outputPathOption.matches(argument: $0) != nil }),
      compilerArguments.allSatisfy({ indexUnitOutputPathOption.matches(argument: $0) == nil }),
      outputPathIndex + 1 < compilerArguments.count
    {
      // The original compiler arguments contained `-o` to specify the output file but we have stripped that away.
      // Re-introduce the output path as `-index-unit-output-path` so that we have an output path for the unit file.
      result += ["-index-unit-output-path", compilerArguments[outputPathIndex + 1]]
    }

    var adjusted = self
    adjusted.compilerArguments = result
    return adjusted
  }

  /// Adjust compiler arguments that were created for building to compiler arguments that should be used for indexing
  /// or background AST builds.
  ///
  /// This removes compiler arguments that produce output files and adds arguments to eg. typecheck only.
  func adjustingArgsForSemanticClangFunctionality() -> TextDocumentSourceKitOptionsResponse {
    let optionsToRemove: [CompilerCommandLineOption] = [
      // Disable writing of a depfile
      .flag("M", [.singleDash]),
      .flag("MD", [.singleDash]),
      .flag("MMD", [.singleDash]),
      .flag("MG", [.singleDash]),
      .flag("MM", [.singleDash]),
      .flag("MV", [.singleDash]),
      // Don't create phony targets
      .flag("MP", [.singleDash]),
      // Don't write out compilation databases
      .flag("MJ", [.singleDash]),
      // Don't compile
      .flag("c", [.singleDash]),

      .flag("fmodules-validate-once-per-build-session", [.singleDash]),

      // Disable writing of a depfile
      .option("MT", [.singleDash], [.noSpace, .separatedBySpace]),
      .option("MF", [.singleDash], [.noSpace, .separatedBySpace]),
      .option("MQ", [.singleDash], [.noSpace, .separatedBySpace]),

      // Don't write serialized diagnostic files
      .option("serialize-diagnostics", [.singleDash, .doubleDash], [.separatedBySpace]),

      .option("fbuild-session-file", [.singleDash], [.separatedByEqualSign]),
    ]

    var result: [String] = []
    result.reserveCapacity(compilerArguments.count)
    var iterator = compilerArguments.makeIterator()
    while let argument = iterator.next() {
      switch optionsToRemove.firstMatch(for: argument) {
      case .removeOption:
        continue
      case .removeOptionAndNextArgument:
        _ = iterator.next()
        continue
      case .removeOptionAndPreviousArgument(let name):
        if let previousArg = result.last, previousArg.hasSuffix("-\(name)") {
          _ = result.popLast()
        }
        continue
      case nil:
        break
      }
      result.append(argument)
    }
    result += supplementalClangIndexingArgs
    result.append(
      "-fsyntax-only"
    )

    var adjusted = self
    adjusted.compilerArguments = result
    return adjusted
  }
}

private let supplementalClangIndexingArgs: [String] = [
  // Retain extra information for indexing
  "-fretain-comments-from-system-headers",
  // Pick up macro definitions during indexing
  "-Xclang", "-detailed-preprocessing-record",

  // libclang uses 'raw' module-format. Match it so we can reuse the module cache and PCHs that libclang uses.
  "-Xclang", "-fmodule-format=raw",

  // Be less strict - we want to continue and typecheck/index as much as possible
  "-Xclang", "-fallow-pch-with-compiler-errors",
  "-Xclang", "-fallow-pcm-with-compiler-errors",
  "-Wno-non-modular-include-in-framework-module",
  "-Wno-incomplete-umbrella",
]

private extension OnBuildLogMessageNotification {
  var lspStructure: LanguageServerProtocol.StructuredLogKind? {
    guard let taskId = self.task?.id else {
      return nil
    }
    switch structure {
    case .begin(let info):
      return .begin(StructuredLogBegin(title: info.title, taskID: taskId))
    case .report:
      return .report(StructuredLogReport(taskID: taskId))
    case .end:
      return .end(StructuredLogEnd(taskID: taskId))
    case nil:
      return nil
    }
  }
}
