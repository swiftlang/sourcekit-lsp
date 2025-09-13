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
package import BuildServerProtocol
import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry

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
      if self.filesToIndex.count < other.filesToIndex.count {
        // If there is an index operation with more files already running, suspend it.
        // The most common use case for this is if we schedule an entire target to be indexed in the background and then
        // need a single file indexed for use interaction. We should suspend the target-wide indexing and just index
        // the current file to get index data for it ASAP.
        return .cancelAndRescheduleDependency(other)
      } else {
        return .waitAndElevatePriorityOfDependency(other)
      }
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
      if !hasUpToDateUnit {
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

    for fileInfo in fileInfos {
      let buildSettings = await buildServerManager.buildSettings(
        for: fileInfo.mainFile,
        in: target,
        language: language,
        fallbackAfterTimeout: false
      )
      guard let buildSettings else {
        logger.error("Not indexing \(fileInfo.file.forLogging) because it has no compiler arguments")
        continue
      }
      if buildSettings.isFallback {
        // Fallback build settings don’t even have an indexstore path set, so they can't generate index data that we would
        // pick up. Also, indexing with fallback args has some other problems:∂
        // - If it did generate a unit file, we would consider the file’s index up-to-date even if the compiler arguments
        //   change, which means that we wouldn't get any up-to-date-index even when we have build settings for the file.
        // - It's unlikely that the index from a single file with fallback arguments will be very useful as it can't tie
        //   into the rest of the project.
        // So, don't index the file.
        logger.error("Not indexing \(fileInfo.file.forLogging) because it has fallback compiler arguments")
        continue
      }

      guard let toolchain = await buildServerManager.toolchain(for: target, language: buildSettings.language) else {
        logger.fault(
          "Unable to determine toolchain to index \(buildSettings.language.description, privacy: .public) files in \(target.forLogging)"
        )
        continue
      }
      let startDate = Date()
      switch buildSettings.language.semanticKind {
      case .swift:
        do {
          try await updateIndexStore(
            forSwiftFiles: [fileInfo.mainFile],
            buildSettings: buildSettings,
            toolchain: toolchain
          )
        } catch {
          logger.error("Updating index store for \(fileInfo.mainFile) failed: \(error.forLogging)")
          BuildSettingsLogger.log(settings: buildSettings, for: fileInfo.mainFile)
        }
      case .clang:
        do {
          try await updateIndexStore(
            forClangFile: fileInfo.mainFile,
            buildSettings: buildSettings,
            toolchain: toolchain
          )
        } catch {
          logger.error("Updating index store for \(fileInfo.mainFile.forLogging) failed: \(error.forLogging)")
          BuildSettingsLogger.log(settings: buildSettings, for: fileInfo.mainFile)
        }
      case nil:
        logger.error(
          "Not updating index store for \(fileInfo.mainFile.forLogging) because it is a language that is not supported by background indexing"
        )
      }
      await indexStoreUpToDateTracker.markUpToDate([(fileInfo.sourceFile, target)], updateOperationStartDate: startDate)
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
          Compiler arguments for specify index store path \(indexStorePath) but build server specified an \
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

  private func updateIndexStore(
    forSwiftFiles uris: [DocumentURI],
    buildSettings: FileBuildSettings,
    toolchain: Toolchain
  ) async throws {
    guard let swiftc = toolchain.swiftc else {
      logger.error(
        "Not updating index store for \(uris) because toolchain \(toolchain.identifier) does not contain a Swift compiler"
      )
      return
    }

    var args =
      try [swiftc.filePath] + buildSettings.compilerArguments + [
        "-index-file",
        // batch mode is not compatible with -index-file
        "-disable-batch-mode",
      ] + uris.flatMap { ["-index-file-path", $0.pseudoPath] }
    args = try await addOrReplaceIndexStorePath(in: args, for: uris)

    try await runIndexingProcess(
      indexFiles: uris,
      buildSettings: buildSettings,
      processArguments: args,
      workingDirectory: buildSettings.workingDirectory.map(AbsolutePath.init(validating:))
    )
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
      workingDirectory: buildSettings.workingDirectory.map(AbsolutePath.init(validating:))
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
        Updating index store for terminated with non-zero exit code \(code) for \(indexFiles)
        Stderr:
        \(stderr)
        Stdout:
        \(stdout)
        """
      )
    // BuildSettingsLogger.log(level: .debug, settings: buildSettings, for: indexFile)
    case .signalled(let signal):
      if !Task.isCancelled {
        // The indexing job finished with a signal. Could be because the compiler crashed.
        // Ignore signal exit codes if this task has been cancelled because the compiler exits with SIGINT if it gets
        // interrupted.
        logger.error("Updating index store for signaled \(signal) for \(indexFiles)")
        // BuildSettingsLogger.log(level: .error, settings: buildSettings, for: indexFile)
      }
    case .abnormal(let exception):
      if !Task.isCancelled {
        logger.error("Updating index store exited abnormally \(exception) for \(indexFiles)")
        // BuildSettingsLogger.log(level: .error, settings: buildSettings, for: indexFile)
      }
    }
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
      let responseFile = FileManager.default.temporaryDirectory.appendingPathComponent(
        "index-response-file-\(UUID()).txt"
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
