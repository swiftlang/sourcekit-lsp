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

import LanguageServerProtocol
import BuildServerProtocol
import LSPLogging
import Dispatch

import struct TSCBasic.AbsolutePath

/// Status for a given main file.
enum MainFileStatus: Equatable {
  /// Waiting for the `BuildSystem` to return settings.
  case waiting

  /// No response from `BuildSystem` yet, using arguments from the fallback build system.
  case waitingUsingFallback(FileBuildSettings)

  /// Two cases here:
  /// - Primary build system gave us fallback arguments to use.
  /// - Primary build system didn't handle the file, using arguments from the fallback build system.
  /// No longer waiting.
  case fallback(FileBuildSettings)

  /// Using settings from the primary `BuildSystem`.
  case primary(FileBuildSettings)

  /// No settings provided by primary and fallback `BuildSystem`s.
  case unsupported
}

extension MainFileStatus {
  /// Whether fallback build settings are being used.
  /// If no build settings are available, returns false.
  var usingFallbackSettings: Bool {
    switch self {
    case .waiting: return false
    case .unsupported: return false
    case .waitingUsingFallback(_): return true
    case .fallback(_): return true
    case .primary(_): return false
    }
  }

  /// The active build settings, if any.
  var buildSettings: FileBuildSettings? {
    switch self {
    case .waiting: return nil
    case .unsupported: return nil
    case .waitingUsingFallback(let settings): return settings
    case .fallback(let settings): return settings
    case .primary(let settings): return settings
    }
  }

  /// Corresponding change from this status, if any.
  var buildSettingsChange: FileBuildSettingsChange? {
    switch self {
    case .waiting: return nil
    case .unsupported: return .removedOrUnavailable
    case .waitingUsingFallback(let settings): return .fallback(settings)
    case .fallback(let settings): return .fallback(settings)
    case .primary(let settings): return .modified(settings)
    }
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
public actor BuildSystemManager {
  /// The set of watched files, along with their main file and language.
  var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  /// Statuses for each main file, containing build settings from the build systems.
  var mainFileStatuses: [DocumentURI: MainFileStatus] = [:]

  /// The underlying primary build system.
  let buildSystem: BuildSystem?

  /// Timeout before fallback build settings are used.
  let fallbackSettingsTimeout: DispatchTimeInterval

  /// The fallback build system. If present, used when the `buildSystem` is not
  /// set or cannot provide settings.
  let fallbackBuildSystem: FallbackBuildSystem?

  /// Provider of file to main file mappings.
  var _mainFilesProvider: MainFilesProvider?

  /// Build system delegate that will receive notifications about setting changes, etc.
  var _delegate: BuildSystemDelegate?

  /// Create a BuildSystemManager that wraps the given build system. The new
  /// manager will modify the delegate of the underlying build system.
  public init(buildSystem: BuildSystem?, fallbackBuildSystem: FallbackBuildSystem?,
              mainFilesProvider: MainFilesProvider?, fallbackSettingsTimeout: DispatchTimeInterval = .seconds(3)) async {
    let buildSystemHasDelegate = await buildSystem?.delegate != nil
    precondition(!buildSystemHasDelegate)
    self.buildSystem = buildSystem
    self.fallbackBuildSystem = fallbackBuildSystem
    self._mainFilesProvider = mainFilesProvider
    self.fallbackSettingsTimeout = fallbackSettingsTimeout
    await self.buildSystem?.setDelegate(self)
  }

  public func filesDidChange(_ events: [FileEvent]) async {
    await self.buildSystem?.filesDidChange(events)
    self.fallbackBuildSystem?.filesDidChange(events)
  }
}

extension BuildSystemManager {
  public var delegate: BuildSystemDelegate? {
    get { _delegate }
    set { _delegate = newValue }
  }

  /// - Note: Needed so we can set the delegate from a different isolation context.
  public func setDelegate(_ delegate: BuildSystemDelegate?) {
    self.delegate = delegate
  }

  public var mainFilesProvider: MainFilesProvider? {
    get { _mainFilesProvider}
    set { _mainFilesProvider = newValue }
  }

  /// - Note: Needed so we can set the delegate from a different isolation context.
  public func setMainFilesProvider(_ mainFilesProvider: MainFilesProvider?) {
    self.mainFilesProvider = mainFilesProvider
  }

  /// Get the build settings for the given document, assuming it has the given
  /// language.
  ///
  /// Returns `nil` if no build settings are available in the build system and
  /// no fallback build settings can be computed.
  ///
  /// `isFallback` is `true` if the build settings couldn't be computed and
  /// fallback settings are used. These fallback settings are most likely not
  /// correct and provide limited semantic functionality.
  public func buildSettings(
    for document: DocumentURI,
    language: Language
  ) async -> (buildSettings: FileBuildSettings, isFallback: Bool)? {
    do {
      // FIXME: (async) We should only wait `fallbackSettingsTimeout` for build
      // settings and return fallback afterwards. I am not sure yet, how best to
      // implement that with Swift concurrency.
      // For now, this should be fine because all build systems return
      // very quickly from `settings(for:language:)`.
      if let settings = try await buildSystem?.buildSettings(for: document, language: language) {
        return (buildSettings: settings, isFallback: false)
      }
    } catch {
      log("Getting build settings failed: \(error)")
    }
    if let settings = fallbackBuildSystem?.buildSettings(for: document, language: language) {
      // If there is no build system and we only have the fallback build system,
      // we will never get real build settings. Consider the build settings
      // non-fallback.
      return (buildSettings: settings, isFallback: buildSystem != nil)
    } else {
      return nil
    }
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) async {
    log("registerForChangeNotifications(\(uri.pseudoPath))")
    let mainFile: DocumentURI

    if let watchedFile = self.watchedFiles[uri] {
      mainFile = watchedFile.mainFile
    } else {
      let mainFiles = self._mainFilesProvider?.mainFilesContainingFile(uri)
      mainFile = chooseMainFile(for: uri, from: mainFiles ?? [])
      self.watchedFiles[uri] = (mainFile, language)
    }

    let newStatus = await self.cachedStatusOrRegisterForSettings(for: mainFile, language: language)

    if let mainChange = newStatus.buildSettingsChange,
       let delegate = self._delegate {
      let change = self.convert(change: mainChange, ofMainFile: mainFile, to: uri)
      delegate.fileBuildSettingsChanged([uri: change])
    }
  }

  /// Return settings for `file` based on  the `change` settings for `mainFile`.
  ///
  /// This is used when inferring arguments for header files (e.g. main file is a `.m`  while file is  a` .h`).
  nonisolated func convert(
    change: FileBuildSettingsChange,
    ofMainFile mainFile: DocumentURI,
    to file: DocumentURI
  ) -> FileBuildSettingsChange {
    guard mainFile != file else { return change }
    switch change {
    case .removedOrUnavailable: return .removedOrUnavailable
    case .fallback(let settings):
      return .fallback(settings.patching(newFile: file.pseudoPath, originalFile: mainFile.pseudoPath))
    case .modified(let settings):
      return .modified(settings.patching(newFile: file.pseudoPath, originalFile: mainFile.pseudoPath))
    }
  }

  /// Handle a request for `FileBuildSettings` on `mainFile`.
  ///
  /// Updates and returns the new `MainFileStatus` for `mainFile`.
  func cachedStatusOrRegisterForSettings(
    for mainFile: DocumentURI,
    language: Language
  ) async -> MainFileStatus {
    // If we already have a status for the main file, use that.
    // Don't update any existing timeout.
    if let status = self.mainFileStatuses[mainFile] {
      return status
    }
    // This is a new `mainFile` that we need to handle. We need to fetch the
    // build settings.
    let newStatus: MainFileStatus
    if let buildSystem = self.buildSystem {
      // Register the timeout if it's applicable.
      if let fallback = self.fallbackBuildSystem {
        Task {
          try await Task.sleep(nanoseconds: UInt64(self.fallbackSettingsTimeout.nanoseconds()!))
          self.handleFallbackTimer(for: mainFile, language: language, fallback)
        }
      }

      // Intentionally register with the `BuildSystem` after setting the fallback to allow for
      // testing of the fallback system triggering before the `BuildSystem` can reply (e.g. if a
      // fallback time of 0 is specified).
      await buildSystem.registerForChangeNotifications(for: mainFile, language: language)


      newStatus = .waiting
    } else if let fallback = self.fallbackBuildSystem {
      // Only have a fallback build system. We consider it be a primary build
      // system that functions synchronously.
      if let settings = fallback.buildSettings(for: mainFile, language: language) {
        newStatus = .primary(settings)
      } else {
        newStatus = .unsupported
      }
    } else {  // Don't have any build systems.
      newStatus = .unsupported
    }

    if let status = self.mainFileStatuses[mainFile] {
      // Since we await above, another call to `cachedStatusOrRegisterForSettings`
      // might have set the main file status of `mainFile`. If this race happened,
      // return the value set by the concurrently executing function. This is safe
      // since all calls from this function are either side-effect free or
      // idempotent.
      return status
    }

    self.mainFileStatuses[mainFile] = newStatus
    return newStatus
  }

  /// Update and notify our delegate for the given main file changes if they are
  /// convertible into `FileBuildSettingsChange`.
  func updateAndNotifyStatuses(changes: [DocumentURI: MainFileStatus]) {
    var changedWatchedFiles = [DocumentURI: FileBuildSettingsChange]()
    for (mainFile, status) in changes {
      let watches = self.watchedFiles.filter { $1.mainFile == mainFile }
      guard !watches.isEmpty else {
        // Possible notification after the file was unregistered. Ignore.
        continue
      }
      let prevStatus = self.mainFileStatuses[mainFile]
      self.mainFileStatuses[mainFile] = status

      // It's possible that the command line arguments didn't change
      // (waitingFallback --> fallback), in that case we don't need to report a change.
      // If we were waiting though, we need to emit an initial change.
      guard prevStatus == .waiting || status.buildSettings != prevStatus?.buildSettings else {
        continue
      }
      if let change = status.buildSettingsChange {
        for watch in watches {
          let newChange =
            self.convert(change: change, ofMainFile: mainFile, to: watch.key)
          changedWatchedFiles[watch.key] = newChange
        }
      }
    }

    if !changedWatchedFiles.isEmpty, let delegate = self._delegate {
      delegate.fileBuildSettingsChanged(changedWatchedFiles)
    }
  }

  /// Handle the fallback timer firing for a given `mainFile`.
  ///
  /// Since this doesn't occur immediately it's possible that the `mainFile` is
  /// no longer referenced or is referenced by multiple watched files.
  func handleFallbackTimer(
    for mainFile: DocumentURI,
    language: Language,
    _ fallback: FallbackBuildSystem
  ) {
    // There won't be a current status if it's unreferenced by any watched file.
    // Similarly, if the status isn't `waiting` then there's nothing to do.
    guard let status = self.mainFileStatuses[mainFile], status == .waiting else {
      return
    }
    if let settings = fallback.buildSettings(for: mainFile, language: language) {
      self.updateAndNotifyStatuses(changes: [mainFile: .waitingUsingFallback(settings)])
    } else {
      // Keep the status as waiting.
    }
  }

  public func unregisterForChangeNotifications(for uri: DocumentURI) async {
    guard let mainFile = self.watchedFiles[uri]?.mainFile else {
      log("Unbalanced calls for registerForChangeNotifications and unregisterForChangeNotifications", level: .warning)
      return
    }
    self.watchedFiles[uri] = nil
    await self.checkUnreferencedMainFile(mainFile)
  }

  /// If the given main file is no longer referenced by any watched files,
  /// remove it and unregister it at the underlying build system.
  func checkUnreferencedMainFile(_ mainFile: DocumentURI) async {
    if !self.watchedFiles.values.lazy.map({ $0.mainFile }).contains(mainFile) {
      // This was the last reference to the main file. Remove it.
      await self.buildSystem?.unregisterForChangeNotifications(for: mainFile)
      self.mainFileStatuses[mainFile] = nil
    }
  }

  public func fileHandlingCapability(for uri: DocumentURI) async -> FileHandlingCapability {
    return max(
      await buildSystem?.fileHandlingCapability(for: uri) ?? .unhandled,
      fallbackBuildSystem?.fileHandlingCapability(for: uri) ?? .unhandled
    )
  }
}

extension BuildSystemManager: BuildSystemDelegate {
  // FIXME: (async) Make this method isolated once `BuildSystemDelegate` has ben asyncified
  public nonisolated func fileBuildSettingsChanged(_ changes: [DocumentURI: FileBuildSettingsChange]) {
    Task {
      await fileBuildSettingsChangedImpl(changes)
    }
  }

  public func fileBuildSettingsChangedImpl(_ changes: [DocumentURI: FileBuildSettingsChange]) {
    let statusChanges: [DocumentURI: MainFileStatus] =
        changes.reduce(into: [:]) { (result, entry) in
      let mainFile = entry.key
      let settingsChange = entry.value
      let watches = self.watchedFiles.filter { $1.mainFile == mainFile }
      guard let firstWatch = watches.first else {
        // Possible notification after the file was unregistered. Ignore.
        return
      }
      let newStatus: MainFileStatus

      if let newSettings = settingsChange.newSettings {
        newStatus = settingsChange.isFallback ? .fallback(newSettings) : .primary(newSettings)
      } else if let fallback = self.fallbackBuildSystem {
        // FIXME: we need to stop threading the language everywhere, or we need the build system
        // itself to pass it in here. Or alternatively cache the fallback settings/language earlier?
        let language = firstWatch.value.language
        if let settings = fallback.buildSettings(for: mainFile, language: language) {
          newStatus = .fallback(settings)
        } else {
          newStatus = .unsupported
        }
      } else {
        newStatus = .unsupported
      }
      result[mainFile] = newStatus
    }
    self.updateAndNotifyStatuses(changes: statusChanges)
  }

  // FIXME: (async) Make this method isolated once `BuildSystemDelegate` has ben asyncified
  public nonisolated func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    Task {
      await filesDependenciesUpdatedImpl(changedFiles)
    }
  }

  public func filesDependenciesUpdatedImpl(_ changedFiles: Set<DocumentURI>) {
    // Empty changes --> assume everything has changed.
    guard !changedFiles.isEmpty else {
      if let delegate = self._delegate {
        delegate.filesDependenciesUpdated(changedFiles)
      }
      return
    }

    // Need to map the changed main files back into changed watch files.
    let changedWatchedFiles = self.watchedFiles.filter { changedFiles.contains($1.mainFile) }
    let newChangedFiles = Set(changedWatchedFiles.map { $0.key })
    if let delegate = self._delegate, !newChangedFiles.isEmpty {
      delegate.filesDependenciesUpdated(newChangedFiles)
    }
  }

  // FIXME: (async) Make this method isolated once `BuildSystemDelegate` has ben asyncified
  public nonisolated func buildTargetsChanged(_ changes: [BuildTargetEvent]) {
    Task {
      await buildTargetsChangedImpl(changes)
    }
  }

  public func buildTargetsChangedImpl(_ changes: [BuildTargetEvent]) {
    if let delegate = self._delegate {
      delegate.buildTargetsChanged(changes)
    }
  }

  // FIXME: (async) Make this method isolated once `BuildSystemDelegate` has ben asyncified
  public nonisolated func fileHandlingCapabilityChanged() {
    Task {
      await fileHandlingCapabilityChangedImpl()
    }
  }

  public func fileHandlingCapabilityChangedImpl() {
    if let delegate = self._delegate {
      delegate.fileHandlingCapabilityChanged()
    }
  }
}

extension BuildSystemManager: MainFilesDelegate {
  // FIXME: (async) Make this method isolated once `MainFilesDelegate` has ben asyncified
  public nonisolated func mainFilesChanged() {
    Task {
      await mainFilesChangedImpl()
    }
  }

  // FIXME: Consider debouncing/limiting this, seems to trigger often during a build.
  public func mainFilesChangedImpl() async {
    let origWatched = self.watchedFiles
    self.watchedFiles = [:]
    var buildSettingsChanges = [DocumentURI: FileBuildSettingsChange]()

    for (uri, state) in origWatched {
      let mainFiles = self._mainFilesProvider?.mainFilesContainingFile(uri) ?? []
      let newMainFile = chooseMainFile(for: uri, previous: state.mainFile, from: mainFiles)
      let language = state.language

      self.watchedFiles[uri] = (newMainFile, language)

      if state.mainFile != newMainFile {
        log("main file for '\(uri)' changed old: '\(state.mainFile)' -> new: '\(newMainFile)'", level: .info)
        await self.checkUnreferencedMainFile(state.mainFile)

        let newStatus = await self.cachedStatusOrRegisterForSettings(
            for: newMainFile, language: language)
        if let change = newStatus.buildSettingsChange {
          let newChange = self.convert(change: change, ofMainFile: newMainFile, to: uri)
          buildSettingsChanges[uri] = newChange
        }
      }
    }

    if let delegate = self._delegate, !buildSettingsChanges.isEmpty {
      delegate.fileBuildSettingsChanged(buildSettingsChanges)
    }
  }
}

extension BuildSystemManager {

  /// *For Testing* Returns the main file used for `uri`, if this is a registered file.
  public func _cachedMainFile(for uri: DocumentURI) -> DocumentURI? {
    watchedFiles[uri]?.mainFile
  }

  /// *For Testing* Returns the main file used for `uri`, if this is a registered file.
  public func _cachedMainFileSettings(for uri: DocumentURI) -> FileBuildSettings?? {
    mainFileStatuses[uri]?.buildSettings
  }
}

/// Choose a new main file for the given uri, preferring to use a previous main file if still
/// available, to avoid thrashing the settings unnecessarily, and falling back to `uri` itself if
/// there are no main files found at all.
private func chooseMainFile(
  for uri: DocumentURI,
  previous: DocumentURI? = nil,
  from mainFiles: Set<DocumentURI>) -> DocumentURI
{
  if let previous = previous, mainFiles.contains(previous) {
    return previous
  } else if mainFiles.isEmpty || mainFiles.contains(uri) {
    return uri
  } else {
    return mainFiles.first!
  }
}
