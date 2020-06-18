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
import TSCBasic
import Dispatch

/// `BuildSettings` status for a given main file.
enum BuildSettingsStatus: Equatable {
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

  /// No settings provided by primary and fallback `BuildSystem`.
  case unsupported
}

extension BuildSettingsStatus {
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

/// State of a given main file.
struct MainFileState {
  /// The `BuildSettingsStatus` for this main file.
  var buildSettingsStatus: BuildSettingsStatus

  /// Last reported `FileStatus` from the `BuildSystem`, if any.
  var reportedFileStatus: FileStatus?

  init(buildSettingsStatus: BuildSettingsStatus, reportedFileStatus: FileStatus? = nil) {
    self.buildSettingsStatus = buildSettingsStatus
    self.reportedFileStatus = reportedFileStatus
  }
}

extension MainFileState {
  var fileStatus: FileStatus {
    // We prefer the status that the `BuildSystem` reports since it may provide more context to
    // the user than we can provide here.
    if let status = self.reportedFileStatus {
      return status
    }
    switch buildSettingsStatus {
    case .waiting:
      return FileStatus(state: .initializing, message: "Waiting for build setings...")
    case .unsupported:
      return FileStatus(state: .ready, severity: .error, message: "Unable to fetch build settings")
    case .fallback:
      return FileStatus(state: .ready, severity: .warning,
                        message: "Using fallback build settings, code assistance may be limited")
    case .waitingUsingFallback:
      return FileStatus(
        state: .ready, severity: .warning,
        message: "Still waiting for proper build settings, code assistance may be limited")
    case .primary:
      return FileStatus(state: .ready)
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
public final class BuildSystemManager {

  /// Queue for processing asynchronous work and mutual exclusion for shared state.
  let queue: DispatchQueue = DispatchQueue(label: "\(BuildSystemManager.self)-queue")

  /// Queue for asynchronous notifications.
  let notifyQueue: DispatchQueue = DispatchQueue(label: "\(BuildSystemManager.self)-notify")

  /// The set of watched files, along with their main file and language.
  var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  /// State for each main file, containing build settings and file status from the build systems.
  var stateByMainFile: [DocumentURI: MainFileState] = [:]

  /// The underlying primary build system.
  let buildSystem: BuildSystem?

  /// Timeout before fallback build settings are used.
  let fallbackSettingsTimeout: DispatchTimeInterval

  /// The fallback build system. If present, used when the `buildSystem` is not
  /// set or cannot provide settings.
  let fallbackBuildSystem: FallbackBuildSystem?

  /// Provider of file to main file mappings.
  weak var mainFilesProvider: MainFilesProvider?

  /// Build system delegate that will receive notifications about setting changes, etc.
  weak var _delegate: BuildSystemDelegate?

  /// Create a BuildSystemManager that wraps the given build system. The new
  /// manager will modify the delegate of the underlying build system.
  public init(buildSystem: BuildSystem?, fallbackBuildSystem: FallbackBuildSystem?,
              mainFilesProvider: MainFilesProvider?, fallbackSettingsTimeout: DispatchTimeInterval = .seconds(3)) {
    precondition(buildSystem?.delegate == nil)
    self.buildSystem = buildSystem
    self.fallbackBuildSystem = fallbackBuildSystem
    self.mainFilesProvider = mainFilesProvider
    self.fallbackSettingsTimeout = fallbackSettingsTimeout
    self.buildSystem?.delegate = self
  }
}

extension BuildSystemManager: BuildSystem {

  public var indexStorePath: AbsolutePath? {  queue.sync { buildSystem?.indexStorePath } }

  public var indexDatabasePath: AbsolutePath? { queue.sync { buildSystem?.indexDatabasePath } }

  public var delegate: BuildSystemDelegate? {
    get { queue.sync { _delegate } }
    set { queue.sync { _delegate = newValue } }
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    return queue.async {
      log("registerForChangeNotifications(\(uri.pseudoPath))")
      let mainFile: DocumentURI

      if let watchedFile = self.watchedFiles[uri] {
        mainFile = watchedFile.mainFile
      } else {
        let mainFiles = self.mainFilesProvider?.mainFilesContainingFile(uri)
        mainFile = chooseMainFile(for: uri, from: mainFiles ?? [])
        self.watchedFiles[uri] = (mainFile, language)
      }

      let newState = self.cachedStatusOrRegisterForSettings(for: mainFile, language: language)

      if let delegate = self._delegate {
        self.notifyQueue.async {
          if let change = newState.buildSettingsStatus.buildSettingsChange {
            delegate.fileBuildSettingsChanged([uri: change])
          }
          delegate.fileStatusesChanged([uri: newState.fileStatus])
        }
      }
    }
  }

  /// *Must be called on queue*. Handle a request for `FileBuildSettings` on
  /// `mainFile`. Updates and returns the new `MainFileState` for `mainFile`.
  func cachedStatusOrRegisterForSettings(
    for mainFile: DocumentURI,
    language: Language
  ) -> MainFileState {
    // If we already have a state for the main file, use that.
    // Don't update any existing timeout.
    if let state = self.stateByMainFile[mainFile] {
      return state
    }
    // This is a new `mainFile` that we need to handle. We need to fetch the build settings.
    let newState: MainFileState
    if let buildSystem = self.buildSystem {
      // Register the timeout if it's applicable.
      if let fallback = self.fallbackBuildSystem {
        self.queue.asyncAfter(deadline: DispatchTime.now() + self.fallbackSettingsTimeout) { [weak self] in
          guard let self = self else { return }
          self.handleFallbackTimer(for: mainFile, language: language, fallback)
        }
      }

      // Intentionally register with the `BuildSystem` after setting the fallback to allow for
      // testing of the fallback system triggering before the `BuildSystem` can reply (e.g. if a
      // fallback time of 0 is specified).
      buildSystem.registerForChangeNotifications(for: mainFile, language: language)

      newState = MainFileState(buildSettingsStatus: .waiting)
    } else if let fallback = self.fallbackBuildSystem {
      // Only have a fallback build system. We consider it be a primary build
      // system that functions synchronously.
      if let settings = fallback.settings(for: mainFile, language) {
        newState = MainFileState(buildSettingsStatus: .primary(settings))
      } else {
        newState = MainFileState(buildSettingsStatus: .unsupported)
      }
    } else {  // Don't have any build systems.
      newState = MainFileState(buildSettingsStatus: .unsupported)
    }
    self.stateByMainFile[mainFile] = newState
    return newState
  }

  /// *Must be called on queue*. Update and notify our delegate for the given
  /// main file changes in terms of `FileBuildSettingsChange` and `FileStatus`.
  func updateAndNotifyStatuses(changes: [DocumentURI: BuildSettingsStatus]) {
    var changedWatchedFiles = [DocumentURI: FileBuildSettingsChange]()
    var changedFileStatuses = [DocumentURI: FileStatus]()
    for (mainFile, status) in changes {
      let watches = self.watchedFiles.filter { $1.mainFile == mainFile }
      guard !watches.isEmpty else {
        // Possible notification after the file was unregistered. Ignore.
        continue
      }
      guard let prevState = self.stateByMainFile[mainFile] else {
        // Unexpected, ignore.
        continue
      }
      let newState = MainFileState(buildSettingsStatus: status,
                                   reportedFileStatus: prevState.reportedFileStatus)
      self.stateByMainFile[mainFile] = newState

      if prevState.fileStatus != newState.fileStatus {
        for watch in watches {
          changedFileStatuses[watch.key] = newState.fileStatus
        }
      }

      let prevStatus = prevState.buildSettingsStatus

      // It's possible that the command line arguments didn't change
      // (waitingFallback --> fallback), in that case we don't need to report a change.
      // If we were waiting though, we need to emit an initial change.
      guard prevStatus == .waiting || status.buildSettings != prevStatus.buildSettings else {
        continue
      }
      if let change = status.buildSettingsChange {
        for watch in watches {
          changedWatchedFiles[watch.key] = change
        }
      }
    }

    if let delegate = self._delegate, !changedWatchedFiles.isEmpty || !changedFileStatuses.isEmpty {
      self.notifyQueue.async {
        if !changedWatchedFiles.isEmpty {
          delegate.fileBuildSettingsChanged(changedWatchedFiles)
        }
        if !changedFileStatuses.isEmpty {
          delegate.fileStatusesChanged(changedFileStatuses)
        }
      }
    }
  }

  /// *Must be called on queue*. Handle the fallback timer firing for a given
  /// `mainFile`. Since this doesn't occur immediately it's possible that the
  /// `mainFile` is no longer referenced or is referenced by multiple watched
  /// files.
  func handleFallbackTimer(
    for mainFile: DocumentURI,
    language: Language,
    _ fallback: FallbackBuildSystem
  ) {
    // There won't be a current status if it's unreferenced by any watched file.
    // Simiarly, if the status isn't `waiting` then there's nothing to do.
    guard self.stateByMainFile[mainFile]?.buildSettingsStatus == .waiting else {
      return
    }
    if let settings = fallback.settings(for: mainFile, language) {
      self.updateAndNotifyStatuses(changes: [mainFile: .waitingUsingFallback(settings)])
    } else {
      // Keep the status as waiting.
    }
  }

  public func unregisterForChangeNotifications(for uri: DocumentURI) {
    queue.async {
      let mainFile = self.watchedFiles[uri]!.mainFile
      self.watchedFiles[uri] = nil
      self.checkUnreferencedMainFile(mainFile)
    }
  }

  /// *Must be called on queue*. If the given main file is no longer referenced
  /// by any watched files, remove it and unregister it at the underlying
  /// build system.
  func checkUnreferencedMainFile(_ mainFile: DocumentURI) {
    if !self.watchedFiles.values.lazy.map({ $0.mainFile }).contains(mainFile) {
      // This was the last reference to the main file. Remove it.
      self.buildSystem?.unregisterForChangeNotifications(for: mainFile)
      self.stateByMainFile[mainFile] = nil
    }
  }

  public func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    queue.async {
      if let buildSystem = self.buildSystem {
        buildSystem.buildTargets(reply: reply)
      } else {
        reply(.success([]))
      }
    }
  }

  public func buildTargetSources(
    targets: [BuildTargetIdentifier],
    reply: @escaping (LSPResult<[SourcesItem]>) -> Void)
  {
    queue.async {
      if let buildSystem = self.buildSystem {
        buildSystem.buildTargetSources(targets: targets, reply: reply)
      } else {
        reply(.success([]))
      }
    }
  }

  public func buildTargetOutputPaths(
    targets: [BuildTargetIdentifier],
    reply: @escaping (LSPResult<[OutputsItem]>) -> Void)
  {
    queue.async {
      if let buildSystem = self.buildSystem {
        buildSystem.buildTargetOutputPaths(targets: targets, reply: reply)
      } else {
        reply(.success([]))
      }
    }
  }
}

extension BuildSystemManager: BuildSystemDelegate {

  public func fileBuildSettingsChanged(_ changes: [DocumentURI: FileBuildSettingsChange]) {
    queue.async {
      let statusChanges: [DocumentURI: BuildSettingsStatus] =
          changes.reduce(into: [:]) { (result, entry) in
        let mainFile = entry.key
        let settingsChange = entry.value
        let watches = self.watchedFiles.filter { $1.mainFile == mainFile }
        guard let firstWatch = watches.first else {
          // Possible notification after the file was unregistered. Ignore.
          return
        }
        let newStatus: BuildSettingsStatus

        if let newSettings = settingsChange.newSettings {
          newStatus = settingsChange.isFallback ? .fallback(newSettings) : .primary(newSettings)
        } else if let fallback = self.fallbackBuildSystem {
          // FIXME: we need to stop threading the language everywhere, or we need the build system
          // itself to pass it in here. Or alteratively cache the fallback settings/language earlier?
          let language = firstWatch.value.language
          if let settings = fallback.settings(for: mainFile, language) {
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
  }

  public func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    queue.async {
      // Empty changes --> assume everything has changed.
      guard !changedFiles.isEmpty else {
        if let delegate = self._delegate {
          self.notifyQueue.async {
            delegate.filesDependenciesUpdated(changedFiles)
          }
        }
        return
      }

      // Need to map the changed main files back into changed watch files.
      let changedWatchedFiles = self.watchedFiles.filter { changedFiles.contains($1.mainFile) }
      let newChangedFiles = Set(changedWatchedFiles.map { $0.key })
      if let delegate = self._delegate, !newChangedFiles.isEmpty {
        self.notifyQueue.async {
          delegate.filesDependenciesUpdated(newChangedFiles)
        }
      }
    }
  }

  public func fileStatusesChanged(_ changes: [DocumentURI: FileStatus]) {
    queue.async {
      var changedFileStatuses = [DocumentURI: FileStatus]()
      for (mainFile, status) in changes {
        let watches = self.watchedFiles.filter { $1.mainFile == mainFile }
        guard !watches.isEmpty else {
          // Possible notification after the file was unregistered. Ignore.
          continue
        }
        guard let prevState = self.stateByMainFile[mainFile], prevState.fileStatus != status else {
          continue
        }
        self.stateByMainFile[mainFile] = MainFileState(
          buildSettingsStatus: prevState.buildSettingsStatus,
          reportedFileStatus: status
        )
        for watch in watches {
          changedFileStatuses[watch.key] = status
        }
      }
      guard let delegate = self._delegate, !changedFileStatuses.isEmpty else { return }
      self.notifyQueue.async {
        delegate.fileStatusesChanged(changedFileStatuses)
      }
    }
  }

  public func buildTargetsChanged(_ changes: [BuildTargetEvent]) {
    queue.async {
      if let delegate = self._delegate {
        self.notifyQueue.async {
          delegate.buildTargetsChanged(changes)
        }
      }
    }
  }
}

extension BuildSystemManager: MainFilesDelegate {

  public func mainFilesChanged() {
    queue.async {
      let origWatched = self.watchedFiles
      self.watchedFiles = [:]
      var buildSettingsChanges = [DocumentURI: FileBuildSettingsChange]()
      var statusChanges = [DocumentURI: FileStatus]()

      for (uri, state) in origWatched {
        let mainFiles = self.mainFilesProvider?.mainFilesContainingFile(uri) ?? []
        let newMainFile = chooseMainFile(for: uri, previous: state.mainFile, from: mainFiles)
        let language = state.language

        self.watchedFiles[uri] = (newMainFile, language)

        if state.mainFile != newMainFile {
          log("main file for '\(uri)' changed old: '\(state.mainFile)' -> new: '\(newMainFile)'", level: .info)
          self.checkUnreferencedMainFile(state.mainFile)

          let newState = self.cachedStatusOrRegisterForSettings(
              for: newMainFile, language: language)
          buildSettingsChanges[uri] = newState.buildSettingsStatus.buildSettingsChange
          statusChanges[uri] = newState.fileStatus
        }
      }

      if let delegate = self._delegate, !statusChanges.isEmpty {
        self.notifyQueue.async {
          if !buildSettingsChanges.isEmpty {
            delegate.fileBuildSettingsChanged(buildSettingsChanges)
          }
          delegate.fileStatusesChanged(statusChanges)
        }
      }
    }
  }
}

extension BuildSystemManager {

  /// *For Testing* Returns the main file used for `uri`, if this is a registered file.
  public func _cachedMainFile(for uri: DocumentURI) -> DocumentURI? {
    queue.sync {
      watchedFiles[uri]?.mainFile
    }
  }

  /// *For Testing* Returns the main file used for `uri`, if this is a registered file.
  public func _cachedMainFileSettings(for uri: DocumentURI) -> FileBuildSettings? {
    queue.sync {
      stateByMainFile[uri]?.buildSettingsStatus.buildSettings
    }
  }

  /// *For Testing* Returns the main file status used for `uri`, if this is a registered file.
  public func _cachedMainFileSettings(for uri: DocumentURI) -> FileStatus? {
    queue.sync {
      stateByMainFile[uri]?.fileStatus
    }
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
