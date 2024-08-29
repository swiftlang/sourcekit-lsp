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

import Basics
@preconcurrency import Build
import BuildServerProtocol
import Dispatch
import Foundation
import LanguageServerProtocol
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
import SKLogging
import SKOptions
import SKSupport
import SourceControl
import SourceKitLSPAPI
import SwiftExtensions
import ToolchainRegistry
@preconcurrency import Workspace

import struct Basics.AbsolutePath
import struct Basics.IdentifiableSet
import struct Basics.TSCAbsolutePath
import struct Foundation.URL
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import class TSCBasic.Process
import var TSCBasic.localFileSystem
import func TSCBasic.resolveSymlinks
import class ToolchainRegistry.Toolchain

fileprivate typealias AbsolutePath = Basics.AbsolutePath

#if canImport(SPMBuildCore)
@preconcurrency import SPMBuildCore
#endif

/// Parameter of `reloadPackageStatusCallback` in ``SwiftPMWorkspace``.
///
/// Informs the callback about whether `reloadPackage` started or finished executing.
package enum ReloadPackageStatus: Sendable {
  case start
  case end
}

/// A build target in SwiftPM
package typealias SwiftBuildTarget = SourceKitLSPAPI.BuildTarget

/// A build target in `BuildServerProtocol`
package typealias BuildServerTarget = BuildServerProtocol.BuildTarget

fileprivate extension BuildDestination {
  /// A string that can be used to identify the build triple in `ConfiguredTarget.runDestinationID`.
  ///
  /// `BuildSystemManager.canonicalConfiguredTarget` picks the canonical target based on alphabetical
  /// ordering. We rely on the string "destination" being ordered before "tools" so that we prefer a
  /// `destination` (or "target") target over a `tools` (or "host") target.
  var id: String {
    switch self {
    case .host:
      return "tools"
    case .target:
      return "destination"
    }
  }
}

fileprivate extension ConfiguredTarget {
  init(_ buildTarget: any SwiftBuildTarget) {
    self.init(targetID: buildTarget.name, runDestinationID: buildTarget.destination.id)
  }

  static let forPackageManifest = ConfiguredTarget(targetID: "", runDestinationID: "")
}

fileprivate let preparationTaskID: AtomicUInt32 = AtomicUInt32(initialValue: 0)

package struct SwiftPMTestHooks: Sendable {
  package var reloadPackageDidStart: (@Sendable () async -> Void)?
  package var reloadPackageDidFinish: (@Sendable () async -> Void)?

  package init(
    reloadPackageDidStart: (@Sendable () async -> Void)? = nil,
    reloadPackageDidFinish: (@Sendable () async -> Void)? = nil
  ) {
    self.reloadPackageDidStart = reloadPackageDidStart
    self.reloadPackageDidFinish = reloadPackageDidFinish
  }
}

/// Swift Package Manager build system and workspace support.
///
/// This class implements the `BuildSystem` interface to provide the build settings for a Swift
/// Package Manager (SwiftPM) package. The settings are determined by loading the Package.swift
/// manifest using `libSwiftPM` and constructing a build plan using the default (debug) parameters.
package actor SwiftPMBuildSystem {
  package enum Error: Swift.Error {
    /// Could not find a manifest (Package.swift file). This is not a package.
    case noManifest(workspacePath: TSCAbsolutePath)

    /// Could not determine an appropriate toolchain for swiftpm to use for manifest loading.
    case cannotDetermineHostToolchain
  }

  // MARK: Integration with SourceKit-LSP

  /// Options that allow the user to pass extra compiler flags.
  private let options: SourceKitLSPOptions

  private let testHooks: SwiftPMTestHooks

  /// Delegate to handle any build system events.
  package weak var delegate: BuildSystemIntegration.BuildSystemDelegate? = nil

  package func setDelegate(_ delegate: BuildSystemIntegration.BuildSystemDelegate?) async {
    self.delegate = delegate
  }

  /// This callback is informed when `reloadPackage` starts and ends executing.
  private var reloadPackageStatusCallback: (ReloadPackageStatus) async -> Void

  /// Callbacks that should be called if the list of possible test files has changed.
  private var testFilesDidChangeCallbacks: [() async -> Void] = []

  /// The URIs for which the delegate has registered for change notifications,
  /// mapped to the language the delegate specified when registering for change notifications.
  private var watchedFiles: Set<DocumentURI> = []

  /// Debounces calls to `delegate.filesDependenciesUpdated`.
  ///
  /// This is to ensure we don't call `filesDependenciesUpdated` for the same file multiple time if the client does not
  /// debounce `workspace/didChangeWatchedFiles` and sends a separate notification eg. for every file within a target as
  /// it's being updated by a git checkout, which would cause other files within that target to receive a
  /// `fileDependenciesUpdated` call once for every updated file within the target.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  private var fileDependenciesUpdatedDebouncer: Debouncer<Set<DocumentURI>>! = nil

  /// Whether the `SwiftPMBuildSystem` is pointed at a `.index-build` directory that's independent of the
  /// user's build.
  private var isForIndexBuild: Bool { options.backgroundIndexingOrDefault }

  // MARK: Build system options (set once and not modified)

  /// The path at which the LSP workspace is opened. This might be a subdirectory of the path that contains the
  /// `Package.swift`.
  private let workspacePath: TSCAbsolutePath

  /// The directory containing `Package.swift`.
  package let projectRoot: TSCAbsolutePath

  package let toolsBuildParameters: BuildParameters
  package let destinationBuildParameters: BuildParameters

  private let fileSystem: FileSystem
  private let toolchain: Toolchain
  private let workspace: Workspace

  /// A `ObservabilitySystem` from `SwiftPM` that logs.
  private let observabilitySystem = ObservabilitySystem({ scope, diagnostic in
    logger.log(level: diagnostic.severity.asLogLevel, "SwiftPM log: \(diagnostic.description)")
  })

  // MARK: Build system state (modified on package reload)

  /// The entry point via with we can access the `SourceKitLSPAPI` provided by SwiftPM.
  private var buildDescription: SourceKitLSPAPI.BuildDescription?

  /// Maps source and header files to the target that include them.
  private var fileToTargets: [DocumentURI: Set<ConfiguredTarget>] = [:]

  /// Maps configured targets ids to their SwiftPM build target as well as the depth at which they occur in the build
  /// graph. Top level targets on which no other target depends have a depth of `1`. Targets with dependencies have a
  /// greater depth.
  private var targets: [ConfiguredTarget: (buildTarget: SwiftBuildTarget, depth: Int)] = [:]

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - workspace: The workspace root path.
  ///   - toolchainRegistry: The toolchain registry to use to provide the Swift compiler used for
  ///     manifest parsing and runtime support.
  ///   - reloadPackageStatusCallback: Will be informed when `reloadPackage` starts and ends executing.
  /// - Throws: If there is an error loading the package, or no manifest is found.
  package init(
    workspacePath: TSCAbsolutePath,
    toolchainRegistry: ToolchainRegistry,
    fileSystem: FileSystem = localFileSystem,
    options: SourceKitLSPOptions,
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) async -> Void = { _ in },
    testHooks: SwiftPMTestHooks
  ) async throws {
    self.workspacePath = workspacePath
    self.options = options
    self.fileSystem = fileSystem
    let toolchain = await toolchainRegistry.preferredToolchain(containing: [
      \.clang, \.clangd, \.sourcekitd, \.swift, \.swiftc,
    ])
    guard let toolchain else {
      throw Error.cannotDetermineHostToolchain
    }

    self.toolchain = toolchain
    self.testHooks = testHooks

    guard let packageRoot = findPackageDirectory(containing: workspacePath, fileSystem) else {
      throw Error.noManifest(workspacePath: workspacePath)
    }

    self.projectRoot = try resolveSymlinks(packageRoot)

    guard let destinationToolchainBinDir = toolchain.swiftc?.parentDirectory else {
      throw Error.cannotDetermineHostToolchain
    }

    let hostSDK = try SwiftSDK.hostSwiftSDK(AbsolutePath(destinationToolchainBinDir))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    let destinationSDK = try SwiftSDK.deriveTargetSwiftSDK(
      hostSwiftSDK: hostSDK,
      hostTriple: hostSwiftPMToolchain.targetTriple,
      customCompileTriple: options.swiftPM.triple.map { try Triple($0) },
      swiftSDKSelector: options.swiftPM.swiftSDK,
      store: SwiftSDKBundleStore(
        swiftSDKsDirectory: fileSystem.getSharedSwiftSDKsDirectory(
          explicitDirectory: options.swiftPM.swiftSDKsDirectory.map { try AbsolutePath(validating: $0) }
        ),
        fileSystem: fileSystem,
        observabilityScope: observabilitySystem.topScope,
        outputHandler: { _ in }
      ),
      observabilityScope: observabilitySystem.topScope,
      fileSystem: fileSystem
    )

    let destinationSwiftPMToolchain = try UserToolchain(swiftSDK: destinationSDK)

    var location = try Workspace.Location(
      forRootPackage: AbsolutePath(packageRoot),
      fileSystem: fileSystem
    )
    if options.backgroundIndexingOrDefault {
      location.scratchDirectory = AbsolutePath(packageRoot.appending(component: ".index-build"))
    } else if let scratchDirectory = options.swiftPM.scratchPath,
      let scratchDirectoryPath = try? AbsolutePath(validating: scratchDirectory)
    {
      location.scratchDirectory = scratchDirectoryPath
    }

    var configuration = WorkspaceConfiguration.default
    configuration.skipDependenciesUpdates = true

    self.workspace = try Workspace(
      fileSystem: fileSystem,
      location: location,
      configuration: configuration,
      customHostToolchain: hostSwiftPMToolchain,
      customManifestLoader: ManifestLoader(
        toolchain: hostSwiftPMToolchain,
        isManifestSandboxEnabled: !(options.swiftPM.disableSandbox ?? false),
        cacheDir: location.sharedManifestsCacheDirectory,
        importRestrictions: configuration.manifestImportRestrictions
      )
    )

    let buildConfiguration: PackageModel.BuildConfiguration
    switch options.swiftPM.configuration {
    case .debug, nil:
      buildConfiguration = .debug
    case .release:
      buildConfiguration = .release
    }

    let buildFlags = BuildFlags(
      cCompilerFlags: options.swiftPM.cCompilerFlags ?? [],
      cxxCompilerFlags: options.swiftPM.cxxCompilerFlags ?? [],
      swiftCompilerFlags: options.swiftPM.swiftCompilerFlags ?? [],
      linkerFlags: options.swiftPM.linkerFlags ?? []
    )

    self.toolsBuildParameters = try BuildParameters(
      destination: .host,
      dataPath: location.scratchDirectory.appending(
        component: hostSwiftPMToolchain.targetTriple.platformBuildPathComponent
      ),
      configuration: buildConfiguration,
      toolchain: hostSwiftPMToolchain,
      flags: buildFlags
    )

    self.destinationBuildParameters = try BuildParameters(
      destination: .target,
      dataPath: location.scratchDirectory.appending(
        component: destinationSwiftPMToolchain.targetTriple.platformBuildPathComponent
      ),
      configuration: buildConfiguration,
      toolchain: destinationSwiftPMToolchain,
      triple: destinationSDK.targetTriple,
      flags: buildFlags
    )

    self.reloadPackageStatusCallback = reloadPackageStatusCallback

    // The debounce duration of 500ms was chosen arbitrarily without scientific research.
    self.fileDependenciesUpdatedDebouncer = Debouncer(
      debounceDuration: .milliseconds(500),
      combineResults: { $0.union($1) }
    ) {
      [weak self] (filesWithUpdatedDependencies) in
      guard let delegate = await self?.delegate else {
        logger.fault("Not calling filesDependenciesUpdated because no delegate exists in SwiftPMBuildSystem")
        return
      }
      await delegate.filesDependenciesUpdated(filesWithUpdatedDependencies)
    }
  }

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - reloadPackageStatusCallback: Will be informed when `reloadPackage` starts and ends executing.
  /// - Returns: nil if `workspacePath` is not part of a package or there is an error.
  package init?(
    uri: DocumentURI,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) async -> Void,
    testHooks: SwiftPMTestHooks
  ) async {
    guard let fileURL = uri.fileURL else {
      return nil
    }
    do {
      try await self.init(
        workspacePath: try TSCAbsolutePath(validating: fileURL.path),
        toolchainRegistry: toolchainRegistry,
        fileSystem: localFileSystem,
        options: options,
        reloadPackageStatusCallback: reloadPackageStatusCallback,
        testHooks: testHooks
      )
    } catch Error.noManifest {
      return nil
    } catch {
      logger.error("Failed to create SwiftPMWorkspace at \(uri.forLogging): \(error.forLogging)")
      return nil
    }
  }
}

extension SwiftPMBuildSystem {
  /// (Re-)load the package settings by parsing the manifest and resolving all the targets and
  /// dependencies.
  package func reloadPackage(forceResolvedVersions: Bool) async throws {
    await reloadPackageStatusCallback(.start)
    await testHooks.reloadPackageDidStart?()
    defer {
      Task {
        await testHooks.reloadPackageDidFinish?()
        await reloadPackageStatusCallback(.end)
      }
    }

    let modulesGraph = try await self.workspace.loadPackageGraph(
      rootInput: PackageGraphRootInput(packages: [AbsolutePath(projectRoot)]),
      forceResolvedVersions: forceResolvedVersions,
      observabilityScope: observabilitySystem.topScope
    )

    let plan = try await BuildPlan(
      destinationBuildParameters: destinationBuildParameters,
      toolsBuildParameters: toolsBuildParameters,
      graph: modulesGraph,
      disableSandbox: options.swiftPM.disableSandbox ?? false,
      fileSystem: fileSystem,
      observabilityScope: observabilitySystem.topScope
    )
    let buildDescription = BuildDescription(buildPlan: plan)
    self.buildDescription = buildDescription

    /// Make sure to execute any throwing statements before setting any
    /// properties because otherwise we might end up in an inconsistent state
    /// with only some properties modified.

    self.targets = [:]
    self.fileToTargets = [:]
    buildDescription.traverseModules { buildTarget, parent, depth in
      let configuredTarget = ConfiguredTarget(buildTarget)
      var depth = depth
      if let existingDepth = targets[configuredTarget]?.depth {
        depth = max(existingDepth, depth)
      } else {
        for source in buildTarget.sources + buildTarget.headers {
          fileToTargets[DocumentURI(source), default: []].insert(configuredTarget)
        }
      }
      targets[configuredTarget] = (buildTarget, depth)
    }

    if let delegate = self.delegate {
      await delegate.fileBuildSettingsChanged(self.watchedFiles)
      await delegate.fileHandlingCapabilityChanged()
    }
    for testFilesDidChangeCallback in testFilesDidChangeCallbacks {
      await testFilesDidChangeCallback()
    }
  }
}

fileprivate struct NonFileURIError: Error, CustomStringConvertible {
  let uri: DocumentURI
  var description: String {
    "Trying to get build settings for non-file URI: \(uri)"
  }
}

extension SwiftPMBuildSystem: BuildSystemIntegration.BuildSystem {
  package nonisolated var supportsPreparation: Bool { true }

  package var buildPath: TSCAbsolutePath {
    return TSCAbsolutePath(destinationBuildParameters.buildPath)
  }

  package var indexStorePath: TSCAbsolutePath? {
    return destinationBuildParameters.indexStoreMode == .off
      ? nil : TSCAbsolutePath(destinationBuildParameters.indexStore)
  }

  package var indexDatabasePath: TSCAbsolutePath? {
    return buildPath.appending(components: "index", "db")
  }

  /// Return the compiler arguments for the given source file within a target, making any necessary adjustments to
  /// account for differences in the SwiftPM versions being linked into SwiftPM and being installed in the toolchain.
  private func compilerArguments(for file: DocumentURI, in buildTarget: any SwiftBuildTarget) async throws -> [String] {
    guard let fileURL = file.fileURL else {
      throw NonFileURIError(uri: file)
    }
    let compileArguments = try buildTarget.compileArguments(for: fileURL)

    #if compiler(>=6.1)
    #warning("When we drop support for Swift 5.10 we no longer need to adjust compiler arguments for the Modules move")
    #endif
    // Fix up compiler arguments that point to a `/Modules` subdirectory if the Swift version in the toolchain is less
    // than 6.0 because it places the modules one level higher up.
    let toolchainVersion = await orLog("Getting Swift version") { try await toolchain.swiftVersion }
    guard let toolchainVersion, toolchainVersion < SwiftVersion(6, 0) else {
      return compileArguments
    }
    return compileArguments.map { argument in
      if argument.hasSuffix("/Modules"), argument.contains(self.workspace.location.scratchDirectory.pathString) {
        return String(argument.dropLast(8))
      }
      return argument
    }
  }

  package func buildSettings(
    for uri: DocumentURI,
    in configuredTarget: ConfiguredTarget,
    language: Language
  ) async throws -> FileBuildSettings? {
    guard let url = uri.fileURL, let path = try? AbsolutePath(validating: url.path) else {
      // We can't determine build settings for non-file URIs.
      return nil
    }

    if configuredTarget == .forPackageManifest {
      return try settings(forPackageManifest: path)
    }

    guard let buildTarget = self.targets[configuredTarget]?.buildTarget else {
      logger.fault("Did not find target with name \(configuredTarget.targetID)")
      return nil
    }

    if !buildTarget.sources.lazy.map(DocumentURI.init).contains(uri),
      let substituteFile = buildTarget.sources.sorted(by: { $0.path < $1.path }).first
    {
      logger.info("Getting compiler arguments for \(url) using substitute file \(substituteFile)")
      // If `url` is not part of the target's source, it's most likely a header file. Fake compiler arguments for it
      // from a substitute file within the target.
      // Even if the file is not a header, this should give reasonable results: Say, there was a new `.cpp` file in a
      // target and for some reason the `SwiftPMBuildSystem` doesn’t know about it. Then we would infer the target based
      // on the file's location on disk and generate compiler arguments for it by picking a source file in that target,
      // getting its compiler arguments and then patching up the compiler arguments by replacing the substitute file
      // with the `.cpp` file.
      return FileBuildSettings(
        compilerArguments: try await compilerArguments(for: DocumentURI(substituteFile), in: buildTarget),
        workingDirectory: workspacePath.pathString
      ).patching(newFile: try resolveSymlinks(path).pathString, originalFile: substituteFile.absoluteString)
    }

    return FileBuildSettings(
      compilerArguments: try await compilerArguments(for: uri, in: buildTarget),
      workingDirectory: workspacePath.pathString
    )
  }

  package func defaultLanguage(for document: DocumentURI) -> Language? {
    // TODO: Query The SwiftPM build system for the document's language. (https://github.com/swiftlang/sourcekit-lsp/issues/1267)
    return nil
  }

  package func toolchain(for uri: DocumentURI, _ language: Language) async -> Toolchain? {
    return toolchain
  }

  package func configuredTargets(for uri: DocumentURI) -> [ConfiguredTarget] {
    guard let url = uri.fileURL, let path = try? AbsolutePath(validating: url.path) else {
      // We can't determine targets for non-file URIs.
      return []
    }

    let targets = buildTargets(for: uri)
    if !targets.isEmpty {
      return targets.sorted { ($0.targetID, $0.runDestinationID) < ($1.targetID, $1.runDestinationID) }
    }

    if path.basename == "Package.swift"
      && projectRoot == (try? TSCBasic.resolveSymlinks(TSCBasic.AbsolutePath(path.parentDirectory)))
    {
      // We use an empty target name to represent the package manifest since an empty target name is not valid for any
      // user-defined target.
      return [ConfiguredTarget.forPackageManifest]
    }

    return []
  }

  package func generateBuildGraph(allowFileSystemWrites: Bool) async throws {
    try await self.reloadPackage(forceResolvedVersions: !isForIndexBuild || !allowFileSystemWrites)
  }

  package func topologicalSort(of targets: [ConfiguredTarget]) -> [ConfiguredTarget]? {
    return targets.sorted { (lhs: ConfiguredTarget, rhs: ConfiguredTarget) -> Bool in
      let lhsDepth = self.targets[lhs]?.depth ?? 0
      let rhsDepth = self.targets[rhs]?.depth ?? 0
      return lhsDepth > rhsDepth
    }
  }

  package func targets(dependingOn targets: [ConfiguredTarget]) -> [ConfiguredTarget]? {
    let targetDepths = targets.compactMap { self.targets[$0]?.depth }
    let minimumTargetDepth: Int?
    if targetDepths.count == targets.count {
      minimumTargetDepth = targetDepths.max()
    } else {
      // One of the targets didn't have an entry in self.targets. We don't know what might depend on it.
      minimumTargetDepth = nil
    }

    // Files that occur before the target in the topological sorting don't depend on it.
    // Ideally, we should consult the dependency graph here for more accurate dependency analysis instead of relying on
    // a flattened list (https://github.com/swiftlang/sourcekit-lsp/issues/1312).
    return self.targets.compactMap { (configuredTarget, value) -> ConfiguredTarget? in
      if let minimumTargetDepth, value.depth >= minimumTargetDepth {
        return nil
      }
      return configuredTarget
    }
  }

  package func prepare(
    targets: [ConfiguredTarget],
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void
  ) async throws {
    // TODO: Support preparation of multiple targets at once. (https://github.com/swiftlang/sourcekit-lsp/issues/1262)
    for target in targets {
      await orLog("Preparing") { try await prepare(singleTarget: target, logMessageToIndexLog: logMessageToIndexLog) }
    }
    let filesInPreparedTargets = targets.flatMap { self.targets[$0]?.buildTarget.sources ?? [] }
    await fileDependenciesUpdatedDebouncer.scheduleCall(Set(filesInPreparedTargets.map(DocumentURI.init)))
  }

  private func prepare(
    singleTarget target: ConfiguredTarget,
    logMessageToIndexLog: @escaping @Sendable (_ taskID: IndexTaskID, _ message: String) -> Void
  ) async throws {
    if target == .forPackageManifest {
      // Nothing to prepare for package manifests.
      return
    }

    // TODO: Add a proper 'prepare' job in SwiftPM instead of building the target. (https://github.com/swiftlang/sourcekit-lsp/issues/1254)
    guard let swift = toolchain.swift else {
      logger.error(
        "Not preparing because toolchain at \(self.toolchain.identifier) does not contain a Swift compiler"
      )
      return
    }
    logger.debug("Preparing '\(target.targetID)' using \(self.toolchain.identifier)")
    var arguments = [
      swift.pathString, "build",
      "--package-path", workspacePath.pathString,
      "--scratch-path", self.workspace.location.scratchDirectory.pathString,
      "--disable-index-store",
      "--target", target.targetID,
    ]
    if options.swiftPM.disableSandbox ?? false {
      arguments += ["--disable-sandbox"]
    }
    if let configuration = options.swiftPM.configuration {
      arguments += ["-c", configuration.rawValue]
    }
    arguments += options.swiftPM.cCompilerFlags?.flatMap { ["-Xcc", $0] } ?? []
    arguments += options.swiftPM.cxxCompilerFlags?.flatMap { ["-Xcxx", $0] } ?? []
    arguments += options.swiftPM.swiftCompilerFlags?.flatMap { ["-Xswiftc", $0] } ?? []
    arguments += options.swiftPM.linkerFlags?.flatMap { ["-Xlinker", $0] } ?? []
    switch options.backgroundPreparationModeOrDefault {
    case .build: break
    case .noLazy: arguments += ["--experimental-prepare-for-indexing", "--experimental-prepare-for-indexing-no-lazy"]
    case .enabled: arguments.append("--experimental-prepare-for-indexing")
    }
    if Task.isCancelled {
      return
    }
    let start = ContinuousClock.now

    let logID = IndexTaskID.preparation(id: preparationTaskID.fetchAndIncrement())
    logMessageToIndexLog(
      logID,
      """
      Preparing \(target.targetID) for \(target.runDestinationID)
      \(arguments.joined(separator: " "))
      """
    )
    let stdoutHandler = PipeAsStringHandler { logMessageToIndexLog(logID, $0) }
    let stderrHandler = PipeAsStringHandler { logMessageToIndexLog(logID, $0) }

    let result = try await Process.run(
      arguments: arguments,
      workingDirectory: nil,
      outputRedirection: .stream(
        stdout: { stdoutHandler.handleDataFromPipe(Data($0)) },
        stderr: { stderrHandler.handleDataFromPipe(Data($0)) }
      )
    )
    let exitStatus = result.exitStatus.exhaustivelySwitchable
    logMessageToIndexLog(logID, "Finished with \(exitStatus.description) in \(start.duration(to: .now))")
    switch exitStatus {
    case .terminated(code: 0):
      break
    case .terminated(code: let code):
      // This most likely happens if there are compilation errors in the source file. This is nothing to worry about.
      let stdout = (try? String(bytes: result.output.get(), encoding: .utf8)) ?? "<no stderr>"
      let stderr = (try? String(bytes: result.stderrOutput.get(), encoding: .utf8)) ?? "<no stderr>"
      logger.debug(
        """
        Preparation of target \(target.targetID) terminated with non-zero exit code \(code)
        Stderr:
        \(stderr)
        Stdout:
        \(stdout)
        """
      )
    case .signalled(signal: let signal):
      if !Task.isCancelled {
        // The indexing job finished with a signal. Could be because the compiler crashed.
        // Ignore signal exit codes if this task has been cancelled because the compiler exits with SIGINT if it gets
        // interrupted.
        logger.error("Preparation of target \(target.targetID) signaled \(signal)")
      }
    case .abnormal(exception: let exception):
      if !Task.isCancelled {
        logger.error("Preparation of target \(target.targetID) exited abnormally \(exception)")
      }
    }
  }

  package func registerForChangeNotifications(for uri: DocumentURI) async {
    self.watchedFiles.insert(uri)
  }

  /// Unregister the given file for build-system level change notifications, such as command
  /// line flag changes, dependency changes, etc.
  package func unregisterForChangeNotifications(for uri: DocumentURI) {
    self.watchedFiles.remove(uri)
  }

  /// Returns the resolved target descriptions for the given file, if one is known.
  private func buildTargets(for file: DocumentURI) -> Set<ConfiguredTarget> {
    if let targets = fileToTargets[file] {
      return targets
    }

    if let fileURL = file.fileURL,
      let realpath = try? resolveSymlinks(AbsolutePath(validating: fileURL.path)),
      let targets = fileToTargets[DocumentURI(realpath.asURL)]
    {
      fileToTargets[file] = targets
      return targets
    }

    return []
  }

  /// An event is relevant if it modifies a file that matches one of the file rules used by the SwiftPM workspace.
  private func fileEventShouldTriggerPackageReload(event: FileEvent) -> Bool {
    guard let fileURL = event.uri.fileURL else {
      return false
    }
    switch event.type {
    case .created, .deleted:
      guard let buildDescription else {
        return false
      }

      return buildDescription.fileAffectsSwiftOrClangBuildSettings(fileURL)
    case .changed:
      return fileURL.lastPathComponent == "Package.swift" || fileURL.lastPathComponent == "Package.resolved"
    default:  // Unknown file change type
      return false
    }
  }

  package func filesDidChange(_ events: [FileEvent]) async {
    if events.contains(where: { self.fileEventShouldTriggerPackageReload(event: $0) }) {
      logger.log("Reloading package because of file change")
      await orLog("Reloading package") {
        try await self.reloadPackage(forceResolvedVersions: !isForIndexBuild)
      }
    }

    var filesWithUpdatedDependencies: Set<DocumentURI> = []
    // If a Swift file within a target is updated, reload all the other files within the target since they might be
    // referring to a function in the updated file.
    for event in events {
      guard event.uri.fileURL?.pathExtension == "swift", let targets = fileToTargets[event.uri] else {
        continue
      }
      for target in targets {
        filesWithUpdatedDependencies.formUnion(self.targets[target]?.buildTarget.sources.map(DocumentURI.init) ?? [])
      }
    }

    // If a `.swiftmodule` file is updated, this means that we have performed a build / are
    // performing a build and files that depend on this module have updated dependencies.
    // We don't have access to the build graph from the SwiftPM API offered to SourceKit-LSP to figure out which files
    // depend on the updated module, so assume that all files have updated dependencies.
    // The file watching here is somewhat fragile as well because it assumes that the `.swiftmodule` files are being
    // written to a directory within the workspace root. This is not necessarily true if the user specifies a build
    // directory outside the source tree.
    // If we have background indexing enabled, this is not necessary because we call `fileDependenciesUpdated` when
    // preparation of a target finishes.
    if !isForIndexBuild, events.contains(where: { $0.uri.fileURL?.pathExtension == "swiftmodule" }) {
      filesWithUpdatedDependencies.formUnion(self.fileToTargets.keys)
    }
    await self.fileDependenciesUpdatedDebouncer.scheduleCall(filesWithUpdatedDependencies)
  }

  package func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability {
    if configuredTargets(for: uri).isEmpty {
      return .unhandled
    }
    return .handled
  }

  package func sourceFiles() -> [SourceFileInfo] {
    var sourceFiles: [DocumentURI: SourceFileInfo] = [:]
    for (buildTarget, depth) in self.targets.values {
      for sourceFile in buildTarget.sources {
        let uri = DocumentURI(sourceFile)
        sourceFiles[uri] = SourceFileInfo(
          uri: uri,
          isPartOfRootProject: depth == 1 || (sourceFiles[uri]?.isPartOfRootProject ?? false),
          mayContainTests: true
        )
      }
    }
    return sourceFiles.values.sorted { $0.uri.pseudoPath < $1.uri.pseudoPath }
  }

  package func addSourceFilesDidChangeCallback(_ callback: @Sendable @escaping () async -> Void) async {
    testFilesDidChangeCallbacks.append(callback)
  }

  /// Retrieve settings for a package manifest (Package.swift).
  private func settings(forPackageManifest path: AbsolutePath) throws -> FileBuildSettings? {
    let compilerArgs = workspace.interpreterFlags(for: path.parentDirectory) + [path.pathString]
    return FileBuildSettings(compilerArguments: compilerArgs)
  }
}

/// Find a Swift Package root directory that contains the given path, if any.
private func findPackageDirectory(
  containing path: TSCAbsolutePath,
  _ fileSystem: FileSystem
) -> TSCAbsolutePath? {
  var path = path
  while true {
    let packagePath = path.appending(component: "Package.swift")
    if fileSystem.isFile(packagePath) {
      let contents = try? fileSystem.readFileContents(packagePath)
      if contents?.cString.contains("PackageDescription") == true {
        return path
      }
    }

    if path.isRoot {
      return nil
    }
    path = path.parentDirectory
  }
  return path
}

extension Basics.Diagnostic.Severity {
  var asLogLevel: LogLevel {
    switch self {
    case .error, .warning: return .default
    case .info: return .info
    case .debug: return .debug
    }
  }
}
