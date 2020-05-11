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

/// `BuildSystem` that integrates client-side information such as main-file lookup on top of one or
/// or more concrete build systems, as well as providing common functionality such as caching.
public final class BuildSystemManager {

  /// Queue for processing asynchronous work and mutual exclusion for shared state.
  let queue: DispatchQueue = DispatchQueue(label: "\(BuildSystemManager.self)-queue")

  /// Queue for asynchronous notifications.
  let notifyQueue: DispatchQueue = DispatchQueue(label: "\(BuildSystemManager.self)-notify")

  /// The set of watched files, along with their main file and language.
  var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

  /// Build settings for each main file.
  ///
  /// * `.none`: Build settings not computed yet.
  /// * `.some(.none)`: Build system returned `nil`.
  /// * `.some(.some(_))`: Build settings available!
  var mainFileSettings: [DocumentURI: FileBuildSettings?] = [:]

  /// The underlying build system.
  let buildSystem: BuildSystem

  /// Provider of file to main file mappings.
  weak var mainFilesProvider: MainFilesProvider?

  /// Build system delegate that will receive notifications about setting changes, etc.
  var _delegate: BuildSystemDelegate?

  /// Create a BuildSystemManager that wraps the given build system. The new manager will modify the
  /// delegate of the underlying build system.
  public init(buildSystem: BuildSystem, mainFilesProvider: MainFilesProvider?) {
    precondition(buildSystem.delegate == nil)
    self.buildSystem = buildSystem
    self.mainFilesProvider = mainFilesProvider
    self.buildSystem.delegate = self
  }
}

extension BuildSystemManager: BuildSystem {

  public var indexStorePath: AbsolutePath? {  queue.sync { buildSystem.indexStorePath } }

  public var indexDatabasePath: AbsolutePath? { queue.sync { buildSystem.indexDatabasePath } }

  /// Synchronously lookup the `FileBuildSettings` for `uri`.
  ///
  /// If `uri` was previously registered with `registerForChangeNotifications`, or if `uri`
  /// corresponds to a main file that was previously registered, this returns the cached settings.
  /// Otherwise it makes a one-off query to the build system and returns the settings.
  public func settings(for uri: DocumentURI, _ language: Language) -> FileBuildSettings? {
    queue.sync {
      if let watched = self.watchedFiles[uri] {
        let mainFile = watched.mainFile
        guard let cached: FileBuildSettings? = self.mainFileSettings[mainFile] else {
          fatalError("no cached settings for known main file \(mainFile)")
        }
        return cached
      } else {
        let mainFiles = self.mainFilesProvider?.mainFilesContainingFile(uri) ?? []
        let mainFile = chooseMainFile(for: uri, from: mainFiles)
        if let cached: FileBuildSettings? = self.mainFileSettings[mainFile] {
          return cached
        } else {
          return self.buildSystem.settings(for: mainFile, language)
        }
      }
    }
  }

  public var delegate: BuildSystemDelegate? {
    get { queue.sync { _delegate } }
    set { queue.sync { _delegate = newValue } }
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    return queue.async {
      log("registerForSettings(\(uri.pseudoPath))")
      let settings: FileBuildSettings?

      if let (mainFile, _) = self.watchedFiles[uri] {
        guard let cached: FileBuildSettings? = self.mainFileSettings[mainFile] else {
          fatalError("no settings for main file \(mainFile)")
        }
        settings = cached
      } else {
        let mainFiles = self.mainFilesProvider?.mainFilesContainingFile(uri)
        let mainFile = chooseMainFile(for: uri, from: mainFiles ?? [])
        self.watchedFiles[uri] = (mainFile, language)
        settings = self.cachedOrRegisterForSettings(mainFile: mainFile, language: language)
      }

      if let delegate = self._delegate {
        self.notifyQueue.async {
          // TODO: send back in the notification.
          _ = settings
          delegate.fileBuildSettingsChanged([uri])
        }
      }
    }
  }

  /// *Must be called on queue*. Returns build settings for the given main file either from the
  /// cache, or by querying the build system and registering for notifications.
  ///
  /// *Invariant*: `mainFileSettings[mainFile]` is non-nil if and only-if `mainFile` is currently
  /// registered for settings.
  func cachedOrRegisterForSettings(mainFile: DocumentURI, language: Language) -> FileBuildSettings?{
    if let cached: FileBuildSettings? = self.mainFileSettings[mainFile] {
      return cached
    }
    self.buildSystem.registerForChangeNotifications(for: mainFile, language: language)
    let settings = self.buildSystem.settings(for: mainFile, language)
    self.mainFileSettings[mainFile] = .some(settings)
    return settings
  }

  public func unregisterForChangeNotifications(for uri: DocumentURI) {
    queue.async {
      let mainFile = self.watchedFiles[uri]!.mainFile
      self.watchedFiles[uri] = nil
      self.checkUnreferencedMainFile(mainFile)
    }
  }

  /// *Must be called on queue*. If the given main file is no longer referenced by any watched
  /// files, remove it and unregister it at the underlying build system.
  func checkUnreferencedMainFile(_ mainFile: DocumentURI) {
    if !self.watchedFiles.values.lazy.map({ $0.mainFile }).contains(mainFile) {
      // This was the last reference to the main file. Remove it.
      self.buildSystem.unregisterForChangeNotifications(for: mainFile)
      self.mainFileSettings[mainFile] = nil
    }
  }

  public func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    queue.async {
      self.buildSystem.buildTargets(reply: reply)
    }
  }

  public func buildTargetSources(
    targets: [BuildTargetIdentifier],
    reply: @escaping (LSPResult<[SourcesItem]>) -> Void)
  {
    queue.async {
      self.buildSystem.buildTargetSources(targets: targets, reply: reply)
    }
  }

  public func buildTargetOutputPaths(
    targets: [BuildTargetIdentifier],
    reply: @escaping (LSPResult<[OutputsItem]>) -> Void)
  {
    queue.async {
      self.buildSystem.buildTargetOutputPaths(targets: targets, reply: reply)
    }
  }
}

extension BuildSystemManager: BuildSystemDelegate {

  public func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) {
    queue.async {
      // Empty -> assume all files have been changed.
      let filesToCheck = changedFiles.isEmpty ? Set(self.mainFileSettings.keys) : changedFiles
      var changedWatchedFiles = Set<DocumentURI>()

      for mainFile in filesToCheck {
        let watches = self.watchedFiles.filter { $1.mainFile == mainFile }
        guard !watches.isEmpty else {
          // We got a notification after the file was unregistered. Ignore.
          continue
        }

        // FIXME: we need to stop threading the langauge everywhere, or we need the build system
        // itself to pass it in here.
        let language = self.mainFileSettings[mainFile]??.language ?? watches.first!.value.language

        let settings = self.buildSystem.settings(for: mainFile, language)
        self.mainFileSettings[mainFile] = settings

        changedWatchedFiles.formUnion(watches.map { $0.key })
      }

      if let delegate = self._delegate, !changedWatchedFiles.isEmpty {
        self.notifyQueue.async {
          delegate.fileBuildSettingsChanged(changedWatchedFiles)
        }
      }
    }
  }

  public func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    queue.async {
      if let delegate = self._delegate {
        self.notifyQueue.async {
          delegate.filesDependenciesUpdated(changedFiles)
        }
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
      var changedWatchedFiles = Set<DocumentURI>()

      for (uri, state) in origWatched {
        let mainFiles = self.mainFilesProvider?.mainFilesContainingFile(uri) ?? []
        let newMainFile = chooseMainFile(for: uri, previous: state.mainFile, from: mainFiles)

        self.watchedFiles[uri] = (newMainFile, state.language)

        if state.mainFile != newMainFile {
          log("main file for '\(uri)' changed old: '\(state.mainFile)' -> new: '\(newMainFile)'", level: .info)
          changedWatchedFiles.insert(uri)
          self.checkUnreferencedMainFile(state.mainFile)
          let settings = self.cachedOrRegisterForSettings(mainFile: newMainFile, language: state.language)
          // TODO: send back in the notification.
          _ = settings
        }
      }

      if let delegate = self._delegate, !changedWatchedFiles.isEmpty {
        self.notifyQueue.async {
          delegate.fileBuildSettingsChanged(changedWatchedFiles)
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
  public func _cachedMainFileSettings(for uri: DocumentURI) -> FileBuildSettings?? {
    queue.sync {
      mainFileSettings[uri]
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
