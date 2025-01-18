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

#if canImport(PackageModel)
import Basics
@preconcurrency import Build
import Dispatch
import LanguageServerProtocolExtensions
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
import SKLogging
@preconcurrency package import SPMBuildCore
import SourceControl
import SwiftExtensions
import TSCExtensions
@preconcurrency import Workspace

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

#if compiler(>=6)
package import BuildServerProtocol
package import Foundation
package import LanguageServerProtocol
package import SKOptions
package import SourceKitLSPAPI
package import ToolchainRegistry
package import class ToolchainRegistry.Toolchain
#else
import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import SKOptions
import SourceKitLSPAPI
import ToolchainRegistry
import class ToolchainRegistry.Toolchain
#endif

fileprivate typealias AbsolutePath = Basics.AbsolutePath

/// A build target in SwiftPM
package typealias SwiftBuildTarget = SourceKitLSPAPI.BuildTarget

/// A build target in `BuildServerProtocol`
package typealias BuildServerTarget = BuildServerProtocol.BuildTarget

fileprivate extension Basics.Diagnostic.Severity {
  var asLogLevel: LogLevel {
    switch self {
    case .error, .warning: return .default
    case .info: return .info
    case .debug: return .debug
    }
  }
}

extension BuildDestinationIdentifier {
  init(_ destination: BuildDestination) {
    switch destination {
    case .target: self = .target
    case .host: self = .host
    }
  }
}

extension BuildTargetIdentifier {
  fileprivate init(_ buildTarget: any SwiftBuildTarget) throws {
    self = try Self.createSwiftPM(
      target: buildTarget.name,
      destination: BuildDestinationIdentifier(buildTarget.destination)
    )
  }
}

fileprivate extension TSCBasic.AbsolutePath {
  var asURI: DocumentURI {
    DocumentURI(self.asURL)
  }
}

fileprivate let preparationTaskID: AtomicUInt32 = AtomicUInt32(initialValue: 0)

/// Swift Package Manager build system and workspace support.
///
/// This class implements the `BuiltInBuildSystem` interface to provide the build settings for a Swift
/// Package Manager (SwiftPM) package. The settings are determined by loading the Package.swift
/// manifest using `libSwiftPM` and constructing a build plan using the default (debug) parameters.
package actor SwiftPMBuildSystem: BuiltInBuildSystem {
  package enum Error: Swift.Error {
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

  package let connectionToSourceKitLSP: any Connection

  /// Whether the `SwiftPMBuildSystem` is pointed at a `.build/index-build` directory that's independent of the
  /// user's build.
  private var isForIndexBuild: Bool { options.backgroundIndexingOrDefault }

  // MARK: Build system options (set once and not modified)

  /// The directory containing `Package.swift`.
  private let projectRoot: URL

  package let fileWatchers: [FileSystemWatcher]

  package let toolsBuildParameters: BuildParameters
  package let destinationBuildParameters: BuildParameters

  private let toolchain: Toolchain
  private let swiftPMWorkspace: Workspace

  /// A `ObservabilitySystem` from `SwiftPM` that logs.
  private let observabilitySystem: ObservabilitySystem

  // MARK: Build system state (modified on package reload)

  /// The entry point via with we can access the `SourceKitLSPAPI` provided by SwiftPM.
  private var buildDescription: SourceKitLSPAPI.BuildDescription?

  /// Maps target ids to their SwiftPM build target.
  private var swiftPMTargets: [BuildTargetIdentifier: SwiftBuildTarget] = [:]

  private var targetDependencies: [BuildTargetIdentifier: Set<BuildTargetIdentifier>] = [:]

  static package func searchForConfig(in path: URL, options: SourceKitLSPOptions) -> BuildSystemSpec? {

    let packagePath = path.appendingPathComponent("Package.swift")
    if (try? String(contentsOf: packagePath, encoding: .utf8))?.contains("PackageDescription") ?? false {
      return BuildSystemSpec(kind: .swiftPM, projectRoot: path, configPath: packagePath)
    }

    return nil
  }

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - projectRoot: The directory containing `Package.swift`
  ///   - toolchainRegistry: The toolchain registry to use to provide the Swift compiler used for
  ///     manifest parsing and runtime support.
  /// - Throws: If there is an error loading the package, or no manifest is found.
  package init(
    projectRoot: URL,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    connectionToSourceKitLSP: any Connection,
    testHooks: SwiftPMTestHooks
  ) async throws {
    self.projectRoot = projectRoot
    self.options = options
    self.fileWatchers =
      try ["Package.swift", "Package@swift*.swift", "Package.resolved"].map {
        FileSystemWatcher(globPattern: try projectRoot.appendingPathComponent($0).filePath, kind: [.change])
      }
      + FileRuleDescription.builtinRules.flatMap({ $0.fileTypes }).map { fileExtension in
        FileSystemWatcher(globPattern: "**/*.\(fileExtension)", kind: [.create, .change, .delete])
      }
    let toolchain = await toolchainRegistry.preferredToolchain(containing: [
      \.clang, \.clangd, \.sourcekitd, \.swift, \.swiftc,
    ])
    guard let toolchain else {
      throw Error.cannotDetermineHostToolchain
    }

    self.toolchain = toolchain
    self.testHooks = testHooks
    self.connectionToSourceKitLSP = connectionToSourceKitLSP

    self.observabilitySystem = ObservabilitySystem({ scope, diagnostic in
      connectionToSourceKitLSP.send(
        OnBuildLogMessageNotification(type: .info, task: TaskId(id: "swiftpm-log"), message: diagnostic.description)
      )
      logger.log(level: diagnostic.severity.asLogLevel, "SwiftPM log: \(diagnostic.description)")
    })

    guard let destinationToolchainBinDir = toolchain.swiftc?.deletingLastPathComponent() else {
      throw Error.cannotDetermineHostToolchain
    }

    let hostSDK = try SwiftSDK.hostSwiftSDK(AbsolutePath(validating: destinationToolchainBinDir.filePath))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    let destinationSDK = try SwiftSDK.deriveTargetSwiftSDK(
      hostSwiftSDK: hostSDK,
      hostTriple: hostSwiftPMToolchain.targetTriple,
      customCompileTriple: options.swiftPMOrDefault.triple.map { try Triple($0) },
      swiftSDKSelector: options.swiftPMOrDefault.swiftSDK,
      store: SwiftSDKBundleStore(
        swiftSDKsDirectory: localFileSystem.getSharedSwiftSDKsDirectory(
          explicitDirectory: options.swiftPMOrDefault.swiftSDKsDirectory.map { try AbsolutePath(validating: $0) }
        ),
        fileSystem: localFileSystem,
        observabilityScope: observabilitySystem.topScope.makeChildScope(description: "SwiftPM Bundle Store"),
        outputHandler: { _ in }
      ),
      observabilityScope: observabilitySystem.topScope.makeChildScope(description: "Derive Target Swift SDK"),
      fileSystem: localFileSystem
    )

    let destinationSwiftPMToolchain = try UserToolchain(swiftSDK: destinationSDK)

    var location = try Workspace.Location(
      forRootPackage: try AbsolutePath(validating: projectRoot.filePath),
      fileSystem: localFileSystem
    )
    if options.backgroundIndexingOrDefault {
      location.scratchDirectory = try AbsolutePath(
        validating: projectRoot.appendingPathComponent(".build").appendingPathComponent("index-build").filePath
      )
    } else if let scratchDirectory = options.swiftPMOrDefault.scratchPath,
      let scratchDirectoryPath = try? AbsolutePath(
        validating: scratchDirectory,
        relativeTo: AbsolutePath(validating: projectRoot.filePath)
      )
    {
      location.scratchDirectory = scratchDirectoryPath
    }

    var configuration = WorkspaceConfiguration.default
    configuration.skipDependenciesUpdates = !options.backgroundIndexingOrDefault

    self.swiftPMWorkspace = try Workspace(
      fileSystem: localFileSystem,
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

    packageLoadingQueue.async {
      await orLog("Initial package loading") {
        // Schedule an initial generation of the build graph. Once the build graph is loaded, the build system will send
        // call `fileHandlingCapabilityChanged`, which allows us to move documents to a workspace with this build
        // system.
        try await self.reloadPackageAssumingOnPackageLoadingQueue()
      }
    }
  }

  /// (Re-)load the package settings by parsing the manifest and resolving all the targets and
  /// dependencies.
  ///
  /// - Important: Must only be called on `packageLoadingQueue`.
  private func reloadPackageAssumingOnPackageLoadingQueue() async throws {
    self.connectionToSourceKitLSP.send(
      TaskStartNotification(
        taskId: TaskId(id: "package-reloading"),
        data: WorkDoneProgressTask(title: "SourceKit-LSP: Reloading Package").encodeToLSPAny()
      )
    )
    await testHooks.reloadPackageDidStart?()
    defer {
      Task {
        self.connectionToSourceKitLSP.send(
          TaskFinishNotification(taskId: TaskId(id: "package-reloading"), status: .ok)
        )
        await testHooks.reloadPackageDidFinish?()
      }
    }

    let modulesGraph = try await self.swiftPMWorkspace.loadPackageGraph(
      rootInput: PackageGraphRootInput(packages: [AbsolutePath(validating: projectRoot.filePath)]),
      forceResolvedVersions: !isForIndexBuild,
      observabilityScope: observabilitySystem.topScope.makeChildScope(description: "Load package graph")
    )

    let plan = try await BuildPlan(
      destinationBuildParameters: destinationBuildParameters,
      toolsBuildParameters: toolsBuildParameters,
      graph: modulesGraph,
      disableSandbox: options.swiftPMOrDefault.disableSandbox ?? false,
      fileSystem: localFileSystem,
      observabilityScope: observabilitySystem.topScope.makeChildScope(description: "Create SwiftPM build plan")
    )
    let buildDescription = BuildDescription(buildPlan: plan)
    self.buildDescription = buildDescription

    /// Make sure to execute any throwing statements before setting any
    /// properties because otherwise we might end up in an inconsistent state
    /// with only some properties modified.

    self.swiftPMTargets = [:]
    self.targetDependencies = [:]

    buildDescription.traverseModules { buildTarget, parent in
      let targetIdentifier = orLog("Getting build target identifier") { try BuildTargetIdentifier(buildTarget) }
      guard let targetIdentifier else {
        return
      }
      if let parent,
        let parentIdentifier = orLog("Getting parent build target identifier", { try BuildTargetIdentifier(parent) })
      {
        self.targetDependencies[parentIdentifier, default: []].insert(targetIdentifier)
      }
      swiftPMTargets[targetIdentifier] = buildTarget
    }

    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  package nonisolated var supportsPreparation: Bool { true }

  package var buildPath: URL {
    return destinationBuildParameters.buildPath.asURL
  }

  package var indexStorePath: URL? {
    if destinationBuildParameters.indexStoreMode == .off {
      return nil
    }
    return destinationBuildParameters.indexStore.asURL
  }

  package var indexDatabasePath: URL? {
    return buildPath.appendingPathComponent("index").appendingPathComponent("db")
  }

  /// Return the compiler arguments for the given source file within a target, making any necessary adjustments to
  /// account for differences in the SwiftPM versions being linked into SwiftPM and being installed in the toolchain.
  private func compilerArguments(for file: DocumentURI, in buildTarget: any SwiftBuildTarget) async throws -> [String] {
    guard let fileURL = file.fileURL else {
      struct NonFileURIError: Swift.Error, CustomStringConvertible {
        let uri: DocumentURI
        var description: String {
          "Trying to get build settings for non-file URI: \(uri)"
        }
      }

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
      if argument.hasSuffix("/Modules"), argument.contains(self.swiftPMWorkspace.location.scratchDirectory.pathString) {
        return String(argument.dropLast(8))
      }
      return argument
    }
  }

  package func buildTargets(request: WorkspaceBuildTargetsRequest) async throws -> WorkspaceBuildTargetsResponse {
    var targets = self.swiftPMTargets.map { (targetId, target) in
      var tags: [BuildTargetTag] = []
      if target.isTestTarget {
        tags.append(.test)
      }
      if !target.isPartOfRootPackage {
        tags.append(.dependency)
      }
      return BuildTarget(
        id: targetId,
        displayName: target.name,
        baseDirectory: nil,
        tags: tags,
        capabilities: BuildTargetCapabilities(),
        // Be conservative with the languages that might be used in the target. SourceKit-LSP doesn't use this property.
        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
        dependencies: self.targetDependencies[targetId, default: []].sorted { $0.uri.stringValue < $1.uri.stringValue },
        dataKind: .sourceKit,
        data: SourceKitBuildTarget(toolchain: toolchain.path.map(URI.init)).encodeToLSPAny()
      )
    }
    targets.append(
      BuildTarget(
        id: .forPackageManifest,
        displayName: "Package.swift",
        baseDirectory: nil,
        tags: [.notBuildable],
        capabilities: BuildTargetCapabilities(),
        languageIds: [.swift],
        dependencies: []
      )
    )
    return WorkspaceBuildTargetsResponse(targets: targets)
  }

  package func buildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    var result: [SourcesItem] = []
    // TODO: Query The SwiftPM build system for the document's language and add it to SourceItem.data
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1267)
    for target in request.targets {
      if target == .forPackageManifest {
        let packageManifestName = #/^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift$/#
        let versionSpecificManifests = try? FileManager.default.contentsOfDirectory(
          at: projectRoot,
          includingPropertiesForKeys: nil
        ).compactMap { (url) -> SourceItem? in
          guard (try? packageManifestName.wholeMatch(in: url.lastPathComponent)) != nil else {
            return nil
          }
          return SourceItem(
            uri: DocumentURI(url),
            kind: .file,
            generated: false
          )
        }
        let packageManifest = SourceItem(
          uri: DocumentURI(projectRoot.appendingPathComponent("Package.swift")),
          kind: .file,
          generated: false
        )
        result.append(
          SourcesItem(
            target: target,
            sources: [packageManifest] + (versionSpecificManifests ?? [])
          )
        )
      }
      guard let swiftPMTarget = self.swiftPMTargets[target] else {
        continue
      }
      var sources = swiftPMTarget.sources.map {
        SourceItem(uri: DocumentURI($0), kind: .file, generated: false)
      }
      sources += swiftPMTarget.headers.map {
        SourceItem(
          uri: DocumentURI($0),
          kind: .file,
          generated: false,
          dataKind: .sourceKit,
          data: SourceKitSourceItemData(isHeader: true).encodeToLSPAny()
        )
      }
      sources += (swiftPMTarget.resources + swiftPMTarget.ignored + swiftPMTarget.others).map {
        SourceItem(
          uri: DocumentURI($0),
          kind: $0.isDirectory ? .directory : .file,
          generated: false
        )
      }
      result.append(SourcesItem(target: target, sources: sources))
    }
    return BuildTargetSourcesResponse(items: result)
  }

  package func sourceKitOptions(
    request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    guard let url = request.textDocument.uri.fileURL, let path = try? AbsolutePath(validating: url.filePath) else {
      // We can't determine build settings for non-file URIs.
      return nil
    }

    if request.target == .forPackageManifest {
      return try settings(forPackageManifest: path)
    }

    guard let swiftPMTarget = self.swiftPMTargets[request.target] else {
      logger.error("Did not find target \(request.target.forLogging)")
      return nil
    }

    if !swiftPMTarget.sources.lazy.map(DocumentURI.init).contains(request.textDocument.uri),
      let substituteFile = swiftPMTarget.sources.sorted(by: { $0.description < $1.description }).first
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
        compilerArguments: try await compilerArguments(for: DocumentURI(substituteFile), in: swiftPMTarget),
        workingDirectory: try projectRoot.filePath
      ).patching(newFile: DocumentURI(try path.asURL.realpath), originalFile: DocumentURI(substituteFile))
      return TextDocumentSourceKitOptionsResponse(
        compilerArguments: buildSettings.compilerArguments,
        workingDirectory: buildSettings.workingDirectory
      )
    }

    return TextDocumentSourceKitOptionsResponse(
      compilerArguments: try await compilerArguments(for: request.textDocument.uri, in: swiftPMTarget),
      workingDirectory: try projectRoot.filePath
    )
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    await self.packageLoadingQueue.async {}.valuePropagatingCancellation
    return VoidResponse()
  }

  package func prepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    // TODO: Support preparation of multiple targets at once. (https://github.com/swiftlang/sourcekit-lsp/issues/1262)
    for target in request.targets {
      await orLog("Preparing") { try await prepare(singleTarget: target) }
    }
    return VoidResponse()
  }

  private nonisolated func logMessageToIndexLog(_ taskID: TaskId, _ message: String) {
    connectionToSourceKitLSP.send(
      BuildServerProtocol.OnBuildLogMessageNotification(type: .info, task: taskID, message: message)
    )
  }

  private func prepare(singleTarget target: BuildTargetIdentifier) async throws {
    if target == .forPackageManifest {
      // Nothing to prepare for package manifests.
      return
    }

    guard let swift = toolchain.swift else {
      logger.error(
        "Not preparing because toolchain at \(self.toolchain.identifier) does not contain a Swift compiler"
      )
      return
    }
    logger.debug("Preparing '\(target.forLogging)' using \(self.toolchain.identifier)")
    var arguments = [
      try swift.filePath, "build",
      "--package-path", try projectRoot.filePath,
      "--scratch-path", self.swiftPMWorkspace.location.scratchDirectory.pathString,
      "--disable-index-store",
      "--target", try target.swiftpmTargetProperties.target,
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

    let taskID: TaskId = TaskId(id: "preparation-\(preparationTaskID.fetchAndIncrement())")
    logMessageToIndexLog(
      taskID,
      """
      Preparing \(self.swiftPMTargets[target]?.name ?? target.uri.stringValue)
      \(arguments.joined(separator: " "))
      """
    )
    let stdoutHandler = PipeAsStringHandler { self.logMessageToIndexLog(taskID, $0) }
    let stderrHandler = PipeAsStringHandler { self.logMessageToIndexLog(taskID, $0) }

    let result = try await Process.run(
      arguments: arguments,
      workingDirectory: nil,
      outputRedirection: .stream(
        stdout: { @Sendable bytes in stdoutHandler.handleDataFromPipe(Data(bytes)) },
        stderr: { @Sendable bytes in stderrHandler.handleDataFromPipe(Data(bytes)) }
      )
    )
    let exitStatus = result.exitStatus.exhaustivelySwitchable
    logMessageToIndexLog(taskID, "Finished with \(exitStatus.description) in \(start.duration(to: .now))")
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

  package func didChangeWatchedFiles(notification: OnWatchedFilesDidChangeNotification) async {
    if let packageReloadTriggerEvent = notification.changes.first(where: {
      self.fileEventShouldTriggerPackageReload(event: $0)
    }) {
      logger.log("Reloading package because \(packageReloadTriggerEvent.uri.forLogging) changed")
      await packageLoadingQueue.async {
        await orLog("Reloading package") {
          try await self.reloadPackageAssumingOnPackageLoadingQueue()
        }
      }.valuePropagatingCancellation
    }
  }

  /// Retrieve settings for a package manifest (Package.swift).
  private func settings(forPackageManifest path: AbsolutePath) throws -> TextDocumentSourceKitOptionsResponse? {
    let compilerArgs = try swiftPMWorkspace.interpreterFlags(for: path) + [path.pathString]
    return TextDocumentSourceKitOptionsResponse(compilerArguments: compilerArgs)
  }
}

fileprivate extension URL {
  var isDirectory: Bool {
    (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
  }
}

#endif
