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

import Foundation
import LSPLogging
import LanguageServerProtocol
import SKCore
import SKSupport
import SwiftExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

private nonisolated(unsafe) var updateIndexStoreIDForLogging = AtomicUInt32(initialValue: 1)

public enum FileToIndex: CustomLogStringConvertible {
  /// A non-header file
  case indexableFile(DocumentURI)

  /// A header file where `mainFile` should be indexed to update the index of `header`.
  case headerFile(header: DocumentURI, mainFile: DocumentURI)

  /// The file whose index store should be updated.
  ///
  /// This file might be a header file that doesn't have build settings associated with it. For the actual compiler
  /// invocation that updates the index store, the `mainFile` should be used.
  public var sourceFile: DocumentURI {
    switch self {
    case .indexableFile(let uri): return uri
    case .headerFile(header: let header, mainFile: _): return header
    }
  }

  /// The file that should be used for compiler invocations that update the index.
  ///
  /// If the `sourceFile` is a header file, this will be a main file that includes the header. Otherwise, it will be the
  /// same as `sourceFile`.
  var mainFile: DocumentURI {
    switch self {
    case .indexableFile(let uri): return uri
    case .headerFile(header: _, mainFile: let mainFile): return mainFile
    }
  }

  public var description: String {
    switch self {
    case .indexableFile(let uri):
      return uri.description
    case .headerFile(header: let header, mainFile: let mainFile):
      return "\(header.description) using main file \(mainFile.description)"
    }
  }

  public var redactedDescription: String {
    switch self {
    case .indexableFile(let uri):
      return uri.redactedDescription
    case .headerFile(header: let header, mainFile: let mainFile):
      return "\(header.redactedDescription) using main file \(mainFile.redactedDescription)"
    }
  }
}

/// A file to index and the target in which the file should be indexed.
public struct FileAndTarget: Sendable {
  public let file: FileToIndex
  public let target: ConfiguredTarget
}

private enum IndexKind {
  case clang
  case swift

  init?(language: Language) {
    switch language {
    case .swift:
      self = .swift
    case .c, .cpp, .objective_c, .objective_cpp:
      self = .clang
    default:
      return nil
    }
  }
}

/// Describes a task to index a set of source files.
///
/// This task description can be scheduled in a `TaskScheduler`.
public struct UpdateIndexStoreTaskDescription: IndexTaskDescription {
  public static let idPrefix = "update-indexstore"
  public let id = updateIndexStoreIDForLogging.fetchAndIncrement()

  /// The files that should be indexed.
  public let filesToIndex: [FileAndTarget]

  /// The build system manager that is used to get the toolchain and build settings for the files to index.
  private let buildSystemManager: BuildSystemManager

  private let indexStoreUpToDateTracker: UpToDateTracker<DocumentURI>

  /// A reference to the underlying index store. Used to check if the index is already up-to-date for a file, in which
  /// case we don't need to index it again.
  private let index: UncheckedIndex

  /// See `SemanticIndexManager.logMessageToIndexLog`.
  private let logMessageToIndexLog: @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void

  /// Test hooks that should be called when the index task finishes.
  private let testHooks: IndexTestHooks

  /// The task is idempotent because indexing the same file twice produces the same result as indexing it once.
  public var isIdempotent: Bool { true }

  public var estimatedCPUCoreCount: Int { 1 }

  public var description: String {
    return self.redactedDescription
  }

  public var redactedDescription: String {
    return "update-indexstore-\(id)"
  }

  static func canIndex(language: Language) -> Bool {
    return IndexKind(language: language) != nil
  }

  init(
    filesToIndex: [FileAndTarget],
    buildSystemManager: BuildSystemManager,
    index: UncheckedIndex,
    indexStoreUpToDateTracker: UpToDateTracker<DocumentURI>,
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void,
    testHooks: IndexTestHooks
  ) {
    self.filesToIndex = filesToIndex
    self.buildSystemManager = buildSystemManager
    self.index = index
    self.indexStoreUpToDateTracker = indexStoreUpToDateTracker
    self.logMessageToIndexLog = logMessageToIndexLog
    self.testHooks = testHooks
  }

  public func execute() async {
    // Only use the last two digits of the indexing ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running indexing operation.
    await withLoggingSubsystemAndScope(subsystem: indexLoggingSubsystem, scope: "update-indexstore-\(id % 100)") {
      let startDate = Date()

      await testHooks.updateIndexStoreTaskDidStart?(self)

      let filesToIndexDescription = filesToIndex.map {
        $0.file.sourceFile.fileURL?.lastPathComponent ?? $0.file.sourceFile.stringValue
      }
      .joined(separator: ", ")
      logger.log(
        "Starting updating index store with priority \(Task.currentPriority.rawValue, privacy: .public): \(filesToIndexDescription)"
      )
      let filesToIndex = filesToIndex.sorted(by: { $0.file.sourceFile.stringValue < $1.file.sourceFile.stringValue })
      // TODO (indexing): Once swiftc supports it, we should group files by target and index files within the same
      // target together in one swiftc invocation.
      // https://github.com/apple/sourcekit-lsp/issues/1268
      for file in filesToIndex {
        await updateIndexStore(forSingleFile: file.file, in: file.target)
      }
      await testHooks.updateIndexStoreTaskDidFinish?(self)
      logger.log(
        "Finished updating index store in \(Date().timeIntervalSince(startDate) * 1000, privacy: .public)ms: \(filesToIndexDescription)"
      )
    }
  }

  public func dependencies(
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

  private func updateIndexStore(forSingleFile file: FileToIndex, in target: ConfiguredTarget) async {
    guard await !indexStoreUpToDateTracker.isUpToDate(file.sourceFile) else {
      // If we know that the file is up-to-date without having ot hit the index, do that because it's fastest.
      return
    }
    guard !index.checked(for: .modifiedFiles).hasUpToDateUnit(for: file.sourceFile, mainFile: file.mainFile)
    else {
      logger.debug("Not indexing \(file.forLogging) because index has an up-to-date unit")
      // We consider a file's index up-to-date if we have any up-to-date unit. Changing build settings does not
      // invalidate the up-to-date status of the index.
      return
    }
    if file.mainFile != file.sourceFile {
      logger.log("Updating index store of \(file.forLogging) using main file \(file.mainFile.forLogging)")
    }
    guard let language = await buildSystemManager.defaultLanguage(for: file.mainFile) else {
      logger.error("Not indexing \(file.forLogging) because its language could not be determined")
      return
    }
    let buildSettings = await buildSystemManager.buildSettings(for: file.mainFile, in: target, language: language)
    guard let buildSettings else {
      logger.error("Not indexing \(file.forLogging) because it has no compiler arguments")
      return
    }
    if buildSettings.isFallback {
      // Fallback build settings don’t even have an indexstore path set, so they can't generate index data that we would
      // pick up. Also, indexing with fallback args has some other problems:
      // - If it did generate a unit file, we would consider the file’s index up-to-date even if the compiler arguments
      //   change, which means that we wouldn't get any up-to-date-index even when we have build settings for the file.
      // - It's unlikely that the index from a single file with fallback arguments will be very useful as it can't tie
      //   into the rest of the project.
      // So, don't index the file.
      logger.error("Not indexing \(file.forLogging) because it has fallback compiler arguments")
      return
    }
    guard let toolchain = await buildSystemManager.toolchain(for: file.mainFile, language) else {
      logger.error(
        "Not updating index store for \(file.forLogging) because no toolchain could be determined for the document"
      )
      return
    }
    let startDate = Date()
    switch IndexKind(language: language) {
    case .swift:
      do {
        try await updateIndexStore(
          forSwiftFile: file.mainFile,
          buildSettings: buildSettings,
          toolchain: toolchain
        )
      } catch {
        logger.error("Updating index store for \(file.forLogging) failed: \(error.forLogging)")
        BuildSettingsLogger.log(settings: buildSettings, for: file.mainFile)
      }
    case .clang:
      do {
        try await updateIndexStore(
          forClangFile: file.mainFile,
          buildSettings: buildSettings,
          toolchain: toolchain
        )
      } catch {
        logger.error("Updating index store for \(file) failed: \(error.forLogging)")
        BuildSettingsLogger.log(settings: buildSettings, for: file.mainFile)
      }
    case nil:
      logger.error(
        "Not updating index store for \(file) because it is a language that is not supported by background indexing"
      )
    }
    await indexStoreUpToDateTracker.markUpToDate([file.sourceFile], updateOperationStartDate: startDate)
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
    if Task.isCancelled {
      return
    }
    let start = ContinuousClock.now
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: "indexing").makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval(
      "Indexing",
      id: signpostID,
      "Indexing \(indexFile.fileURL?.lastPathComponent ?? indexFile.pseudoPath)"
    )
    defer {
      signposter.endInterval("Indexing", state)
    }
    let logID = IndexTaskID.updateIndexStore(id: id)
    logMessageToIndexLog(
      logID,
      """
      Indexing \(indexFile.pseudoPath)
      \(processArguments.joined(separator: " "))
      """
    )

    let stdoutHandler = PipeAsStringHandler { logMessageToIndexLog(logID, $0) }
    let stderrHandler = PipeAsStringHandler { logMessageToIndexLog(logID, $0) }

    // Time out updating of the index store after 2 minutes. We don't expect any single file compilation to take longer
    // than 2 minutes in practice, so this indicates that the compiler has entered a loop and we probably won't make any
    // progress here. We will try indexing the file again when it is edited or when the project is re-opened.
    // 2 minutes have been chosen arbitrarily.
    let result = try await withTimeout(.seconds(120)) {
      try await Process.run(
        arguments: processArguments,
        workingDirectory: workingDirectory,
        outputRedirection: .stream(
          stdout: { stdoutHandler.handleDataFromPipe(Data($0)) },
          stderr: { stderrHandler.handleDataFromPipe(Data($0)) }
        )
      )
    }
    let exitStatus = result.exitStatus.exhaustivelySwitchable
    logMessageToIndexLog(logID, "Finished with \(exitStatus.description) in \(start.duration(to: .now))")
    switch exitStatus {
    case .terminated(code: 0):
      break
    case .terminated(code: let code):
      // This most likely happens if there are compilation errors in the source file. This is nothing to worry about.
      let stdout = (try? String(bytes: result.output.get(), encoding: .utf8)) ?? "<failed to decode stdout>"
      let stderr = (try? String(bytes: result.stderrOutput.get(), encoding: .utf8)) ?? "<failed to decode stderr>"
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
  let optionsToRemove: [CompilerCommandLineOption] = [
    .flag("c", [.singleDash]),
    .flag("disable-cmo", [.singleDash]),
    .flag("emit-dependencies", [.singleDash]),
    .flag("emit-module-interface", [.singleDash]),
    .flag("emit-module", [.singleDash]),
    .flag("emit-objc-header", [.singleDash]),
    .flag("incremental", [.singleDash]),
    .flag("no-color-diagnostics", [.singleDash]),
    .flag("parseable-output", [.singleDash]),
    .flag("save-temps", [.singleDash]),
    .flag("serialize-diagnostics", [.singleDash]),
    .flag("use-frontend-parseable-output", [.singleDash]),
    .flag("validate-clang-modules-once", [.singleDash]),
    .flag("whole-module-optimization", [.singleDash]),

    .option("clang-build-session-file", [.singleDash], [.separatedBySpace]),
    .option("emit-module-interface-path", [.singleDash], [.separatedBySpace]),
    .option("emit-module-path", [.singleDash], [.separatedBySpace]),
    .option("emit-objc-header-path", [.singleDash], [.separatedBySpace]),
    .option("emit-package-module-interface-path", [.singleDash], [.separatedBySpace]),
    .option("emit-private-module-interface-path", [.singleDash], [.separatedBySpace]),
    .option("num-threads", [.singleDash], [.separatedBySpace]),
    // Technically, `-o` and the output file don't need to be separated by a space. Eg. `swiftc -oa file.swift` is
    // valid and will write to an output file named `a`.
    // We can't support that because the only way to know that `-output-file-map` is a different flag and not an option
    // to write to an output file named `utput-file-map` is to know all compiler arguments of `swiftc`, which we don't.
    .option("o", [.singleDash], [.separatedBySpace]),
    .option("output-file-map", [.singleDash], [.separatedBySpace, .separatedByEqualSign]),
  ]

  var result: [String] = []
  result.reserveCapacity(compilerArguments.count)
  var iterator = compilerArguments.makeIterator()
  while let argument = iterator.next() {
    switch optionsToRemove.firstMatch(for: argument) {
    case .removeOption:
      continue
    case .removeOptionAndNextArgument:
      _ = iterator.next()
      continue
    case nil:
      break
    }
    result.append(argument)
  }
  result += supplementalClangIndexingArgs.flatMap { ["-Xcc", $0] }
  result += [
    // Preparation produces modules with errors. We should allow reading them.
    "-Xfrontend", "-experimental-allow-module-with-compiler-errors",
    // Avoid emitting the ABI descriptor, we don't need it
    "-Xfrontend", "-empty-abi-descriptor",
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
  let optionsToRemove: [CompilerCommandLineOption] = [
    // Disable writing of a depfile
    .flag("M", [.singleDash]),
    .flag("MD", [.singleDash]),
    .flag("MMD", [.singleDash]),
    .flag("MG", [.singleDash]),
    .flag("MM", [.singleDash]),
    .flag("MV", [.singleDash]),
    // Don't create phony targets
    .flag("MP", [.singleDash]),
    // Don't write out compilation databases
    .flag("MJ", [.singleDash]),
    // Don't compile
    .flag("c", [.singleDash]),

    .flag("fmodules-validate-once-per-build-session", [.singleDash]),

    // Disable writing of a depfile
    .option("MT", [.singleDash], [.noSpace, .separatedBySpace]),
    .option("MF", [.singleDash], [.noSpace, .separatedBySpace]),
    .option("MQ", [.singleDash], [.noSpace, .separatedBySpace]),

    // Don't write serialized diagnostic files
    .option("serialize-diagnostics", [.singleDash, .doubleDash], [.separatedBySpace]),

    .option("fbuild-session-file", [.singleDash], [.separatedByEqualSign]),
  ]

  var result: [String] = []
  result.reserveCapacity(compilerArguments.count)
  var iterator = compilerArguments.makeIterator()
  while let argument = iterator.next() {
    switch optionsToRemove.firstMatch(for: argument) {
    case .removeOption:
      continue
    case .removeOptionAndNextArgument:
      _ = iterator.next()
      continue
    case nil:
      break
    }
    result.append(argument)
  }
  result += supplementalClangIndexingArgs
  result.append(
    "-fsyntax-only"
  )
  return result
}

#if compiler(>=6.1)
#warning(
  "Remove -fmodules-validate-system-headers from supplementalClangIndexingArgs once all supported Swift compilers have https://github.com/apple/swift/pull/74063"
)
#endif

fileprivate let supplementalClangIndexingArgs: [String] = [
  // Retain extra information for indexing
  "-fretain-comments-from-system-headers",
  // Pick up macro definitions during indexing
  "-Xclang", "-detailed-preprocessing-record",

  // libclang uses 'raw' module-format. Match it so we can reuse the module cache and PCHs that libclang uses.
  "-Xclang", "-fmodule-format=raw",

  // Be less strict - we want to continue and typecheck/index as much as possible
  "-Xclang", "-fallow-pch-with-compiler-errors",
  "-Xclang", "-fallow-pcm-with-compiler-errors",
  "-Wno-non-modular-include-in-framework-module",
  "-Wno-incomplete-umbrella",

  // sourcekitd adds `-fno-modules-validate-system-headers` before https://github.com/apple/swift/pull/74063.
  // This completely disables system module validation and never re-builds pcm for system modules. The intended behavior
  // is to only re-build those PCMs once per sourcekitd session.
  "-fmodules-validate-system-headers",
]

fileprivate extension Sequence {
  /// Returns `true` if this sequence contains an element that is equal to an element in `otherSequence` when
  /// considering two elements as equal if they satisfy `predicate`.
  func hasIntersection(
    with otherSequence: some Sequence<Element>,
    where predicate: (Element, Element) -> Bool
  ) -> Bool {
    for outer in self {
      for inner in otherSequence {
        if predicate(outer, inner) {
          return true
        }
      }
    }
    return false
  }
}
