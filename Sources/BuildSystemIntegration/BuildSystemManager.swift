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

import BuildServerProtocol
import Dispatch
import Foundation
import LanguageServerProtocol
import SKLogging
import SKOptions
import SKSupport
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath

#if canImport(os)
import os
#endif

fileprivate class Cache<Key: Sendable & Hashable, Result: Sendable> {
  private var storage: [Key: Task<Result, Error>] = [:]

  func get(
    _ key: Key,
    isolation: isolated any Actor = #isolation,
    compute: @Sendable @escaping (Key) async throws(Error) -> Result
  ) async throws(Error) -> Result {
    let task: Task<Result, Error>
    if let cached = storage[key] {
      task = cached
    } else {
      task = Task {
        try await compute(key)
      }
      storage[key] = task
    }
    return try await task.value
  }

  func get(
    whereKey keyPredicate: (Key) -> Bool,
    isolation: isolated any Actor = #isolation,
    transform: @Sendable @escaping (Result) -> Result
  ) async throws -> Result? {
    for (key, value) in storage {
      if keyPredicate(key) {
        return try await transform(value.value)
      }
    }
    return nil
  }

  func clear(where condition: (Key) -> Bool, isolation: isolated any Actor = #isolation) {
    for key in storage.keys {
      if condition(key) {
        storage[key] = nil
      }
    }
  }

  func clearAll(isolation: isolated any Actor = #isolation) {
    storage.removeAll()
  }
}

package struct SourceFileInfo: Sendable {
  /// The targets that this source file is a member of
  package var targets: Set<BuildTargetIdentifier>

  /// `true` if this file belongs to the root project that the user is working on. It is false, if the file belongs
  /// to a dependency of the project.
  package var isPartOfRootProject: Bool

  /// Whether the file might contain test cases. This property is an over-approximation. It might be true for files
  /// from non-test targets or files that don't actually contain any tests. Keeping this list of files with
  /// `mayContainTets` minimal as possible helps reduce the amount of work that the syntactic test indexer needs to
  /// perform.
  package var mayContainTests: Bool

  func merging(_ other: SourceFileInfo?) -> SourceFileInfo {
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

fileprivate extension SourceItem {
  var sourceKitData: SourceKitSourceItemData? {
    guard dataKind == .sourceKit, case .dictionary(let data) = data else {
      return nil
    }
    return SourceKitSourceItemData(fromLSPDictionary: data)
  }
}

/// `BuildSystem` that integrates client-side information such as main-file lookup as well as providing
///  common functionality such as caching.
///
/// This `BuildSystem` combines settings from optional primary and fallback
/// build systems. We assume the fallback system does not integrate with change
/// notifications; at the moment the fallback must be a `FallbackBuildSystem` if
/// present.
///
/// Since some `BuildSystem`s may require a bit of a time to compute their arguments asynchronously,
/// this class has a configurable `buildSettings` timeout which denotes the amount of time to give
/// the build system before applying the fallback arguments.
package actor BuildSystemManager: QueueBasedMessageHandler {
  package static let signpostLoggingCategory: String = "build-system-manager-message-handling"

  /// The files for which the delegate has requested change notifications, ie.
  /// the files for which the delegate wants to get `filesDependenciesUpdated`
  /// callbacks if the file's build settings.
  private var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  /// The underlying primary build system.
  ///
  /// - Important: The only time this should be modified is in the initializer. Afterwards, it must be constant.
  private var buildSystem: BuiltInBuildSystemAdapter?

  /// If the underlying build system is a `TestBuildSystem`, return it. Otherwise, `nil`
  ///
  /// - Important: For testing purposes only.
  package var testBuildSystem: TestBuildSystem? {
    get async {
      return await buildSystem?.testBuildSystem
    }
  }

  /// The fallback build system. If present, used when the `buildSystem` is not
  /// set or cannot provide settings.
  private let fallbackBuildSystem: FallbackBuildSystem

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
  private var initializeResult: Task<InitializeBuildResponse?, Never>!

  /// Debounces calls to `delegate.filesDependenciesUpdated`.
  ///
  /// This is to ensure we don't call `filesDependenciesUpdated` for the same file multiple time if the client does not
  /// debounce `workspace/didChangeWatchedFiles` and sends a separate notification eg. for every file within a target as
  /// it's being updated by a git checkout, which would cause other files within that target to receive a
  /// `fileDependenciesUpdated` call once for every updated file within the target.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private var filesDependenciesUpdatedDebouncer: Debouncer<Set<DocumentURI>>! = nil

  private var cachedSourceKitOptions = Cache<SourceKitOptionsRequest, SourceKitOptionsResponse?>()

  private var cachedBuildTargets = Cache<
    BuildTargetsRequest, [BuildTargetIdentifier: (target: BuildTarget, depth: Int)]
  >()

  private var cachedTargetSources = Cache<BuildTargetSourcesRequest, BuildTargetSourcesResponse>()

  private struct SourceFilesAndDirectoriesKey: Hashable {
    let includeNonBuildableFiles: Bool
    let sourcesItems: [SourcesItem]
  }

  private struct SourceFilesAndDirectories {
    let files: [DocumentURI: SourceFileInfo]
    let directories: [DocumentURI: SourceFileInfo]
  }

  private let cachedSourceFilesAndDirectories = Cache<SourceFilesAndDirectoriesKey, SourceFilesAndDirectories>()

  /// The root of the project that this build system manages. For example, for SwiftPM packages, this is the folder
  /// containing Package.swift. For compilation databases it is the root folder based on which the compilation database
  /// was found.
  package let projectRoot: AbsolutePath?

  /// The `SourceKitInitializeBuildResponseData` received from the `build/initialize` request, if any.
  package var initializationData: SourceKitInitializeBuildResponseData? {
    get async {
      guard let initializeResult = await initializeResult.value else {
        return nil
      }
      guard initializeResult.dataKind == nil || initializeResult.dataKind == .sourceKit else {
        return nil
      }
      guard case .dictionary(let data) = initializeResult.data else {
        return nil
      }
      return SourceKitInitializeBuildResponseData(fromLSPDictionary: data)
    }
  }

  private let connectionFromBuildSystemToSourceKitLSP: LocalConnection
  private var connectionToBuildSystem: LocalConnection?

  package init(
    buildSystemKind: BuildSystemKind?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    buildSystemTestHooks: BuildSystemTestHooks
  ) async {
    self.fallbackBuildSystem = FallbackBuildSystem(options: options.fallbackBuildSystemOrDefault)
    self.toolchainRegistry = toolchainRegistry
    self.options = options
    self.projectRoot = buildSystemKind?.projectRoot
    connectionFromBuildSystemToSourceKitLSP = LocalConnection(receiverName: "BuildSystemManager")
    connectionFromBuildSystemToSourceKitLSP.start(handler: self)
    self.buildSystem = await BuiltInBuildSystemAdapter(
      buildSystemKind: buildSystemKind,
      toolchainRegistry: toolchainRegistry,
      options: options,
      buildSystemTestHooks: buildSystemTestHooks,
      connectionToSourceKitLSP: connectionFromBuildSystemToSourceKitLSP
    )
    if let buildSystem {
      let connectionFromSourceKitLSPToBuildSystem = LocalConnection(receiverName: "\(type(of: buildSystem))")
      connectionFromSourceKitLSPToBuildSystem.start(handler: buildSystem)
      self.connectionToBuildSystem = connectionFromSourceKitLSPToBuildSystem
    } else {
      self.connectionToBuildSystem = nil
    }
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
      guard !changedWatchedFiles.isEmpty else {
        return
      }
      await delegate.filesDependenciesUpdated(changedWatchedFiles)
    }

    // FIXME: (BSP migration) Forward file watch patterns from this initialize request to the client
    initializeResult = Task { () -> InitializeBuildResponse? in
      guard let connectionToBuildSystem else {
        return nil
      }
      guard let buildSystemKind else {
        logger.fault("Created build system without a build system kind?")
        return nil
      }
      return await orLog("Initializing build system") {
        try await connectionToBuildSystem.send(
          InitializeBuildRequest(
            displayName: "SourceKit-LSP",
            version: "unknown",
            bspVersion: "2.2.0",
            rootUri: URI(buildSystemKind.projectRoot.asURL),
            capabilities: BuildClientCapabilities(languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift])
          )
        )
      }
    }
  }

  deinit {
    connectionFromBuildSystemToSourceKitLSP.close()
    connectionToBuildSystem?.close()
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    connectionToBuildSystem?.send(BuildServerProtocol.DidChangeWatchedFilesNotification(changes: events))

    var targetsWithUpdatedDependencies: Set<BuildTargetIdentifier> = []
    // If a Swift file within a target is updated, reload all the other files within the target since they might be
    // referring to a function in the updated file.
    let targetsWithChangedSwiftFiles =
      await events
      .filter { $0.uri.fileURL?.pathExtension == "swift" }
      .asyncFlatMap { await self.targets(for: $0.uri) }
    targetsWithUpdatedDependencies.formUnion(targetsWithChangedSwiftFiles)

    // If a `.swiftmodule` file is updated, this means that we have performed a build / are
    // performing a build and files that depend on this module have updated dependencies.
    // We don't have access to the build graph from the SwiftPM API offered to SourceKit-LSP to figure out which files
    // depend on the updated module, so assume that all files have updated dependencies.
    // The file watching here is somewhat fragile as well because it assumes that the `.swiftmodule` files are being
    // written to a directory within the workspace root. This is not necessarily true if the user specifies a build
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

  package let messageHandlingQueue = AsyncQueue<BuildSystemMessageDependencyTracker>()

  package func handleImpl(_ notification: some NotificationType) async {
    switch notification {
    case let notification as DidChangeBuildTargetNotification:
      await self.didChangeBuildTarget(notification: notification)
    case let notification as BuildServerProtocol.LogMessageNotification:
      await self.logMessage(notification: notification)
    case let notification as BuildServerProtocol.WorkDoneProgress:
      await self.workDoneProgress(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method)")
    }
  }

  package func handleImpl<Request: RequestType>(_ request: RequestAndReply<Request>) async {
    switch request {
    case let request as RequestAndReply<BuildServerProtocol.CreateWorkDoneProgressRequest>:
      await request.reply { try await self.createWorkDoneProgress(request: request.params) }
    default:
      await request.reply { throw ResponseError.methodNotFound(Request.method) }
    }
  }

  private func createWorkDoneProgress(
    request: BuildServerProtocol.CreateWorkDoneProgressRequest
  ) async throws -> BuildServerProtocol.CreateWorkDoneProgressRequest.Response {
    guard let delegate else {
      throw ResponseError.unknown("Connection to client closed")
    }
    guard await delegate.clientSupportsWorkDoneProgress else {
      throw ResponseError.unknown("Client does not support work done progress")
    }
    await delegate.waitUntilInitialized()
    return try await delegate.sendRequestToClient(request as LanguageServerProtocol.CreateWorkDoneProgressRequest)
  }

  private func workDoneProgress(notification: BuildServerProtocol.WorkDoneProgress) async {
    guard let delegate else {
      logger.fault("Ignoring work done progress form build system because connection to client closed")
      return
    }
    await delegate.waitUntilInitialized()
    delegate.sendNotificationToClient(notification as LanguageServerProtocol.WorkDoneProgress)
  }

  /// - Note: Needed so we can set the delegate from a different isolation context.
  package func setDelegate(_ delegate: BuildSystemManagerDelegate?) {
    self.delegate = delegate
  }

  /// Returns the toolchain that should be used to process the given document.
  package func toolchain(
    for uri: DocumentURI,
    in target: BuildTargetIdentifier?,
    language: Language
  ) async -> Toolchain? {
    let toolchainPath = await orLog("Getting toolchain from build targets") { () -> AbsolutePath? in
      guard let target else {
        return nil
      }
      let targets = try await self.buildTargets()
      guard let target = targets[target]?.target else {
        logger.error("Failed to find target \(target.forLogging) to determine toolchain")
        return nil
      }
      guard target.dataKind == .sourceKit, case .dictionary(let data) = target.data else {
        return nil
      }
      guard let toolchain = SourceKitBuildTarget(fromLSPDictionary: data).toolchain else {
        return nil
      }
      guard let toolchainUrl = toolchain.fileURL else {
        logger.error("Toolchain is not a file URL")
        return nil
      }
      return try AbsolutePath(validating: toolchainUrl.path)
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

  /// - Note: Needed so we can set the delegate from a different isolation context.
  package func setMainFilesProvider(_ mainFilesProvider: MainFilesProvider?) {
    self.mainFilesProvider = mainFilesProvider
  }

  /// Ask the build system if it explicitly specifies a language for this document. Return `nil` if it does not.
  private func languageInferredFromBuildSystem(
    for document: DocumentURI,
    in target: BuildTargetIdentifier
  ) async throws -> Language? {
    let sourcesItems = try await self.sourceFiles(in: [target])
    let sourceFiles = sourcesItems.flatMap(\.sources)
    var result: Language? = nil
    for sourceFile in sourceFiles {
      guard sourceFile.uri == document, sourceFile.dataKind == .sourceKit, case .dictionary(let data) = sourceFile.data,
        let sourceKitData = SourceKitSourceItemData(fromLSPDictionary: data),
        let language = sourceKitData.language
      else {
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
    let language = await orLog("Getting source files to determine default language") {
      try await languageInferredFromBuildSystem(for: document, in: target)
    }
    if let language {
      return language
    }
    switch document.fileURL?.pathExtension {
    case "c": return .c
    case "cpp", "cc", "cxx", "hpp": return .cpp
    case "m": return .objective_c
    case "mm", "h": return .objective_cpp
    case "swift": return .swift
    default: return nil
    }
  }

  /// Returns all the `ConfiguredTarget`s that the document is part of.
  package func targets(for document: DocumentURI) async -> Set<BuildTargetIdentifier> {
    return await orLog("Getting targets for source file") {
      var result: Set<BuildTargetIdentifier> = []
      let filesAndDirectories = try await sourceFilesAndDirectories(includeNonBuildableFiles: true)
      if let targets = filesAndDirectories.files[document]?.targets {
        result.formUnion(targets)
      }
      if !filesAndDirectories.directories.isEmpty,
        let documentPath = AbsolutePath(validatingOrNil: document.fileURL?.path)
      {
        for (directory, info) in filesAndDirectories.directories {
          guard let directoryPath = AbsolutePath(validatingOrNil: directory.fileURL?.path) else {
            continue
          }
          if documentPath.isDescendantOfOrEqual(to: directoryPath) {
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
      let buildSettings = await buildSettings(for: document, in: target, language: language)
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
        let moduleNameArgument = buildSettings.compilerArguments.last(where: {
          $0.starts(with: "-fmodule-name=")
        }),
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
  private func buildSettingsFromPrimaryBuildSystem(
    for document: DocumentURI,
    in target: BuildTargetIdentifier?,
    language: Language
  ) async throws -> FileBuildSettings? {
    guard let connectionToBuildSystem, let target else {
      return nil
    }
    let request = SourceKitOptionsRequest(textDocument: TextDocumentIdentifier(document), target: target)

    // TODO: We should only wait `fallbackSettingsTimeout` for build settings
    // and return fallback afterwards.
    // For now, this should be fine because all build systems return
    // very quickly from `settings(for:language:)`.
    // https://github.com/apple/sourcekit-lsp/issues/1181
    let response = try await cachedSourceKitOptions.get(request) { request in
      try await connectionToBuildSystem.send(request)
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
  /// Only call this method if it is known that `document` is a main file. Prefer `buildSettingsInferredFromMainFile`
  /// otherwise. If `document` is a header file, this will most likely return fallback settings because header files
  /// don't have build settings by themselves.
  package func buildSettings(
    for document: DocumentURI,
    in target: BuildTargetIdentifier?,
    language: Language
  ) async -> FileBuildSettings? {
    do {
      if let buildSettings = try await buildSettingsFromPrimaryBuildSystem(
        for: document,
        in: target,
        language: language
      ) {
        return buildSettings
      }
    } catch {
      logger.error("Getting build settings failed: \(error.forLogging)")
    }

    guard var settings = await fallbackBuildSystem.buildSettings(for: document, language: language) else {
      return nil
    }
    if buildSystem == nil {
      // If there is no build system and we only have the fallback build system,
      // we will never get real build settings. Consider the build settings
      // non-fallback.
      settings.isFallback = false
    }
    return settings
  }

  /// Returns the build settings for the given document.
  ///
  /// If the document doesn't have builds settings by itself, eg. because it is
  /// a C header file, the build settings will be inferred from the primary main
  /// file of the document. In practice this means that we will compute the build
  /// settings of a C file that includes the header and replace any file
  /// references to that C file in the build settings by the header file.
  package func buildSettingsInferredFromMainFile(
    for document: DocumentURI,
    language: Language
  ) async -> FileBuildSettings? {
    let mainFile = await mainFile(for: document, language: language)
    let target = await canonicalTarget(for: mainFile)
    guard var settings = await buildSettings(for: mainFile, in: target, language: language) else {
      return nil
    }
    if mainFile != document {
      // If the main file isn't the file itself, we need to patch the build settings
      // to reference `document` instead of `mainFile`.
      settings = settings.patching(newFile: document.pseudoPath, originalFile: mainFile.pseudoPath)
    }
    await BuildSettingsLogger.shared.log(settings: settings, for: document)
    return settings
  }

  package func waitForUpToDateBuildGraph() async {
    await orLog("Waiting for build system updates") {
      let _: VoidResponse? = try await connectionToBuildSystem?.send(WaitForBuildSystemUpdatesRequest())
    }
    // Handle any messages the build system might have sent us while updating.
    await self.messageHandlingQueue.async(metadata: .stateChange) {}.valuePropagatingCancellation
  }

  /// The root targets of the project have depth of 0 and all target dependencies have a greater depth than the target
  // itself.
  private func targetDepths(for buildTargets: [BuildTarget]) -> [BuildTargetIdentifier: Int] {
    var nonRoots: Set<BuildTargetIdentifier> = []
    for buildTarget in buildTargets {
      nonRoots.formUnion(buildTarget.dependencies)
    }
    let targetsById = Dictionary(elements: buildTargets, keyedBy: \.id)
    var depths: [BuildTargetIdentifier: Int] = [:]
    let rootTargets = buildTargets.filter { !nonRoots.contains($0.id) }
    var worksList: [(target: BuildTargetIdentifier, depth: Int)] = rootTargets.map { ($0.id, 0) }
    while let (target, depth) = worksList.popLast() {
      depths[target] = max(depths[target, default: 0], depth)
      for dependency in targetsById[target]?.dependencies ?? [] {
        // Check if we have already recorded this target with a greater depth, in which case visiting it again will
        // not increase its depth or any of its children.
        if depths[target, default: 0] < depth + 1 {
          worksList.append((dependency, depth + 1))
        }
      }
    }
    return depths
  }

  /// Sort the targets so that low-level targets occur before high-level targets.
  ///
  /// This sorting is best effort but allows the indexer to prepare and index low-level targets first, which allows
  /// index data to be available earlier.
  ///
  /// `nil` if the build system doesn't support topological sorting of targets.
  package func topologicalSort(of targets: [BuildTargetIdentifier]) async throws -> [BuildTargetIdentifier]? {
    guard let buildTargets = await orLog("Getting build targets for topological sort", { try await buildTargets() })
    else {
      return nil
    }

    return targets.sorted { (lhs: BuildTargetIdentifier, rhs: BuildTargetIdentifier) -> Bool in
      return (buildTargets[lhs]?.depth ?? 0) > (buildTargets[rhs]?.depth ?? 0)
    }
  }

  /// Returns the list of targets that might depend on the given target and that need to be re-prepared when a file in
  /// `target` is modified.
  package func targets(dependingOn targetIds: Set<BuildTargetIdentifier>) async -> [BuildTargetIdentifier] {
    guard
      let buildTargets = await orLog("Getting build targets for dependencies", { try await self.buildTargets().values })
    else {
      return []
    }
    return buildTargets.filter { $0.target.dependencies.contains(anyIn: targetIds) }.map { $0.target.id }
  }

  package func prepare(targets: Set<BuildTargetIdentifier>) async throws {
    let _: VoidResponse? = try await connectionToBuildSystem?.send(
      PrepareTargetsRequest(targets: targets.sorted { $0.uri.stringValue < $1.uri.stringValue })
    )
    await orLog("Calling fileDependenciesUpdated") {
      let filesInPreparedTargets = try await self.sourceFiles(in: targets).flatMap(\.sources).map(\.uri)
      await filesDependenciesUpdatedDebouncer.scheduleCall(Set(filesInPreparedTargets))
    }
  }

  package func registerForChangeNotifications(for uri: DocumentURI, language: Language) async {
    logger.debug("registerForChangeNotifications(\(uri.forLogging))")
    let mainFile = await mainFile(for: uri, language: language)
    self.watchedFiles[uri] = (mainFile, language)
  }

  package func unregisterForChangeNotifications(for uri: DocumentURI) async {
    self.watchedFiles[uri] = nil
  }

  package func buildTargets() async throws -> [BuildTargetIdentifier: (target: BuildTarget, depth: Int)] {
    guard let connectionToBuildSystem else {
      return [:]
    }

    let request = BuildTargetsRequest()
    let result = try await cachedBuildTargets.get(request) { request in
      let buildTargets = try await connectionToBuildSystem.send(request).targets
      let depths = await self.targetDepths(for: buildTargets)
      var result: [BuildTargetIdentifier: (target: BuildTarget, depth: Int)] = [:]
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
        result[buildTarget.id] = (buildTarget, depth)
      }
      return result
    }
    return result
  }

  package func sourceFiles(in targets: Set<BuildTargetIdentifier>) async throws -> [SourcesItem] {
    guard let connectionToBuildSystem else {
      return []
    }

    // If we have a cached request for a superset of the targets, serve the result from that cache entry.
    let fromSuperset = await orLog("Getting source files from superset request") {
      try await cachedTargetSources.get { request in
        targets.isSubset(of: request.targets)
      } transform: { response in
        return BuildTargetSourcesResponse(items: response.items.filter { targets.contains($0.target) })
      }
    }
    if let fromSuperset {
      return fromSuperset.items
    }

    // Sort targets to help cache hits if we have two calls to `sourceFiles` with targets in different orders.
    let sortedTargets = targets.sorted { $0.uri.stringValue < $1.uri.stringValue }
    let request = BuildTargetSourcesRequest(targets: sortedTargets)
    let response = try await cachedTargetSources.get(request) { request in
      try await connectionToBuildSystem.send(request)
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

    return try await cachedSourceFilesAndDirectories.get(key) { key in
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
}

extension BuildSystemManager {
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

  private func didChangeBuildTarget(notification: DidChangeBuildTargetNotification) async {
    let updatedTargets: Set<BuildTargetIdentifier>? =
      if let changes = notification.changes {
        Set(changes.map(\.target))
      } else {
        nil
      }
    self.cachedSourceKitOptions.clear { cacheKey in
      guard let updatedTargets else {
        // All targets might have changed
        return true
      }
      return updatedTargets.contains(cacheKey.target)
    }
    self.cachedBuildTargets.clearAll()
    self.cachedTargetSources.clear { cacheKey in
      guard let updatedTargets else {
        // All targets might have changed
        return true
      }
      return !updatedTargets.intersection(cacheKey.targets).isEmpty
    }
    self.cachedSourceFilesAndDirectories.clearAll()

    await delegate?.buildTargetsChanged(notification.changes)
    // FIXME: (BSP Migration) Communicate that the build target has changed to the `BuildSystemManagerDelegate` and make
    // it responsible for figuring out which files are affected.
    await delegate?.fileBuildSettingsChanged(Set(watchedFiles.keys))
  }

  private func logMessage(notification: BuildServerProtocol.LogMessageNotification) async {
    let message =
      if let taskID = notification.task?.id {
        prefixMessageWithTaskEmoji(taskID: taskID, message: notification.message)
      } else {
        notification.message
      }
    delegate?.sendNotificationToClient(
      LanguageServerProtocol.LogMessageNotification(type: .info, message: message, logName: "SourceKit-LSP: Indexing")
    )
  }
}

extension BuildSystemManager {
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
}

extension BuildSystemManager {

  /// Returns the main file used for `uri`, if this is a registered file.
  ///
  /// For testing purposes only.
  package func cachedMainFile(for uri: DocumentURI) -> DocumentURI? {
    return self.watchedFiles[uri]?.mainFile
  }
}

// MARK: - Build settings logger

/// Shared logger that only logs build settings for a file once unless they change
package actor BuildSettingsLogger {
  package static let shared = BuildSettingsLogger()

  private var loggedSettings: [DocumentURI: FileBuildSettings] = [:]

  package func log(level: LogLevel = .default, settings: FileBuildSettings, for uri: DocumentURI) {
    guard loggedSettings[uri] != settings else {
      return
    }
    loggedSettings[uri] = settings
    Self.log(level: level, settings: settings, for: uri)
  }

  /// Log the given build settings.
  ///
  /// In contrast to the instance method `log`, this will always log the build settings. The instance method only logs
  /// the build settings if they have changed.
  package static func log(level: LogLevel = .default, settings: FileBuildSettings, for uri: DocumentURI) {
    let log = """
      Compiler Arguments:
      \(settings.compilerArguments.joined(separator: "\n"))

      Working directory:
      \(settings.workingDirectory ?? "<nil>")
      """

    let chunks = splitLongMultilineMessage(message: log)
    for (index, chunk) in chunks.enumerated() {
      logger.log(
        level: level,
        """
        Build settings for \(uri.forLogging) (\(index + 1)/\(chunks.count))
        \(chunk)
        """
      )
    }
  }
}
