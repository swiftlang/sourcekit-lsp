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

fileprivate class RequestCache<Request: RequestType & Hashable> {
  private var storage: [Request: Task<Request.Response, Error>] = [:]

  func get(
    _ key: Request,
    isolation: isolated any Actor = #isolation,
    compute: @Sendable @escaping (Request) async throws(Error) -> Request.Response
  ) async throws(Error) -> Request.Response {
    let task: Task<Request.Response, Error>
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

  func clear(where condition: (Request) -> Bool, isolation: isolated any Actor = #isolation) {
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
package actor BuildSystemManager: BuiltInBuildSystemAdapterDelegate {
  /// The files for which the delegate has requested change notifications, ie.
  /// the files for which the delegate wants to get `filesDependenciesUpdated`
  /// callbacks if the file's build settings.
  private var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  /// The underlying primary build system.
  ///
  /// - Important: The only time this should be modified is in the initializer. Afterwards, it must be constant.
  private(set) package var buildSystem: BuiltInBuildSystemAdapter?

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

  private var cachedTargetsForDocument = RequestCache<InverseSourcesRequest>()

  private var cachedSourceKitOptions = RequestCache<SourceKitOptionsRequest>()

  private var cachedBuildTargets = RequestCache<BuildTargetsRequest>()

  private var cachedTargetSources = RequestCache<BuildTargetSourcesRequest>()

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

  package init(
    buildSystemKind: BuildSystemKind?,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    swiftpmTestHooks: SwiftPMTestHooks,
    reloadPackageStatusCallback: @Sendable @escaping (ReloadPackageStatus) async -> Void
  ) async {
    self.fallbackBuildSystem = FallbackBuildSystem(options: options.fallbackBuildSystemOrDefault)
    self.toolchainRegistry = toolchainRegistry
    self.options = options
    self.projectRoot = buildSystemKind?.projectRoot
    self.buildSystem = await BuiltInBuildSystemAdapter(
      buildSystemKind: buildSystemKind,
      toolchainRegistry: toolchainRegistry,
      options: options,
      swiftpmTestHooks: swiftpmTestHooks,
      reloadPackageStatusCallback: reloadPackageStatusCallback,
      messageHandler: self
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
      guard !changedWatchedFiles.isEmpty else {
        return
      }
      await delegate.filesDependenciesUpdated(changedWatchedFiles)
    }
    initializeResult = Task { () -> InitializeBuildResponse? in
      guard let buildSystem else {
        return nil
      }
      guard let buildSystemKind else {
        logger.fault("Created build system without a build system kind?")
        return nil
      }
      return await orLog("Initializing build system") {
        try await buildSystem.send(
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

  package func filesDidChange(_ events: [FileEvent]) async {
    await self.buildSystem?.send(BuildServerProtocol.DidChangeWatchedFilesNotification(changes: events))

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
      let targets = await orLog("Getting build targets") {
        try await self.buildTargets()
      }
      targetsWithUpdatedDependencies.formUnion(targets?.map(\.id) ?? [])
    }

    var filesWithUpdatedDependencies: Set<DocumentURI> = []

    await orLog("Getting source files in targets") {
      let sourceFiles = try await self.sourceFiles(in: Array(Set(targetsWithUpdatedDependencies)))
      filesWithUpdatedDependencies.formUnion(sourceFiles.flatMap(\.sources).map(\.uri))
    }

    if let mainFilesProvider {
      var mainFiles = await Set(events.asyncFlatMap { await mainFilesProvider.mainFilesContainingFile($0.uri) })
      mainFiles.subtract(events.map(\.uri))
      filesWithUpdatedDependencies.formUnion(mainFiles)
    }

    await self.filesDependenciesUpdatedDebouncer.scheduleCall(filesWithUpdatedDependencies)
  }

  /// Implementation of `MessageHandler`, handling notifications from the build system.
  ///
  /// - Important: Do not call directly.
  package func handle(_ notification: some LanguageServerProtocol.NotificationType) async {
    switch notification {
    case let notification as DidChangeBuildTargetNotification:
      await self.didChangeBuildTarget(notification: notification)
    case let notification as BuildServerProtocol.LogMessageNotification:
      await self.logMessage(notification: notification)
    default:
      logger.error("Ignoring unknown notification \(type(of: notification).method)")
    }
  }

  /// Implementation of `MessageHandler`, handling requests from the build system.
  ///
  /// - Important: Do not call directly.
  package nonisolated func handle<R: RequestType>(_ request: R) async throws -> R.Response {
    throw ResponseError.methodNotFound(R.method)
  }

  /// - Note: Needed so we can set the delegate from a different isolation context.
  package func setDelegate(_ delegate: BuildSystemManagerDelegate?) {
    self.delegate = delegate
  }

  /// Returns the toolchain that should be used to process the given document.
  package func toolchain(for uri: DocumentURI, _ language: Language) async -> Toolchain? {
    if let toolchain = await buildSystem?.underlyingBuildSystem.toolchain(for: uri, language) {
      return toolchain
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
  package func targets(for document: DocumentURI) async -> [BuildTargetIdentifier] {
    guard let buildSystem else {
      return []
    }

    // FIXME: (BSP migration) Only use `InverseSourcesRequest` if the BSP server declared it can handle it in the
    // capabilities
    let request = InverseSourcesRequest(textDocument: TextDocumentIdentifier(uri: document))
    do {
      let response = try await cachedTargetsForDocument.get(request) { document in
        return try await buildSystem.send(request)
      }
      return response.targets
    } catch {
      return []
    }
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
    guard let buildSystem, let target else {
      return nil
    }
    let request = SourceKitOptionsRequest(textDocument: TextDocumentIdentifier(uri: document), target: target)

    // TODO: We should only wait `fallbackSettingsTimeout` for build settings
    // and return fallback afterwards.
    // For now, this should be fine because all build systems return
    // very quickly from `settings(for:language:)`.
    // https://github.com/apple/sourcekit-lsp/issues/1181
    let response = try await cachedSourceKitOptions.get(request) { request in
      try await buildSystem.send(request)
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
    await self.buildSystem?.underlyingBuildSystem.waitForUpToDateBuildGraph()
  }

  package func topologicalSort(of targets: [BuildTargetIdentifier]) async throws -> [BuildTargetIdentifier]? {
    return await buildSystem?.underlyingBuildSystem.topologicalSort(of: targets)
  }

  package func targets(dependingOn targets: [BuildTargetIdentifier]) async -> [BuildTargetIdentifier]? {
    return await buildSystem?.underlyingBuildSystem.targets(dependingOn: targets)
  }

  package func prepare(
    targets: [BuildTargetIdentifier],
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void
  ) async throws {
    let _: VoidResponse? = try await buildSystem?.send(PrepareTargetsRequest(targets: targets))
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

  package func buildTargets() async throws -> [BuildTarget] {
    guard let buildSystem else {
      return []
    }

    let request = BuildTargetsRequest()
    let response = try await cachedBuildTargets.get(request) { request in
      try await buildSystem.send(request)
    }
    return response.targets
  }

  package func sourceFiles(in targets: [BuildTargetIdentifier]) async throws -> [SourcesItem] {
    guard let buildSystem else {
      return []
    }

    // FIXME: (BSP migration) If we have a cached request for a superset of the targets, serve the result from that
    // cache entry.
    let request = BuildTargetSourcesRequest.init(targets: targets)
    let response = try await cachedTargetSources.get(request) { request in
      try await buildSystem.send(request)
    }
    return response.items
  }

  package func sourceFiles() async throws -> [SourceFileInfo] {
    // FIXME: (BSP Migration): Consider removing this method and letting callers get all targets first and then
    // retrieving the source files for those targets.
    // FIXME: (BSP Migration) Handle source files that are in multiple targets
    let targets = try await self.buildTargets()
    let targetsById = Dictionary(elements: targets, keyedBy: \.id)
    let sourceFiles = try await self.sourceFiles(in: targets.map(\.id)).flatMap { sourcesItem in
      let target = targetsById[sourcesItem.target]
      return sourcesItem.sources.map { sourceItem in
        SourceFileInfo(
          uri: sourceItem.uri,
          isPartOfRootProject: !(target?.tags.contains(.dependency) ?? false),
          mayContainTests: target?.tags.contains(.test) ?? true
        )
      }
    }
    return sourceFiles
  }

  package func testFiles() async throws -> [DocumentURI] {
    return try await sourceFiles().compactMap { (info: SourceFileInfo) -> DocumentURI? in
      guard info.isPartOfRootProject, info.mayContainTests else {
        return nil
      }
      return info.uri
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
    // Every `DidChangeBuildTargetNotification` notification needs to invalidate the cache since the changed target
    // might gained a source file.
    self.cachedTargetsForDocument.clearAll()

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

    await delegate?.buildTargetsChanged(notification.changes)
    // FIXME: (BSP Migration) Communicate that the build target has changed to the `BuildSystemManagerDelegate` and make
    // it responsible for figuring out which files are affected.
    await delegate?.fileBuildSettingsChanged(Set(watchedFiles.keys))
  }

  private func logMessage(notification: BuildServerProtocol.LogMessageNotification) async {
    // FIXME: (BSP Integration) Remove the restriction that task IDs need to have a raw value that can be parsed by
    // `IndexTaskID.init`.
    guard let task = notification.task, let taskID = IndexTaskID(rawValue: task.id) else {
      logger.error("Ignoring log message notification with unknown task \(notification.task?.id ?? "<nil>")")
      return
    }
    delegate?.logMessageToIndexLog(taskID: taskID, message: notification.message)
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
