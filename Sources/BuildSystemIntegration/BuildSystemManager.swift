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
  var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  /// The underlying primary build system.
  ///
  /// - Important: The only time this should be modified is in the initializer. Afterwards, it must be constant.
  private(set) package var buildSystem: BuiltInBuildSystemAdapter?

  /// The fallback build system. If present, used when the `buildSystem` is not
  /// set or cannot provide settings.
  let fallbackBuildSystem: FallbackBuildSystem

  /// Provider of file to main file mappings.
  var mainFilesProvider: MainFilesProvider?

  /// Build system delegate that will receive notifications about setting changes, etc.
  private weak var delegate: BuildSystemManagerDelegate?

  /// The list of toolchains that are available.
  ///
  /// Used to determine which toolchain to use for a given document.
  private let toolchainRegistry: ToolchainRegistry

  private var cachedTargetsForDocument = RequestCache<InverseSourcesRequest>()

  private var cachedSourceKitOptions = RequestCache<SourceKitOptionsRequest>()

  /// The root of the project that this build system manages. For example, for SwiftPM packages, this is the folder
  /// containing Package.swift. For compilation databases it is the root folder based on which the compilation database
  /// was found.
  package let projectRoot: AbsolutePath?

  package var supportsPreparation: Bool {
    get async {
      return await buildSystem?.underlyingBuildSystem.supportsPreparation ?? false
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
    self.projectRoot = buildSystemKind?.projectRoot
    self.buildSystem = await BuiltInBuildSystemAdapter(
      buildSystemKind: buildSystemKind,
      toolchainRegistry: toolchainRegistry,
      options: options,
      swiftpmTestHooks: swiftpmTestHooks,
      reloadPackageStatusCallback: reloadPackageStatusCallback,
      messageHandler: self
    )
    await self.buildSystem?.underlyingBuildSystem.setDelegate(self)
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    await self.buildSystem?.send(BuildServerProtocol.DidChangeWatchedFilesNotification(changes: events))
    if let mainFilesProvider {
      var mainFiles = await Set(events.asyncFlatMap { await mainFilesProvider.mainFilesContainingFile($0.uri) })
      mainFiles.subtract(events.map(\.uri))
      await self.filesDependenciesUpdated(mainFiles)
    }
  }

  /// Implementation of `MessageHandler`, handling notifications from the build system.
  ///
  /// - Important: Do not call directly.
  package func handle(_ notification: some LanguageServerProtocol.NotificationType) async {
    switch notification {
    case let notification as DidChangeBuildTargetNotification:
      await self.didChangeBuildTarget(notification: notification)
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

  /// Returns the language that a document should be interpreted in for background tasks where the editor doesn't
  /// specify the document's language.
  package func defaultLanguage(for document: DocumentURI) async -> Language? {
    if let defaultLanguage = await buildSystem?.underlyingBuildSystem.defaultLanguage(for: document) {
      return defaultLanguage
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
    guard let language = await self.defaultLanguage(for: document),
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

  package func scheduleBuildGraphGeneration() async throws {
    try await self.buildSystem?.underlyingBuildSystem.scheduleBuildGraphGeneration()
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
    try await buildSystem?.underlyingBuildSystem.prepare(targets: targets, logMessageToIndexLog: logMessageToIndexLog)
  }

  package func registerForChangeNotifications(for uri: DocumentURI, language: Language) async {
    logger.debug("registerForChangeNotifications(\(uri.forLogging))")
    let mainFile = await mainFile(for: uri, language: language)
    self.watchedFiles[uri] = (mainFile, language)

    // Register for change notifications of the main file in the underlying build
    // system. That way, iff the main file changes, we will also notify the
    // delegate about build setting changes of all header files that are based
    // on that main file.
    await buildSystem?.underlyingBuildSystem.registerForChangeNotifications(for: mainFile)
  }

  package func unregisterForChangeNotifications(for uri: DocumentURI) async {
    guard let mainFile = self.watchedFiles[uri]?.mainFile else {
      logger.fault("Unbalanced calls for registerForChangeNotifications and unregisterForChangeNotifications")
      return
    }
    self.watchedFiles[uri] = nil

    if watchedFilesReferencing(mainFiles: [mainFile]).isEmpty {
      // Nobody is interested in this main file anymore.
      // We are no longer interested in change notifications for it.
      await self.buildSystem?.underlyingBuildSystem.unregisterForChangeNotifications(for: mainFile)
    }
  }

  package func sourceFiles() async -> [SourceFileInfo] {
    return await buildSystem?.underlyingBuildSystem.sourceFiles() ?? []
  }

  package func testFiles() async -> [DocumentURI] {
    return await sourceFiles().compactMap { (info: SourceFileInfo) -> DocumentURI? in
      guard info.isPartOfRootProject, info.mayContainTests else {
        return nil
      }
      return info.uri
    }
  }
}

extension BuildSystemManager: BuildSystemDelegate {
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

  package func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) async {
    // Empty changes --> assume everything has changed.
    guard !changedFiles.isEmpty else {
      if let delegate = self.delegate {
        await delegate.filesDependenciesUpdated(changedFiles)
      }
      return
    }

    // Need to map the changed main files back into changed watch files.
    let changedWatchedFiles = watchedFilesReferencing(mainFiles: changedFiles)
    if let delegate, !changedWatchedFiles.isEmpty {
      await delegate.filesDependenciesUpdated(changedWatchedFiles)
    }
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

    await delegate?.buildTargetsChanged(notification.changes)
    // FIXME: (BSP Migration) Communicate that the build target has changed to the `BuildSystemManagerDelegate` and make
    // it responsible for figuring out which files are affected.
    await delegate?.fileBuildSettingsChanged(Set(watchedFiles.keys))
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
