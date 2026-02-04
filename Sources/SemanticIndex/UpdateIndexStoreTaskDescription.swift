//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import BuildServerIntegration
@_spi(SourceKitLSP) package import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import struct TSCBasic.ProcessResult
import enum TSCBasic.SystemError

#if os(Windows)
import WinSDK
#endif

private let updateIndexStoreIDForLogging = AtomicUInt32(initialValue: 1)

package enum FileToIndex: CustomLogStringConvertible, Hashable {
  /// A non-header file
  case indexableFile(DocumentURI)

  /// A header file where `mainFile` should be indexed to update the index of `header`.
  case headerFile(header: DocumentURI, mainFile: DocumentURI)

  /// The file whose index store should be updated.
  ///
  /// This file might be a header file that doesn't have build settings associated with it. For the actual compiler
  /// invocation that updates the index store, the `mainFile` should be used.
  package var sourceFile: DocumentURI {
    switch self {
    case .indexableFile(let uri): return uri
    case .headerFile(let header, mainFile: _): return header
    }
  }

  /// The file that should be used for compiler invocations that update the index.
  ///
  /// If the `sourceFile` is a header file, this will be a main file that includes the header. Otherwise, it will be the
  /// same as `sourceFile`.
  var mainFile: DocumentURI {
    switch self {
    case .indexableFile(let uri): return uri
    case .headerFile(header: _, let mainFile): return mainFile
    }
  }

  package var description: String {
    switch self {
    case .indexableFile(let uri):
      return uri.description
    case .headerFile(let header, let mainFile):
      return "\(header.description) using main file \(mainFile.description)"
    }
  }

  package var redactedDescription: String {
    switch self {
    case .indexableFile(let uri):
      return uri.redactedDescription
    case .headerFile(let header, let mainFile):
      return "\(header.redactedDescription) using main file \(mainFile.redactedDescription)"
    }
  }
}

/// A source file to index and the output path that should be used for indexing.
package struct FileAndOutputPath: Sendable, Hashable {
  package let file: FileToIndex
  package let outputPath: OutputPath

  fileprivate var mainFile: DocumentURI { file.mainFile }
  fileprivate var sourceFile: DocumentURI { file.sourceFile }
}

/// A single file or a list of files that should be indexed in a single compiler invocation.
private enum UpdateIndexStorePartition {
  case multipleFiles(filesAndOutputPaths: [(file: FileToIndex, outputPath: String)], buildSettings: FileBuildSettings)
  case singleFile(file: FileAndOutputPath, buildSettings: FileBuildSettings)

  var buildSettings: FileBuildSettings {
    switch self {
    case .multipleFiles(_, let buildSettings): return buildSettings
    case .singleFile(_, let buildSettings): return buildSettings
    }
  }

  var files: [FileToIndex] {
    switch self {
    case .multipleFiles(let filesAndOutputPaths, _): return filesAndOutputPaths.map(\.file)
    case .singleFile(let file, _): return [file.file]
    }
  }
}

/// Describes a task to index a set of source files.
///
/// This task description can be scheduled in a `TaskScheduler`.
package struct UpdateIndexStoreTaskDescription: IndexTaskDescription {
  package static let idPrefix = "update-indexstore"
  package let id = updateIndexStoreIDForLogging.fetchAndIncrement()

  /// The files that should be indexed.
  package let filesToIndex: [FileAndOutputPath]

  /// The target in whose context the files should be indexed.
  package let target: BuildTargetIdentifier

  /// The common language of all main files in `filesToIndex`.
  package let language: Language

  /// The build server manager that is used to get the toolchain and build settings for the files to index.
  private let buildServerManager: BuildServerManager

  /// A reference to the underlying index store. Used to check if the index is already up-to-date for a file, in which
  /// case we don't need to index it again.
  private let index: UncheckedIndex

  private let indexStoreUpToDateTracker: UpToDateTracker<DocumentURI, BuildTargetIdentifier>

  /// Whether files that have an up-to-date unit file should be indexed.
  ///
  /// In general, this should be `false`. The only situation when this should be set to `true` is when the user
  /// explicitly requested a re-index of all files.
  private let indexFilesWithUpToDateUnit: Bool

  /// See `SemanticIndexManager.logMessageToIndexLog`.
  private let logMessageToIndexLog:
    @Sendable (
      _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
    ) -> Void

  /// How long to wait until we cancel an update indexstore task. This timeout should be long enough that all
  /// `swift-frontend` tasks finish within it. It prevents us from blocking the index if the type checker gets stuck on
  /// an expression for a long time.
  private let timeout: Duration

  /// Test hooks that should be called when the index task finishes.
  private let hooks: IndexHooks

  /// The task is idempotent because indexing the same file twice produces the same result as indexing it once.
  package var isIdempotent: Bool { true }

  package var estimatedCPUCoreCount: Int { 1 }

  package var description: String {
    return self.redactedDescription
  }

  package var redactedDescription: String {
    return "update-indexstore-\(id)"
  }

  static func canIndex(language: Language) -> Bool {
    return language.semanticKind != nil
  }

  init(
    filesToIndex: [FileAndOutputPath],
    target: BuildTargetIdentifier,
    language: Language,
    buildServerManager: BuildServerManager,
    index: UncheckedIndex,
    indexStoreUpToDateTracker: UpToDateTracker<DocumentURI, BuildTargetIdentifier>,
    indexFilesWithUpToDateUnit: Bool,
    logMessageToIndexLog:
      @escaping @Sendable (
        _ message: String, _ type: WindowMessageType, _ structure: LanguageServerProtocol.StructuredLogKind
      ) -> Void,
    timeout: Duration,
    hooks: IndexHooks
  ) {
    self.filesToIndex = filesToIndex
    self.target = target
    self.language = language
    self.buildServerManager = buildServerManager
    self.index = index
    self.indexStoreUpToDateTracker = indexStoreUpToDateTracker
    self.indexFilesWithUpToDateUnit = indexFilesWithUpToDateUnit
    self.logMessageToIndexLog = logMessageToIndexLog
    self.timeout = timeout
    self.hooks = hooks
  }

  package func execute() async {
    // Only use the last two digits of the indexing ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running indexing operation.
    await withLoggingSubsystemAndScope(subsystem: indexLoggingSubsystem, scope: "update-indexstore-\(id % 100)") {
      let startDate = Date()

      await hooks.updateIndexStoreTaskDidStart?(self)

      let filesToIndexDescription = filesToIndex.map {
        $0.file.sourceFile.fileURL?.lastPathComponent ?? $0.file.sourceFile.stringValue
      }
      .joined(separator: ", ")
      logger.log(
        "Starting updating index store with priority \(Task.currentPriority.rawValue, privacy: .public): \(filesToIndexDescription)"
      )
      let filesToIndex = filesToIndex.sorted(by: { $0.file.sourceFile.stringValue < $1.file.sourceFile.stringValue })
      await updateIndexStore(forFiles: filesToIndex)
      // If we know the output paths, make sure that we load their units into indexstore-db. We would eventually also
      // pick the units up through file watching but that would leave a short time period in which we think that
      // indexing has finished (because the index process has terminated) but when the new symbols aren't present in
      // indexstore-db.
      let outputPaths = filesToIndex.compactMap { fileToIndex in
        switch fileToIndex.outputPath {
        case .path(let string): return string
        case .notSupported: return nil
        }
      }
      index.processUnitsForOutputPathsAndWait(outputPaths)
      await hooks.updateIndexStoreTaskDidFinish?(self)
      logger.log(
        "Finished updating index store in \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms: \(filesToIndexDescription)"
      )
    }
  }

  package func dependencies(
    to currentlyExecutingTasks: [UpdateIndexStoreTaskDescription]
  ) -> [TaskDependencyAction<UpdateIndexStoreTaskDescription>] {
    let selfMainFiles = Set(filesToIndex.map(\.file.mainFile))
    return currentlyExecutingTasks.compactMap { (other) -> TaskDependencyAction<UpdateIndexStoreTaskDescription>? in
      if !other.filesToIndex.lazy.map(\.file.mainFile).contains(where: { selfMainFiles.contains($0) }) {
        // Disjoint sets of files can be indexed concurrently.
        return nil
      }
      return .waitAndElevatePriorityOfDependency(other)
    }
  }

  private func updateIndexStore(forFiles fileInfos: [FileAndOutputPath]) async {
    let fileInfos = await fileInfos.asyncFilter { fileInfo in
      // If we know that the file is up-to-date without having ot hit the index, do that because it's fastest.
      if await indexStoreUpToDateTracker.isUpToDate(fileInfo.file.sourceFile, target) {
        return false
      }
      if indexFilesWithUpToDateUnit {
        return true
      }
      let hasUpToDateUnit = index.checked(for: .modifiedFiles).hasUpToDateUnit(
        for: fileInfo.sourceFile,
        mainFile: fileInfo.mainFile,
        outputPath: fileInfo.outputPath
      )
      if hasUpToDateUnit {
        logger.debug("Not indexing \(fileInfo.file.forLogging) because index has an up-to-date unit")
        // We consider a file's index up-to-date if we have any up-to-date unit. Changing build settings does not
        // invalidate the up-to-date status of the index.
      }
      return !hasUpToDateUnit
    }
    if fileInfos.isEmpty {
      return
    }
    for fileInfo in fileInfos where fileInfo.mainFile != fileInfo.sourceFile {
      logger.log(
        "Updating index store of \(fileInfo.file.forLogging) using main file \(fileInfo.mainFile.forLogging)"
      )
    }

    // Compute the partitions within which we can perform multi-file indexing. For this we gather all the files that may
    // only be indexed by themselves in `partitions` an collect all other files in `fileInfosByBuildSettings` so that we
    // can create a partition for all files that share the same build settings.
    // In most cases, we will only end up with a single partition for each `UpdateIndexStoreTaskDescription` since
    // `UpdateIndexStoreTaskDescription.batches(toIndex:)` tries to batch the files in a way such that all files within
    // the batch can be indexed by a single compiler invocation. However, we might discover that two Swift files within
    // the same target have different build settings in the build server. In that case, the best thing we can do is
    // trigger two compiler invocations.
    var swiftFileInfosByBuildSettings: [FileBuildSettings: [(file: FileToIndex, outputPath: String)]] = [:]
    var partitions: [UpdateIndexStorePartition] = []
    for fileInfo in fileInfos {
      let buildSettings = await buildServerManager.buildSettings(
        for: fileInfo.mainFile,
        in: target,
        language: language,
        fallbackAfterTimeout: false
      )
      guard var buildSettings else {
        logger.error("Not indexing \(fileInfo.file.forLogging) because it has no compiler arguments")
        continue
      }
      if buildSettings.isFallback {
        // Fallback build settings don’t even have an indexstore path set, so they can't generate index data that we
        // would pick up. Also, indexing with fallback args has some other problems:
        // - If it did generate a unit file, we would consider the file’s index up-to-date even if the compiler
        //   arguments change, which means that we wouldn't get any up-to-date-index even when we have build settings
        //   for the file.
        // - It's unlikely that the index from a single file with fallback arguments will be very useful as it can't tie
        //   into the rest of the project.
        // So, don't index the file.
        logger.error("Not indexing \(fileInfo.file.forLogging) because it has fallback compiler arguments")
        continue
      }

      guard buildSettings.language == .swift else {
        // We only support multi-file indexing for Swift files. Do not try to batch or normalize
        // `-index-unit-output-path` for clang files.
        partitions.append(.singleFile(file: fileInfo, buildSettings: buildSettings))
        continue
      }

      guard
        await buildServerManager.toolchain(for: target, language: language)?
          .canIndexMultipleSwiftFilesInSingleInvocation ?? false
      else {
        partitions.append(.singleFile(file: fileInfo, buildSettings: buildSettings))
        continue
      }

      // If the build settings contain `-index-unit-output-path`, remove it. We add the index unit output path back in
      // using an `-output-file-map`. Removing it from the build settings allows us to index multiple Swift files in a
      // single compiler invocation if they share all build settings and only differ in their `-index-unit-output-path`.
      let indexUnitOutputPathFromSettings = removeIndexUnitOutputPath(
        from: &buildSettings,
        for: fileInfo.mainFile
      )

      switch (fileInfo.outputPath, indexUnitOutputPathFromSettings) {
      case (.notSupported, nil):
        partitions.append(.singleFile(file: fileInfo, buildSettings: buildSettings))
      case (.notSupported, let indexUnitOutputPathFromSettings?):
        swiftFileInfosByBuildSettings[buildSettings, default: []].append(
          (fileInfo.file, indexUnitOutputPathFromSettings)
        )
      case (.path(let indexUnitOutputPath), nil):
        swiftFileInfosByBuildSettings[buildSettings, default: []].append((fileInfo.file, indexUnitOutputPath))
      case (.path(let indexUnitOutputPath), let indexUnitOutputPathFromSettings?):
        if indexUnitOutputPathFromSettings != indexUnitOutputPath {
          logger.error(
            "Output path reported by BSP server does not match -index-unit-output path in compiler arguments: \(indexUnitOutputPathFromSettings) vs \(indexUnitOutputPath)"
          )
        }
        swiftFileInfosByBuildSettings[buildSettings, default: []].append((fileInfo.file, indexUnitOutputPath))
      }
    }
    for (buildSettings, fileInfos) in swiftFileInfosByBuildSettings {
      partitions.append(.multipleFiles(filesAndOutputPaths: fileInfos, buildSettings: buildSettings))
    }

    for partition in partitions {
      guard let toolchain = await buildServerManager.toolchain(for: target, language: partition.buildSettings.language)
      else {
        logger.fault(
          "Unable to determine toolchain to index \(partition.buildSettings.language.description, privacy: .public) files in \(target.forLogging)"
        )
        continue
      }
      let startDate = Date()
      switch partition.buildSettings.language.semanticKind {
      case .swift:
        do {
          try await updateIndexStore(
            forSwiftFilesInPartition: partition,
            toolchain: toolchain
          )
        } catch {
          logger.error(
            """
            Updating index store failed: \(error.forLogging).
            Files: \(partition.files)
            """
          )
          BuildSettingsLogger.log(settings: partition.buildSettings, for: partition.files.map(\.mainFile))
        }
      case .clang:
        for fileInfo in partition.files {
          do {
            try await updateIndexStore(
              forClangFile: fileInfo.mainFile,
              buildSettings: partition.buildSettings,
              toolchain: toolchain
            )
          } catch {
            logger.error("Updating index store for \(fileInfo.mainFile.forLogging) failed: \(error.forLogging)")
            BuildSettingsLogger.log(settings: partition.buildSettings, for: fileInfo.mainFile)
          }
        }
      case nil:
        logger.error(
          """
          Not updating index store because \(partition.buildSettings.language.rawValue, privacy: .public) is not \
          supported by background indexing.
          Files: \(partition.files)
          """
        )
      }
      await indexStoreUpToDateTracker.markUpToDate(
        partition.files.map { ($0.sourceFile, target) },
        updateOperationStartDate: startDate
      )
    }
  }

  /// If `args` does not contain an `-index-store-path` argument, add it, pointing to the build server's index store
  /// path. If an `-index-store-path` already exists, validate that it matches the build server's index store path and
  /// replace it by the build server's index store path if they don't match.
  private func addOrReplaceIndexStorePath(in args: [String], for uris: [DocumentURI]) async throws -> [String] {
    var args = args
    guard let buildServerIndexStorePath = await self.buildServerManager.initializationData?.indexStorePath else {
      struct NoIndexStorePathError: Error {}
      throw NoIndexStorePathError()
    }
    if let indexStorePathIndex = args.lastIndex(of: "-index-store-path"), indexStorePathIndex + 1 < args.count {
      let indexStorePath = args[indexStorePathIndex + 1]
      if indexStorePath != buildServerIndexStorePath {
        logger.error(
          """
          Compiler arguments specify index store path \(indexStorePath) but build server specified an \
          incompatible index store path \(buildServerIndexStorePath). Overriding with the path specified by the build \
          system. For \(uris)
          """
        )
        args[indexStorePathIndex + 1] = buildServerIndexStorePath
      }
    } else {
      args += ["-index-store-path", buildServerIndexStorePath]
    }
    return args
  }

  /// If the build settings contain an `-index-unit-output-path` argument, remove it and return the index unit output
  /// path. Otherwise don't modify `buildSettings` and return `nil`.
  private func removeIndexUnitOutputPath(from buildSettings: inout FileBuildSettings, for uri: DocumentURI) -> String? {
    guard let indexUnitOutputPathIndex = buildSettings.compilerArguments.lastIndex(of: "-index-unit-output-path"),
      indexUnitOutputPathIndex + 1 < buildSettings.compilerArguments.count
    else {
      return nil
    }
    let indexUnitOutputPath = buildSettings.compilerArguments[indexUnitOutputPathIndex + 1]
    buildSettings.compilerArguments.removeSubrange(indexUnitOutputPathIndex...(indexUnitOutputPathIndex + 1))
    if buildSettings.compilerArguments.contains("-index-unit-output-path") {
      logger.error("Build settings contained two -index-unit-output-path arguments")
      BuildSettingsLogger.log(settings: buildSettings, for: uri)
    }
    return indexUnitOutputPath
  }

  private func updateIndexStore(
    forSwiftFilesInPartition partition: UpdateIndexStorePartition,
    toolchain: Toolchain
  ) async throws {
    guard let swiftc = toolchain.swiftc else {
      logger.error(
        "Not updating index store for \(partition.files) because toolchain \(toolchain.identifier) does not contain a Swift compiler"
      )
      return
    }

    var args =
      try [swiftc.filePath] + partition.buildSettings.compilerArguments + [
        "-index-file",
        // batch mode is not compatible with -index-file
        "-disable-batch-mode",
      ]
    args = try await addOrReplaceIndexStorePath(in: args, for: partition.files.map(\.mainFile))

    switch partition {
    case .multipleFiles(let filesAndOutputPaths, let buildSettings):
      if await !toolchain.canIndexMultipleSwiftFilesInSingleInvocation {
        // We should never get here because we shouldn't create `multipleFiles` batches if the toolchain doesn't support
        // indexing multiple files in a single compiler invocation.
        logger.fault("Cannot index multiple files in a single compiler invocation.")
      }

      struct OutputFileMapEntry: Encodable {
        let indexUnitOutputPath: String

        private enum CodingKeys: String, CodingKey {
          case indexUnitOutputPath = "index-unit-output-path"
        }
      }
      var outputFileMap: [String: OutputFileMapEntry] = [:]
      for (fileInfo, outputPath) in filesAndOutputPaths {
        guard let filePath = try? fileInfo.mainFile.fileURL?.filePath else {
          logger.error("Failed to determine file path of file to index \(fileInfo.mainFile.forLogging)")
          continue
        }
        outputFileMap[filePath] = .init(indexUnitOutputPath: outputPath)
      }
      let tempFileUri = FileManager.default.temporaryDirectory
        .appending(component: "sourcekit-lsp-output-file-map-\(UUID().uuidString).json")
      try JSONEncoder().encode(outputFileMap).write(to: tempFileUri)
      defer {
        orLog("Delete output file map") {
          try FileManager.default.removeItem(at: tempFileUri)
        }
      }

      let indexFiles = filesAndOutputPaths.map(\.file.mainFile)
      // If the compiler arguments already contain an `-output-file-map` argument, we override it by adding a second one
      // This is fine because we shouldn't be generating any outputs except for the index.
      args += ["-output-file-map", try tempFileUri.filePath]
      args += indexFiles.flatMap { (indexFile) -> [String] in
        guard let filePath = try? indexFile.fileURL?.filePath else {
          logger.error("Failed to determine file path of file to index \(indexFile.forLogging)")
          return []
        }
        return ["-index-file-path", filePath]
      }

      try await runIndexingProcess(
        indexFiles: indexFiles,
        buildSettings: buildSettings,
        processArguments: args,
        workingDirectory: buildSettings.workingDirectoryPath
      )
    case .singleFile(let file, let buildSettings):
      // We only end up in this case if the file's build settings didn't contain `-index-unit-output-path` and the build
      // server is not a `outputPathsProvider`.
      args += ["-index-file-path", file.mainFile.pseudoPath]

      try await runIndexingProcess(
        indexFiles: [file.mainFile],
        buildSettings: buildSettings,
        processArguments: args,
        workingDirectory: buildSettings.workingDirectoryPath
      )
    }
  }

  private func updateIndexStore(
    forClangFile uri: DocumentURI,
    buildSettings: FileBuildSettings,
    toolchain: Toolchain
  ) async throws {
    guard let clang = toolchain.clang else {
      logger.error(
        "Not updating index store for \(uri.forLogging) because toolchain \(toolchain.identifier) does not contain clang"
      )
      return
    }

    var args = [try clang.filePath] + buildSettings.compilerArguments
    args = try await addOrReplaceIndexStorePath(in: args, for: [uri])

    try await runIndexingProcess(
      indexFiles: [uri],
      buildSettings: buildSettings,
      processArguments: args,
      workingDirectory: buildSettings.workingDirectoryPath
    )
  }

  private func runIndexingProcess(
    indexFiles: [DocumentURI],
    buildSettings: FileBuildSettings,
    processArguments: [String],
    workingDirectory: AbsolutePath?
  ) async throws {
    if Task.isCancelled {
      return
    }
    let start = ContinuousClock.now
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: "indexing").makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval(
      "Indexing",
      id: signpostID,
      "Indexing \(indexFiles.map { $0.fileURL?.lastPathComponent ?? $0.pseudoPath })"
    )
    defer {
      signposter.endInterval("Indexing", state)
    }
    let taskId = "indexing-\(id)"
    logMessageToIndexLog(
      processArguments.joined(separator: " "),
      .info,
      .begin(
        StructuredLogBegin(title: "Indexing \(indexFiles.map(\.pseudoPath).joined(separator: ", "))", taskID: taskId)
      )
    )

    let stdoutHandler = PipeAsStringHandler {
      logMessageToIndexLog($0, .info, .report(StructuredLogReport(taskID: taskId)))
    }
    let stderrHandler = PipeAsStringHandler {
      logMessageToIndexLog($0, .info, .report(StructuredLogReport(taskID: taskId)))
    }

    let result: ProcessResult
    do {
      result = try await withTimeout(timeout) {
        try await Process.runUsingResponseFileIfTooManyArguments(
          arguments: processArguments,
          workingDirectory: workingDirectory,
          outputRedirection: .stream(
            stdout: { @Sendable bytes in stdoutHandler.handleDataFromPipe(Data(bytes)) },
            stderr: { @Sendable bytes in stderrHandler.handleDataFromPipe(Data(bytes)) }
          )
        )
      }
    } catch {
      logMessageToIndexLog(
        "Finished with error in \(start.duration(to: .now)): \(error)",
        .error,
        .end(StructuredLogEnd(taskID: taskId))
      )
      throw error
    }
    let exitStatus = result.exitStatus.exhaustivelySwitchable
    logMessageToIndexLog(
      "Finished with \(exitStatus.description) in \(start.duration(to: .now))",
      exitStatus.isSuccess ? .info : .error,
      .end(StructuredLogEnd(taskID: taskId))
    )
    switch exitStatus {
    case .terminated(code: 0):
      break
    case .terminated(let code):
      // This most likely happens if there are compilation errors in the source file. This is nothing to worry about.
      let stdout = (try? String(bytes: result.output.get(), encoding: .utf8)) ?? "<failed to decode stdout>"
      let stderr = (try? String(bytes: result.stderrOutput.get(), encoding: .utf8)) ?? "<failed to decode stderr>"
      // Indexing will frequently fail if the source code is in an invalid state. Thus, log the failure at a low level.
      logger.debug(
        """
        Updating index store terminated with non-zero exit code \(code) for \(indexFiles)
        Stderr:
        \(stderr)
        Stdout:
        \(stdout)
        """
      )
      BuildSettingsLogger.log(level: .debug, settings: buildSettings, for: indexFiles)
    case .signalled(let signal):
      if !Task.isCancelled {
        // The indexing job finished with a signal. Could be because the compiler crashed.
        // Ignore signal exit codes if this task has been cancelled because the compiler exits with SIGINT if it gets
        // interrupted.
        logger.error("Updating index store signaled \(signal) for \(indexFiles)")
        BuildSettingsLogger.log(level: .error, settings: buildSettings, for: indexFiles)
      }
    case .abnormal(let exception):
      if !Task.isCancelled {
        logger.error("Updating index store exited abnormally \(exception) for \(indexFiles)")
        BuildSettingsLogger.log(level: .error, settings: buildSettings, for: indexFiles)
      }
    }
  }

  /// Partition the given `FileIndexInfos` into batches so that a single `UpdateIndexStoreTaskDescription` should be
  /// created for every one of these batches, taking advantage of multi-file indexing when it is supported.
  static func batches(
    toIndex fileIndexInfos: [FileIndexInfo],
    buildServerManager: BuildServerManager
  ) async -> [(target: BuildTargetIdentifier, language: Language, files: [FileIndexInfo])] {
    struct TargetAndLanguage: Hashable, Comparable {
      let target: BuildTargetIdentifier
      let language: Language

      static func < (lhs: TargetAndLanguage, rhs: TargetAndLanguage) -> Bool {
        if lhs.target.uri.stringValue < rhs.target.uri.stringValue {
          return true
        } else if lhs.target.uri.stringValue > rhs.target.uri.stringValue {
          return false
        }
        if lhs.language.rawValue < rhs.language.rawValue {
          return true
        } else if lhs.language.rawValue > rhs.language.rawValue {
          return false
        }
        return false
      }
    }

    var partitions: [(target: BuildTargetIdentifier, language: Language, files: [FileIndexInfo])] = []
    var fileIndexInfosToBatch: [TargetAndLanguage: [FileIndexInfo]] = [:]
    for fileIndexInfo in fileIndexInfos {
      guard fileIndexInfo.language == .swift,
        await buildServerManager.toolchain(for: fileIndexInfo.target, language: fileIndexInfo.language)?
          .canIndexMultipleSwiftFilesInSingleInvocation ?? false
      else {
        // Only Swift supports indexing multiple files in a single compiler invocation, so don't batch files of other
        // languages.
        partitions.append((fileIndexInfo.target, fileIndexInfo.language, [fileIndexInfo]))
        continue
      }
      // Even for Swift files, we can only index files in a single compiler invocation if they have the same build
      // settings (modulo some normalization in `updateIndexStore(forFiles:)`). We can't know that all the files do
      // indeed have the same compiler arguments but loading build settings during scheduling from the build server
      // is not desirable because it slows down a bottleneck.
      // Since Swift files within the same target should build a single module, it is reasonable to assume that they all
      // share the same build settings.
      let languageAndTarget = TargetAndLanguage(target: fileIndexInfo.target, language: fileIndexInfo.language)
      fileIndexInfosToBatch[languageAndTarget, default: []].append(fileIndexInfo)
    }
    // Create one partition per processor core but limit the partition size to 25 primary files. This matches the
    // driver's behavior in `numberOfBatchPartitions`
    // https://github.com/swiftlang/swift-driver/blob/df3d0796ed5e533d82accd7baac43d15e97b5671/Sources/SwiftDriver/Jobs/Planning.swift#L917-L1022
    let partitionSize = max(fileIndexInfosToBatch.count / ProcessInfo.processInfo.activeProcessorCount, 25)
    let batchedPartitions =
      fileIndexInfosToBatch
      .sorted { $0.key < $1.key }  // Ensure we get a deterministic partition order
      .flatMap { targetAndLanguage, files in
        files.partition(intoBatchesOfSize: partitionSize).map {
          (targetAndLanguage.target, targetAndLanguage.language, $0)
        }
      }
    return partitions + batchedPartitions
  }
}

fileprivate extension Process {
  /// Run a process with the given arguments. If the number of arguments exceeds the maximum number of arguments allows,
  /// create a response file and use it to pass the arguments.
  static func runUsingResponseFileIfTooManyArguments(
    arguments: [String],
    workingDirectory: AbsolutePath?,
    outputRedirection: OutputRedirection = .collect(redirectStderr: false)
  ) async throws -> ProcessResult {
    do {
      return try await Process.run(
        arguments: arguments,
        workingDirectory: workingDirectory,
        outputRedirection: outputRedirection
      )
    } catch {
      let argumentListTooLong: Bool
      #if os(Windows)
      if let error = error as? CocoaError {
        argumentListTooLong =
          error.underlyingErrors.contains(where: {
            return ($0 as NSError).domain == "org.swift.Foundation.WindowsError"
              && ($0 as NSError).code == ERROR_FILENAME_EXCED_RANGE
          })
      } else {
        argumentListTooLong = false
      }
      #else
      if case SystemError.posix_spawn(E2BIG, _) = error {
        argumentListTooLong = true
      } else {
        argumentListTooLong = false
      }
      #endif

      guard argumentListTooLong else {
        throw error
      }

      logger.debug("Argument list is too long. Using response file.")
      let responseFile = FileManager.default.temporaryDirectory.appending(
        component: "index-response-file-\(UUID()).txt"
      )
      defer {
        orLog("Failed to remove temporary response file") {
          try FileManager.default.removeItem(at: responseFile)
        }
      }
      try FileManager.default.createFile(at: responseFile, contents: nil)
      let handle = try FileHandle(forWritingTo: responseFile)
      for argument in arguments.dropFirst() {
        handle.write(Data((argument.spm_shellEscaped() + "\n").utf8))
      }
      try handle.close()

      return try await Process.run(
        arguments: arguments.prefix(1) + ["@\(responseFile.filePath)"],
        workingDirectory: workingDirectory,
        outputRedirection: outputRedirection
      )
    }
  }
}

fileprivate extension FileBuildSettings {
  var workingDirectoryPath: AbsolutePath? {
    get throws {
      guard let workingDirectory else {
        return nil
      }
      return try AbsolutePath(validating: workingDirectory)
    }
  }
}
