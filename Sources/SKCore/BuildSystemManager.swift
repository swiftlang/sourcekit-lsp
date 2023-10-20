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
import LSPLogging
import LanguageServerProtocol

import struct TSCBasic.AbsolutePath

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
  /// The files for which the delegate has requested change notifications, ie.
  /// the files for which the delegate wants to get `filesDependenciesUpdated`
  /// callbacks if the file's build settings.
  var watchedFiles: [DocumentURI: (mainFile: DocumentURI, language: Language)] = [:]

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
  public init(
    buildSystem: BuildSystem?,
    fallbackBuildSystem: FallbackBuildSystem?,
    mainFilesProvider: MainFilesProvider?,
    fallbackSettingsTimeout: DispatchTimeInterval = .seconds(3)
  ) async {
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
  }
}

/// Splits `message` on newline characters such that each chunk is at most `maxChunkSize` bytes long.
///
/// The intended use case for this is to split compiler arguments into multiple chunks so that each chunk doesn't exceed
/// the maximum message length of `os_log` and thus won't get truncated.
///
///  - Note: This will only split along newline boundary. If a single line is longer than `maxChunkSize`, it won't be
///    split. This is fine for compiler argument splitting since a single argument is rarely longer than 800 characters.
private func splitLongMultilineMessage(message: String, maxChunkSize: Int) -> [String] {
  var chunks: [String] = []
  for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
    if let lastChunk = chunks.last, lastChunk.utf8.count + line.utf8.count < maxChunkSize {
      chunks[chunks.count - 1] += "\n" + line
    } else {
      chunks.append(String(line))
    }
  }
  return chunks
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
    get { _mainFilesProvider }
    set { _mainFilesProvider = newValue }
  }

  /// - Note: Needed so we can set the delegate from a different isolation context.
  public func setMainFilesProvider(_ mainFilesProvider: MainFilesProvider?) {
    self.mainFilesProvider = mainFilesProvider
  }

  private func buildSettings(
    for document: DocumentURI,
    language: Language
  ) async -> FileBuildSettings? {
    do {
      // FIXME: (async) We should only wait `fallbackSettingsTimeout` for build
      // settings and return fallback afterwards. I am not sure yet, how best to
      // implement that with Swift concurrency.
      // For now, this should be fine because all build systems return
      // very quickly from `settings(for:language:)`.
      if let settings = try await buildSystem?.buildSettings(for: document, language: language) {
        return settings
      }
    } catch {
      logger.error("Getting build settings failed: \(error.forLogging)")
    }
    guard var settings = fallbackBuildSystem?.buildSettings(for: document, language: language) else {
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
  public func buildSettingsInferredFromMainFile(
    for document: DocumentURI,
    language: Language
  ) async -> FileBuildSettings? {
    let mainFile = mainFile(for: document)
    guard var settings = await buildSettings(for: mainFile, language: language) else {
      return nil
    }
    if mainFile != document {
      // If the main file isn't the file itself, we need to patch the build settings
      // to reference `document` instead of `mainFile`.
      settings = settings.patching(newFile: document.pseudoPath, originalFile: mainFile.pseudoPath)
    }
    let log = """
      Compiler Arguments:
      \(settings.compilerArguments.joined(separator: "\n"))

      Working directory:
      \(settings.workingDirectory ?? "<nil>")
      """

    let chunks = splitLongMultilineMessage(message: log, maxChunkSize: 800)
    for (index, chunk) in chunks.enumerated() {
      logger.log(
        """
        Build settings for \(document.forLogging) (\(index + 1)/\(chunks.count))
        \(chunk)
        """
      )
    }
    return settings
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) async {
    logger.debug("registerForChangeNotifications(\(uri.forLogging))")
    let mainFile = mainFile(for: uri)
    self.watchedFiles[uri] = (mainFile, language)

    // Register for change notifications of the main file in the underlying build
    // system. That way, iff the main file changes, we will also notify the
    // delegate about build setting changes of all header files that are based
    // on that main file.
    await buildSystem?.registerForChangeNotifications(for: mainFile, language: language)
  }

  public func unregisterForChangeNotifications(for uri: DocumentURI) async {
    guard let mainFile = self.watchedFiles[uri]?.mainFile else {
      logger.error("Unbalanced calls for registerForChangeNotifications and unregisterForChangeNotifications")
      return
    }
    self.watchedFiles[uri] = nil

    if watchedFilesReferencing(mainFiles: [mainFile]).isEmpty {
      // Nobody is interested in this main file anymore.
      // We are no longer interested in change notifications for it.
      await self.buildSystem?.unregisterForChangeNotifications(for: mainFile)
    }
  }

  public func fileHandlingCapability(for uri: DocumentURI) async -> FileHandlingCapability {
    return max(
      await buildSystem?.fileHandlingCapability(for: uri) ?? .unhandled,
      fallbackBuildSystem != nil ? .fallback : .unhandled
    )
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

  public func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    let changedWatchedFiles = watchedFilesReferencing(mainFiles: changedFiles)

    if !changedWatchedFiles.isEmpty, let delegate = self._delegate {
      await delegate.fileBuildSettingsChanged(changedWatchedFiles)
    }
  }

  public func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) async {
    // Empty changes --> assume everything has changed.
    guard !changedFiles.isEmpty else {
      if let delegate = self._delegate {
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

  public func buildTargetsChanged(_ changes: [BuildTargetEvent]) async {
    if let delegate = self._delegate {
      await delegate.buildTargetsChanged(changes)
    }
  }

  public func fileHandlingCapabilityChanged() async {
    if let delegate = self._delegate {
      await delegate.fileHandlingCapabilityChanged()
    }
  }
}

extension BuildSystemManager: MainFilesDelegate {
  // FIXME: Consider debouncing/limiting this, seems to trigger often during a build.
  /// Checks if there are any files in `mainFileAssociations` where the main file
  /// that we have stored has changed.
  ///
  /// For all of these files, re-associate the file with the new main file and
  /// inform the delegate that the build settings for it might have changed.
  public func mainFilesChanged() async {
    var changedMainFileAssociations: Set<DocumentURI> = []
    for (file, (oldMainFile, language)) in self.watchedFiles {
      let newMainFile = self.mainFile(for: file, useCache: false)
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
  private func mainFile(for uri: DocumentURI, useCache: Bool = true) -> DocumentURI {
    if useCache, let mainFile = self.watchedFiles[uri]?.mainFile {
      // Performance optimization: We did already compute the main file and have
      // it cached. We can just return it.
      return mainFile
    }
    guard let mainFilesProvider else {
      return uri
    }

    let mainFiles = mainFilesProvider.mainFilesContainingFile(uri)
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

  /// *For Testing* Returns the main file used for `uri`, if this is a registered file.
  public func _cachedMainFile(for uri: DocumentURI) -> DocumentURI? {
    return self.watchedFiles[uri]?.mainFile
  }
}
