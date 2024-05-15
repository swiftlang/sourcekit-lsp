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

import CAtomics
import Foundation
import LSPLogging
import LanguageServerProtocol
import SKCore
import SKSupport

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

private nonisolated(unsafe) var updateIndexStoreIDForLogging = AtomicUInt32(initialValue: 1)

/// Describes a task to index a set of source files.
///
/// This task description can be scheduled in a `TaskScheduler`.
public struct UpdateIndexStoreTaskDescription: IndexTaskDescription {
  public static let idPrefix = "update-indexstore"
  public let id = updateIndexStoreIDForLogging.fetchAndIncrement()

  /// The files that should be indexed.
  private let filesToIndex: Set<DocumentURI>

  /// The build system manager that is used to get the toolchain and build settings for the files to index.
  private let buildSystemManager: BuildSystemManager

  /// A reference to the underlying index store. Used to check if the index is already up-to-date for a file, in which
  /// case we don't need to index it again.
  private let index: UncheckedIndex

  /// The task is idempotent because indexing the same file twice produces the same result as indexing it once.
  public var isIdempotent: Bool { true }

  public var estimatedCPUCoreCount: Int { 1 }

  public var description: String {
    return self.redactedDescription
  }

  public var redactedDescription: String {
    return "update-indexstore-\(id)"
  }

  init(
    filesToIndex: Set<DocumentURI>,
    buildSystemManager: BuildSystemManager,
    index: UncheckedIndex
  ) {
    self.filesToIndex = filesToIndex
    self.buildSystemManager = buildSystemManager
    self.index = index
  }

  public func execute() async {
    // Only use the last two digits of the indexing ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running indexing operation.
    await withLoggingSubsystemAndScope(
      subsystem: "org.swift.sourcekit-lsp.indexing",
      scope: "update-indexstore-\(id % 100)"
    ) {
      let startDate = Date()

      let filesToIndexDescription = filesToIndex.map { $0.fileURL?.lastPathComponent ?? $0.stringValue }
        .joined(separator: ", ")
      logger.log(
        "Starting updating index store with priority \(Task.currentPriority.rawValue, privacy: .public): \(filesToIndexDescription)"
      )
      let filesToIndex = filesToIndex.sorted(by: { $0.stringValue < $1.stringValue })
      // TODO (indexing): Once swiftc supports it, we should group files by target and index files within the same
      // target together in one swiftc invocation.
      // https://github.com/apple/sourcekit-lsp/issues/1268
      for file in filesToIndex {
        await updateIndexStoreForSingleFile(file)
      }
      logger.log(
        "Finished updating index store in \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms: \(filesToIndexDescription)"
      )
    }
  }

  public func dependencies(
    to currentlyExecutingTasks: [UpdateIndexStoreTaskDescription]
  ) -> [TaskDependencyAction<UpdateIndexStoreTaskDescription>] {
    return currentlyExecutingTasks.compactMap { (other) -> TaskDependencyAction<UpdateIndexStoreTaskDescription>? in
      guard !other.filesToIndex.intersection(filesToIndex).isEmpty else {
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

  private func updateIndexStoreForSingleFile(_ uri: DocumentURI) async {
    guard let url = uri.fileURL else {
      // The URI is not a file, so there's nothing we can index.
      return
    }
    guard !index.checked(for: .modifiedFiles).hasUpToDateUnit(for: url) else {
      // We consider a file's index up-to-date if we have any up-to-date unit. Changing build settings does not
      // invalidate the up-to-date status of the index.
      return
    }
    guard let language = await buildSystemManager.defaultLanguage(for: uri) else {
      logger.error("Not indexing \(uri.forLogging) because its language could not be determined")
      return
    }
    let buildSettings = await buildSystemManager.buildSettingsInferredFromMainFile(
      for: uri,
      language: language,
      logBuildSettings: false
    )
    guard let buildSettings else {
      logger.error("Not indexing \(uri.forLogging) because it has no compiler arguments")
      return
    }
    guard let toolchain = await buildSystemManager.toolchain(for: uri, language) else {
      logger.error(
        "Not updating index store for \(uri.forLogging) because no toolchain could be determined for the document"
      )
      return
    }
    switch language {
    case .swift:
      do {
        try await updateIndexStore(forSwiftFile: uri, buildSettings: buildSettings, toolchain: toolchain)
      } catch {
        logger.error("Updating index store for \(uri) failed: \(error.forLogging)")
        BuildSettingsLogger.log(settings: buildSettings, for: uri)
      }
    case .c, .cpp, .objective_c, .objective_cpp:
      do {
        try await updateIndexStore(forClangFile: uri, buildSettings: buildSettings, toolchain: toolchain)
      } catch {
        logger.error("Updating index store for \(uri) failed: \(error.forLogging)")
        BuildSettingsLogger.log(settings: buildSettings, for: uri)
      }
    default:
      logger.error(
        "Not updating index store for \(uri) because it is a language that is not supported by background indexing"
      )
    }
  }

  private func updateIndexStore(
    forSwiftFile uri: DocumentURI,
    buildSettings: FileBuildSettings,
    toolchain: Toolchain
  ) async throws {
    guard let swiftc = toolchain.swiftc else {
      logger.error(
        "Not updating index store for \(uri.forLogging) because toolchain \(toolchain.identifier) does not contain a Swift compiler"
      )
      return
    }

    let indexingArguments = adjustSwiftCompilerArgumentsForIndexStoreUpdate(
      buildSettings.compilerArguments,
      fileToIndex: uri
    )

    try await runIndexingProcess(
      indexFile: uri,
      buildSettings: buildSettings,
      processArguments: [swiftc.pathString] + indexingArguments,
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

    let indexingArguments = adjustClangCompilerArgumentsForIndexStoreUpdate(
      buildSettings.compilerArguments,
      fileToIndex: uri
    )

    try await runIndexingProcess(
      indexFile: uri,
      buildSettings: buildSettings,
      processArguments: [clang.pathString] + indexingArguments,
      workingDirectory: buildSettings.workingDirectory.map(AbsolutePath.init(validating:))
    )
  }

  private func runIndexingProcess(
    indexFile: DocumentURI,
    buildSettings: FileBuildSettings,
    processArguments: [String],
    workingDirectory: AbsolutePath?
  ) async throws {
    let process = try Process.launch(
      arguments: processArguments,
      workingDirectory: workingDirectory
    )
    let result = try await process.waitUntilExitSendingSigIntOnTaskCancellation()
    switch result.exitStatus.exhaustivelySwitchable {
    case .terminated(code: 0):
      break
    case .terminated(code: let code):
      // This most likely happens if there are compilation errors in the source file. This is nothing to worry about.
      let stdout = (try? String(bytes: result.output.get(), encoding: .utf8)) ?? "<no stderr>"
      let stderr = (try? String(bytes: result.stderrOutput.get(), encoding: .utf8)) ?? "<no stderr>"
      // Indexing will frequently fail if the source code is in an invalid state. Thus, log the failure at a low level.
      logger.debug(
        """
        Updating index store for \(indexFile.forLogging) terminated with non-zero exit code \(code)
        Stderr:
        \(stderr)
        Stdout:
        \(stdout)
        """
      )
      BuildSettingsLogger.log(level: .debug, settings: buildSettings, for: indexFile)
    case .signalled(signal: let signal):
      if !Task.isCancelled {
        // The indexing job finished with a signal. Could be because the compiler crashed.
        // Ignore signal exit codes if this task has been cancelled because the compiler exits with SIGINT if it gets
        // interrupted.
        logger.error("Updating index store for \(indexFile.forLogging) signaled \(signal)")
        BuildSettingsLogger.log(level: .error, settings: buildSettings, for: indexFile)
      }
    case .abnormal(exception: let exception):
      if !Task.isCancelled {
        logger.error("Updating index store for \(indexFile.forLogging) exited abnormally \(exception)")
        BuildSettingsLogger.log(level: .error, settings: buildSettings, for: indexFile)
      }
    }
  }
}

/// Adjust compiler arguments that were created for building to compiler arguments that should be used for indexing.
///
/// This removes compiler arguments that produce output files and adds arguments to index the file.
private func adjustSwiftCompilerArgumentsForIndexStoreUpdate(
  _ compilerArguments: [String],
  fileToIndex: DocumentURI
) -> [String] {
  let removeFlags: Set<String> = [
    "-c",
    "-disable-cmo",
    "-emit-dependencies",
    "-emit-module-interface",
    "-emit-module",
    "-emit-module",
    "-emit-objc-header",
    "-incremental",
    "-no-color-diagnostics",
    "-parseable-output",
    "-save-temps",
    "-serialize-diagnostics",
    "-use-frontend-parseable-output",
    "-validate-clang-modules-once",
    "-whole-module-optimization",
  ]

  let removeArguments: Set<String> = [
    "-clang-build-session-file",
    "-emit-module-interface-path",
    "-emit-module-path",
    "-emit-objc-header-path",
    "-emit-package-module-interface-path",
    "-emit-private-module-interface-path",
    "-num-threads",
    "-o",
    "-output-file-map",
  ]

  let removeFrontendFlags: Set<String> = [
    "-experimental-skip-non-inlinable-function-bodies",
    "-experimental-skip-all-function-bodies",
  ]

  var result: [String] = []
  result.reserveCapacity(compilerArguments.count)
  var iterator = compilerArguments.makeIterator()
  while let argument = iterator.next() {
    if removeFlags.contains(argument) {
      continue
    }
    if removeArguments.contains(argument) {
      _ = iterator.next()
      continue
    }
    if argument == "-Xfrontend" {
      if let nextArgument = iterator.next() {
        if removeFrontendFlags.contains(nextArgument) {
          continue
        }
        result += [argument, nextArgument]
        continue
      }
    }
    result.append(argument)
  }
  result += [
    "-index-file",
    "-index-file-path", fileToIndex.pseudoPath,
    // batch mode is not compatible with -index-file
    "-disable-batch-mode",
    // Fake an output path so that we get a different unit file for every Swift file we background index
    "-index-unit-output-path", fileToIndex.pseudoPath + ".o",
  ]
  return result
}

/// Adjust compiler arguments that were created for building to compiler arguments that should be used for indexing.
///
/// This removes compiler arguments that produce output files and adds arguments to index the file.
private func adjustClangCompilerArgumentsForIndexStoreUpdate(
  _ compilerArguments: [String],
  fileToIndex: DocumentURI
) -> [String] {
  let removeFlags: Set<String> = [
    // Disable writing of a depfile
    "-M",
    "-MD",
    "-MMD",
    "-MG",
    "-MM",
    "-MV",
    // Don't create phony targets
    "-MP",
    // Don't writ out compilation databases
    "-MJ",
    // Continue in the presence of errors during indexing
    "-fmodules-validate-once-per-build-session",
    // Don't compile
    "-c",
  ]

  let removeArguments: Set<String> = [
    // Disable writing of a depfile
    "-MT",
    "-MF",
    "-MQ",
    // Don't write serialized diagnostic files
    "--serialize-diagnostics",
  ]

  var result: [String] = []
  result.reserveCapacity(compilerArguments.count)
  var iterator = compilerArguments.makeIterator()
  while let argument = iterator.next() {
    if removeFlags.contains(argument) || argument.starts(with: "-fbuild-session-file=") {
      continue
    }
    if removeArguments.contains(argument) {
      _ = iterator.next()
      continue
    }
    result.append(argument)
  }
  result.append(
    "-fsyntax-only"
  )
  return result
}
