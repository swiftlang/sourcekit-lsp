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
  /// A string that can be used to identify the build triple in a `BuildTargetIdentifier`.
  ///
  /// `BuildSystemManager.canonicalBuildTargetIdentifier` picks the canonical target based on alphabetical
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

extension BuildTargetIdentifier {
  fileprivate init(_ buildTarget: any SwiftBuildTarget) throws {
    try self.init(target: buildTarget.name, destination: buildTarget.destination)
  }

  /// - Important: *For testing only*
  package init(target: String, destination: BuildDestination) throws {
    var components = URLComponents()
    components.scheme = "swiftpm"
    components.host = "target"
    components.queryItems = [
      URLQueryItem(name: "target", value: target),
      URLQueryItem(name: "destination", value: destination.id),
    ]

    struct FailedToConvertSwiftBuildTargetToUrlError: Swift.Error, CustomStringConvertible {
      var target: String
      var destination: String

      var description: String {
        return "Failed to generate URL for target: \(target), destination: \(destination)"
      }
    }

    guard let url = components.url else {
      throw FailedToConvertSwiftBuildTargetToUrlError(target: target, destination: destination.id)
    }

    self.init(uri: URI(url))
  }

  fileprivate static let forPackageManifest = BuildTargetIdentifier(uri: try! URI(string: "swiftpm://package-manifest"))

  fileprivate var targetProperties: (target: String, runDestination: String) {
    get throws {
      struct InvalidTargetIdentifierError: Swift.Error, CustomStringConvertible {
        var target: BuildTargetIdentifier

        var description: String {
          return "Invalid target identifier \(target)"
        }
      }
      guard let components = URLComponents(url: self.uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
        throw InvalidTargetIdentifierError(target: self)
      }
      let target = components.queryItems?.last(where: { $0.name == "target" })?.value
      let runDestination = components.queryItems?.last(where: { $0.name == "destination" })?.value

      guard let target, let runDestination else {
        throw InvalidTargetIdentifierError(target: self)
      }

      return (target, runDestination)
    }
  }

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

  /// The queue on which we reload the package to ensure we don't reload it multiple times concurrently, which can cause
  /// issues in SwiftPM.
  private let packageLoadingQueue = AsyncQueue<Serial>()

  package weak var messageHandler: BuiltInBuildSystemMessageHandler?

  /// This callback is informed when `reloadPackage` starts and ends executing.
  private var reloadPackageStatusCallback: (ReloadPackageStatus) async -> Void

  /// Callbacks that should be called if the list of possible test files has changed.
  private var testFilesDidChangeCallbacks: [() async -> Void] = []

  /// Whether the `SwiftPMBuildSystem` is pointed at a `.index-build` directory that's independent of the
  /// user's build.
  private var isForIndexBuild: Bool { options.backgroundIndexingOrDefault }

  // MARK: Build system options (set once and not modified)

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
  private var fileToTargets: [DocumentURI: Set<BuildTargetIdentifier>] = [:]

  /// Maps target ids to their SwiftPM build target as well as the depth at which they occur in the build
  /// graph. Top level targets on which no other target depends have a depth of `1`. Targets with dependencies have a
  /// greater depth.
  private var targets: [BuildTargetIdentifier: (buildTarget: SwiftBuildTarget, depth: Int)] = [:]

  static package func projectRoot(
    for path: TSCBasic.AbsolutePath,
    options: SourceKitLSPOptions
  ) -> TSCBasic.AbsolutePath? {
    guard var path = try? resolveSymlinks(path) else {
      return nil
    }
    while true {
      let packagePath = path.appending(component: "Package.swift")
      if localFileSystem.isFile(packagePath) {
        let contents = try? localFileSystem.readFileContents(packagePath)
        if contents?.cString.contains("PackageDescription") == true {
          return path
        }
      }

      if path.isRoot {
        return nil
      }
      path = path.parentDirectory
    }
    return nil
  }

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - projectRoot: The directory containing `Package.swift`
  ///   - toolchainRegistry: The toolchain registry to use to provide the Swift compiler used for
  ///     manifest parsing and runtime support.
  ///   - reloadPackageStatusCallback: Will be informed when `reloadPackage` starts and ends executing.
  /// - Throws: If there is an error loading the package, or no manifest is found.
  package init(
    projectRoot: TSCAbsolutePath,
    toolchainRegistry: ToolchainRegistry,
    fileSystem: FileSystem = localFileSystem,
    options: SourceKitLSPOptions,
    messageHandler: (any BuiltInBuildSystemMessageHandler)?,
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) async -> Void = { _ in },
    testHooks: SwiftPMTestHooks
  ) async throws {
    self.projectRoot = projectRoot
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
    self.messageHandler = messageHandler

    guard let destinationToolchainBinDir = toolchain.swiftc?.parentDirectory else {
      throw Error.cannotDetermineHostToolchain
    }

    let hostSDK = try SwiftSDK.hostSwiftSDK(AbsolutePath(destinationToolchainBinDir))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    let destinationSDK = try SwiftSDK.deriveTargetSwiftSDK(
      hostSwiftSDK: hostSDK,
      hostTriple: hostSwiftPMToolchain.targetTriple,
      customCompileTriple: options.swiftPMOrDefault.triple.map { try Triple($0) },
      swiftSDKSelector: options.swiftPMOrDefault.swiftSDK,
      store: SwiftSDKBundleStore(
        swiftSDKsDirectory: fileSystem.getSharedSwiftSDKsDirectory(
          explicitDirectory: options.swiftPMOrDefault.swiftSDKsDirectory.map { try AbsolutePath(validating: $0) }
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
      forRootPackage: AbsolutePath(projectRoot),
      fileSystem: fileSystem
    )
    if options.backgroundIndexingOrDefault {
      location.scratchDirectory = AbsolutePath(projectRoot.appending(component: ".index-build"))
    } else if let scratchDirectory = options.swiftPMOrDefault.scratchPath,
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
        isManifestSandboxEnabled: !(options.swiftPMOrDefault.disableSandbox ?? false),
        cacheDir: location.sharedManifestsCacheDirectory,
        importRestrictions: configuration.manifestImportRestrictions
      )
    )

    let buildConfiguration: PackageModel.BuildConfiguration
    switch options.swiftPMOrDefault.configuration {
    case .debug, nil:
      buildConfiguration = .debug
    case .release:
      buildConfiguration = .release
    }

    let buildFlags = BuildFlags(
      cCompilerFlags: options.swiftPMOrDefault.cCompilerFlags ?? [],
      cxxCompilerFlags: options.swiftPMOrDefault.cxxCompilerFlags ?? [],
      swiftCompilerFlags: options.swiftPMOrDefault.swiftCompilerFlags ?? [],
      linkerFlags: options.swiftPMOrDefault.linkerFlags ?? []
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
  }

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - reloadPackageStatusCallback: Will be informed when `reloadPackage` starts and ends executing.
  /// - Returns: nil if `workspacePath` is not part of a package or there is an error.
  package init?(
    projectRoot: TSCBasic.AbsolutePath,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    messageHandler: any BuiltInBuildSystemMessageHandler,
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) async -> Void,
    testHooks: SwiftPMTestHooks
  ) async {
    do {
      try await self.init(
        projectRoot: projectRoot,
        toolchainRegistry: toolchainRegistry,
        fileSystem: localFileSystem,
        options: options,
        messageHandler: messageHandler,
        reloadPackageStatusCallback: reloadPackageStatusCallback,
        testHooks: testHooks
      )
    } catch Error.noManifest {
      return nil
    } catch {
      logger.error("Failed to create SwiftPMWorkspace at \(projectRoot.pathString): \(error.forLogging)")
      return nil
    }
  }
}

extension SwiftPMBuildSystem {
  /// (Re-)load the package settings by parsing the manifest and resolving all the targets and
  /// dependencies.
  @discardableResult
  package func schedulePackageReload() -> Task<Void, Swift.Error> {
    return packageLoadingQueue.asyncThrowing {
      try await self.reloadPackageImpl()
    }
  }

  /// - Important: Must only be called on `packageLoadingQueue`.
  private func reloadPackageImpl() async throws {
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
      forceResolvedVersions: !isForIndexBuild,
      observabilityScope: observabilitySystem.topScope
    )

    let plan = try await BuildPlan(
      destinationBuildParameters: destinationBuildParameters,
      toolsBuildParameters: toolsBuildParameters,
      graph: modulesGraph,
      disableSandbox: options.swiftPMOrDefault.disableSandbox ?? false,
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
      let targetIdentifier = orLog("Getting build target identifier") { try BuildTargetIdentifier(buildTarget) }
      guard let targetIdentifier else {
        return
      }
      var depth = depth
      if let existingDepth = targets[targetIdentifier]?.depth {
        depth = max(existingDepth, depth)
      } else {
        for source in buildTarget.sources + buildTarget.headers {
          fileToTargets[DocumentURI(source), default: []].insert(targetIdentifier)
        }
      }
      targets[targetIdentifier] = (buildTarget, depth)
    }

    await messageHandler?.sendNotificationToSourceKitLSP(DidChangeBuildTargetNotification(changes: nil))
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

extension SwiftPMBuildSystem: BuildSystemIntegration.BuiltInBuildSystem {
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

  package func buildTargets(request: BuildTargetsRequest) async throws -> BuildTargetsResponse {
    let targets = self.targets.map { (targetId, target) in
      var tags: [BuildTargetTag] = [.test]
      if target.depth != 1 {
        tags.append(.dependency)
      }
      return BuildTarget(
        id: targetId,
        displayName: nil,
        baseDirectory: nil,
        tags: tags,
        capabilities: BuildTargetCapabilities(),
        // Be conservative with the languages that might be used in the target. SourceKit-LSP doesn't use this property.
        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
        // FIXME: (BSP migration) List the target's dependencies
        dependencies: []
      )
    }
    return BuildTargetsResponse(targets: targets)
  }

  package func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    var result: [SourcesItem] = []
    // TODO: Query The SwiftPM build system for the document's language and add it to SourceItem.data
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1267)
    for target in request.targets {
      guard let swiftPMTarget = self.targets[target] else {
        continue
      }
      let sources = swiftPMTarget.buildTarget.sources.map {
        SourceItem(uri: DocumentURI($0), kind: .file, generated: false)
      }
      result.append(SourcesItem(target: target, sources: sources))
    }
    return BuildTargetSourcesResponse(items: result)
  }

  package func sourceKitOptions(request: SourceKitOptionsRequest) async throws -> SourceKitOptionsResponse? {
    guard let url = request.textDocument.uri.fileURL, let path = try? AbsolutePath(validating: url.path) else {
      // We can't determine build settings for non-file URIs.
      return nil
    }

    if request.target == .forPackageManifest {
      return try settings(forPackageManifest: path)
    }

    guard let buildTarget = self.targets[request.target]?.buildTarget else {
      logger.fault("Did not find target \(request.target.forLogging)")
      return nil
    }

    if !buildTarget.sources.lazy.map(DocumentURI.init).contains(request.textDocument.uri),
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
      let buildSettings = FileBuildSettings(
        compilerArguments: try await compilerArguments(for: DocumentURI(substituteFile), in: buildTarget),
        workingDirectory: projectRoot.pathString
      ).patching(newFile: try resolveSymlinks(path).pathString, originalFile: substituteFile.absoluteString)
      return SourceKitOptionsResponse(
        compilerArguments: buildSettings.compilerArguments,
        workingDirectory: buildSettings.workingDirectory
      )
    }

    return SourceKitOptionsResponse(
      compilerArguments: try await compilerArguments(for: request.textDocument.uri, in: buildTarget),
      workingDirectory: projectRoot.pathString
    )
  }

  package func toolchain(for uri: DocumentURI, _ language: Language) async -> Toolchain? {
    return toolchain
  }

  package func targets(for uri: DocumentURI) -> [BuildTargetIdentifier] {
    guard let url = uri.fileURL, let path = try? AbsolutePath(validating: url.path) else {
      // We can't determine targets for non-file URIs.
      return []
    }

    let targets = buildTargets(for: uri)
    if !targets.isEmpty {
      // Sort targets to get deterministic ordering. The actual order does not matter.
      return targets.sorted { $0.uri.stringValue < $1.uri.stringValue }
    }

    if path.basename == "Package.swift"
      && projectRoot == (try? TSCBasic.resolveSymlinks(TSCBasic.AbsolutePath(path.parentDirectory)))
    {
      // We use an empty target name to represent the package manifest since an empty target name is not valid for any
      // user-defined target.
      return [BuildTargetIdentifier.forPackageManifest]
    }

    return []
  }

  package func inverseSources(request: InverseSourcesRequest) -> InverseSourcesResponse {
    return InverseSourcesResponse(targets: targets(for: request.textDocument.uri))
  }

  package func scheduleBuildGraphGeneration() async throws {
    self.schedulePackageReload()
  }

  package func waitForUpToDateBuildGraph() async {
    await self.packageLoadingQueue.async {}.valuePropagatingCancellation
  }

  package func topologicalSort(of targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
    return targets.sorted { (lhs: BuildTargetIdentifier, rhs: BuildTargetIdentifier) -> Bool in
      let lhsDepth = self.targets[lhs]?.depth ?? 0
      let rhsDepth = self.targets[rhs]?.depth ?? 0
      return lhsDepth > rhsDepth
    }
  }

  package func targets(dependingOn targets: [BuildTargetIdentifier]) -> [BuildTargetIdentifier]? {
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
    return self.targets.compactMap { (targets, value) -> BuildTargetIdentifier? in
      if let minimumTargetDepth, value.depth >= minimumTargetDepth {
        return nil
      }
      return targets
    }
  }

  package func prepare(request: PrepareTargetsRequest) async throws -> VoidResponse {
    // TODO: Support preparation of multiple targets at once. (https://github.com/swiftlang/sourcekit-lsp/issues/1262)
    for target in request.targets {
      await orLog("Preparing") { try await prepare(singleTarget: target) }
    }
    return VoidResponse()
  }

  private nonisolated func logMessageToIndexLog(_ taskID: IndexTaskID, _ message: String) {
    // FIXME: When `messageHandler` is a Connection, we don't need to go via Task anymore
    Task {
      await self.messageHandler?.sendNotificationToSourceKitLSP(
        BuildServerProtocol.LogMessageNotification(
          type: .info,
          task: TaskId(id: taskID.rawValue),
          message: message
        )
      )
    }
  }

  private func prepare(singleTarget target: BuildTargetIdentifier) async throws {
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
    logger.debug("Preparing '\(target.forLogging)' using \(self.toolchain.identifier)")
    var arguments = [
      swift.pathString, "build",
      "--package-path", projectRoot.pathString,
      "--scratch-path", self.workspace.location.scratchDirectory.pathString,
      "--disable-index-store",
      "--target", try target.targetProperties.target,
    ]
    if options.swiftPMOrDefault.disableSandbox ?? false {
      arguments += ["--disable-sandbox"]
    }
    if let configuration = options.swiftPMOrDefault.configuration {
      arguments += ["-c", configuration.rawValue]
    }
    arguments += options.swiftPMOrDefault.cCompilerFlags?.flatMap { ["-Xcc", $0] } ?? []
    arguments += options.swiftPMOrDefault.cxxCompilerFlags?.flatMap { ["-Xcxx", $0] } ?? []
    arguments += options.swiftPMOrDefault.swiftCompilerFlags?.flatMap { ["-Xswiftc", $0] } ?? []
    arguments += options.swiftPMOrDefault.linkerFlags?.flatMap { ["-Xlinker", $0] } ?? []
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
    // FIXME: (BSP Migration) log target name instead of target URI
    logMessageToIndexLog(
      logID,
      """
      Preparing \(target.uri.stringValue)
      \(arguments.joined(separator: " "))
      """
    )
    let stdoutHandler = PipeAsStringHandler { self.logMessageToIndexLog(logID, $0) }
    let stderrHandler = PipeAsStringHandler { self.logMessageToIndexLog(logID, $0) }

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
        Preparation of target \(target.forLogging) terminated with non-zero exit code \(code)
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
        logger.error("Preparation of target \(target.forLogging) signaled \(signal)")
      }
    case .abnormal(exception: let exception):
      if !Task.isCancelled {
        logger.error("Preparation of target \(target.forLogging) exited abnormally \(exception)")
      }
    }
  }

  /// Returns the resolved target descriptions for the given file, if one is known.
  private func buildTargets(for file: DocumentURI) -> Set<BuildTargetIdentifier> {
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

  package func didChangeWatchedFiles(notification: BuildServerProtocol.DidChangeWatchedFilesNotification) async {
    if notification.changes.contains(where: { self.fileEventShouldTriggerPackageReload(event: $0) }) {
      logger.log("Reloading package because of file change")
      await orLog("Reloading package") {
        try await self.schedulePackageReload().value
      }
    }
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
  private func settings(forPackageManifest path: AbsolutePath) throws -> SourceKitOptionsResponse? {
    let compilerArgs = workspace.interpreterFlags(for: path.parentDirectory) + [path.pathString]
    return SourceKitOptionsResponse(compilerArguments: compilerArgs)
  }
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
