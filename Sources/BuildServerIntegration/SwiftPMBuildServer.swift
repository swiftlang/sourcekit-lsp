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

#if !NO_SWIFTPM_DEPENDENCY
import Basics
@preconcurrency import Build
@_spi(SourceKitLSP) package import BuildServerProtocol
import Dispatch
package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@preconcurrency import PackageGraph
import PackageLoading
@preconcurrency import PackageModel
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
@preconcurrency package import SPMBuildCore
import SourceControl
@preconcurrency package import SourceKitLSPAPI
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import TSCExtensions
package import ToolchainRegistry
@preconcurrency import Workspace

package import struct BuildServerProtocol.SourceItem
import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
package import class ToolchainRegistry.Toolchain
import struct TSCBasic.FileSystemError

private typealias AbsolutePath = Basics.AbsolutePath

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

private let preparationTaskID: AtomicUInt32 = AtomicUInt32(initialValue: 0)

/// Swift Package Manager build server and workspace support.
///
/// This class implements the `BuiltInBuildServe` interface to provide the build settings for a Swift
/// Package Manager (SwiftPM) package. The settings are determined by loading the Package.swift
/// manifest using `libSwiftPM` and constructing a build plan using the default (debug) parameters.
package actor SwiftPMBuildServer: BuiltInBuildServer {
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

  /// Whether the `SwiftPMBuildServer` is pointed at a `.build/index-build` directory that's independent of the
  /// user's build.
  private var isForIndexBuild: Bool { options.backgroundIndexingOrDefault }

  // MARK: Build server options (set once and not modified)

  /// The directory containing `Package.swift`.
  private let projectRoot: URL

  package let fileWatchers: [FileSystemWatcher]

  package let toolsBuildParameters: BuildParameters
  package let destinationBuildParameters: BuildParameters

  private let toolchain: Toolchain
  private let swiftPMWorkspace: Workspace

  private let pluginConfiguration: PluginConfiguration
  private let traitConfiguration: TraitConfiguration

  /// Paths to any toolsets provided in `SourceKitLSPOptions`, with any relative paths resolved based on the project
  /// root.
  private let toolsets: [AbsolutePath]

  /// A `ObservabilitySystem` from `SwiftPM` that logs.
  private let observabilitySystem: ObservabilitySystem

  // MARK: Build server state (modified on package reload)

  /// The entry point via with we can access the `SourceKitLSPAPI` provided by SwiftPM.
  private var buildDescription: SourceKitLSPAPI.BuildDescription?

  /// Maps target ids to their SwiftPM build target.
  private var swiftPMTargets: [BuildTargetIdentifier: any SwiftBuildTarget] = [:]

  private var targetDependencies: [BuildTargetIdentifier: Set<BuildTargetIdentifier>] = [:]

  /// Regular expression that matches version-specific package manifest file names such as Package@swift-6.1.swift
  private static var versionSpecificPackageManifestNameRegex: Regex<(Substring, Substring, Substring?, Substring?)> {
    #/^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift$/#
  }

  static package func searchForConfig(in path: URL, options: SourceKitLSPOptions) -> BuildServerSpec? {
    let packagePath = path.appending(component: "Package.swift")
    if (try? String(contentsOf: packagePath, encoding: .utf8))?.contains("PackageDescription") ?? false {
      return BuildServerSpec(kind: .swiftPM, projectRoot: path, configPath: packagePath)
    }

    return nil
  }

  /// Creates a build server using the Swift Package Manager, if this workspace is a package.
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
    // We could theoretically dynamically register all known files when we get back the build graph, but that seems
    // more errorprone than just watching everything and then filtering when we need to (eg. in
    // `SemanticIndexManager.filesDidChange`).
    self.fileWatchers = [FileSystemWatcher(globPattern: "**/*", kind: [.create, .change, .delete])]
    let toolchain = await toolchainRegistry.preferredToolchain(containing: [
      \.clang, \.clangd, \.sourcekitd, \.swift, \.swiftc,
    ])
    guard let toolchain else {
      throw Error.cannotDetermineHostToolchain
    }

    self.toolchain = toolchain
    self.testHooks = testHooks
    self.connectionToSourceKitLSP = connectionToSourceKitLSP

    // Start an open-ended log for messages that we receive during package loading. We never end this log.
    let logTaskID = TaskId(id: "swiftpm-log-\(UUID())")
    connectionToSourceKitLSP.send(
      OnBuildLogMessageNotification(
        type: .info,
        task: logTaskID,
        message: "",
        structure: .begin(StructuredLogBegin(title: "SwiftPM log for \(projectRoot.path)"))
      )
    )

    self.observabilitySystem = ObservabilitySystem({ scope, diagnostic in
      connectionToSourceKitLSP.send(
        OnBuildLogMessageNotification(
          type: .info,
          task: logTaskID,
          message: diagnostic.description,
          structure: .report(StructuredLogReport())
        )
      )
      logger.log(level: diagnostic.severity.asLogLevel, "SwiftPM log: \(diagnostic.description)")
    })

    guard let destinationToolchainBinDir = toolchain.swiftc?.deletingLastPathComponent() else {
      throw Error.cannotDetermineHostToolchain
    }

    let absProjectRoot = try AbsolutePath(validating: projectRoot.filePath)
    self.toolsets =
      try options.swiftPMOrDefault.toolsets?.map {
        try AbsolutePath(validating: $0, relativeTo: absProjectRoot)
      } ?? []

    let hostSDK = try SwiftSDK.hostSwiftSDK(AbsolutePath(validating: destinationToolchainBinDir.filePath))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    let triple: Triple? =
      if let triple = options.swiftPMOrDefault.triple {
        try Triple(triple)
      } else {
        nil
      }
    let swiftSDKsDirectory: AbsolutePath? =
      if let swiftSDKsDirectory = options.swiftPMOrDefault.swiftSDKsDirectory {
        try AbsolutePath(validating: swiftSDKsDirectory, relativeTo: absProjectRoot)
      } else {
        nil
      }
    let destinationSDK = try SwiftSDK.deriveTargetSwiftSDK(
      hostSwiftSDK: hostSDK,
      hostTriple: hostSwiftPMToolchain.targetTriple,
      customToolsets: toolsets,
      customCompileTriple: triple,
      swiftSDKSelector: options.swiftPMOrDefault.swiftSDK,
      store: SwiftSDKBundleStore(
        swiftSDKsDirectory: localFileSystem.getSharedSwiftSDKsDirectory(
          explicitDirectory: swiftSDKsDirectory
        ),
        hostToolchainBinDir: hostSwiftPMToolchain.swiftCompilerPath.parentDirectory,
        fileSystem: localFileSystem,
        observabilityScope: observabilitySystem.topScope.makeChildScope(description: "SwiftPM Bundle Store"),
        outputHandler: { _ in }
      ),
      observabilityScope: observabilitySystem.topScope.makeChildScope(description: "Derive Target Swift SDK"),
      fileSystem: localFileSystem
    )

    let destinationSwiftPMToolchain = try UserToolchain(swiftSDK: destinationSDK)

    var location = try Workspace.Location(
      forRootPackage: absProjectRoot,
      fileSystem: localFileSystem
    )

    if let scratchDirectory = options.swiftPMOrDefault.scratchPath {
      location.scratchDirectory = try AbsolutePath(validating: scratchDirectory, relativeTo: absProjectRoot)
    } else if options.backgroundIndexingOrDefault {
      location.scratchDirectory = absProjectRoot.appending(components: ".build", "index-build")
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
        extraManifestFlags: options.swiftPMOrDefault.buildToolsSwiftCompilerFlags,
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
      flags: buildFlags,
      buildSystemKind: .native,
    )

    self.destinationBuildParameters = try BuildParameters(
      destination: .target,
      dataPath: location.scratchDirectory.appending(
        component: destinationSwiftPMToolchain.targetTriple.platformBuildPathComponent
      ),
      configuration: buildConfiguration,
      toolchain: destinationSwiftPMToolchain,
      triple: destinationSDK.targetTriple,
      flags: buildFlags,
      buildSystemKind: .native,
      prepareForIndexing: options.backgroundPreparationModeOrDefault.toSwiftPMPreparation
    )

    let pluginScriptRunner = DefaultPluginScriptRunner(
      fileSystem: localFileSystem,
      cacheDir: location.pluginWorkingDirectory.appending("cache"),
      toolchain: hostSwiftPMToolchain,
      extraPluginSwiftCFlags: options.swiftPMOrDefault.buildToolsSwiftCompilerFlags ?? [],
      enableSandbox: !(options.swiftPMOrDefault.disableSandbox ?? false)
    )
    self.pluginConfiguration = PluginConfiguration(
      scriptRunner: pluginScriptRunner,
      workDirectory: location.pluginWorkingDirectory,
      disableSandbox: options.swiftPMOrDefault.disableSandbox ?? false
    )

    let enabledTraits: Set<String>? =
      if let traits = options.swiftPMOrDefault.traits {
        Set(traits)
      } else {
        nil
      }
    self.traitConfiguration = TraitConfiguration(enabledTraits: enabledTraits)

    packageLoadingQueue.async {
      await orLog("Initial package loading") {
        // Schedule an initial generation of the build graph. Once the build graph is loaded, the build server will send
        // call `fileHandlingCapabilityChanged`, which allows us to move documents to a workspace with this build
        // server.
        try await self.reloadPackageAssumingOnPackageLoadingQueue()
      }
    }
  }

  /// Loading the build description sometimes fails non-deterministically on Windows because it's unable to write
  /// `output-file-map.json`, probably due to https://github.com/swiftlang/swift-package-manager/issues/8038.
  /// If this happens, retry loading the build description up to `maxLoadAttempt` times.
  private func loadBuildDescriptionWithRetryOnOutputFileMapWriteErrorOnWindows(
    modulesGraph: ModulesGraph,
    maxLoadAttempts: Int = 5
  ) async throws -> (description: SourceKitLSPAPI.BuildDescription, errors: String) {
    // TODO: Remove this workaround once https://github.com/swiftlang/swift-package-manager/issues/8038 is fixed.
    var loadAttempt = 0
    while true {
      loadAttempt += 1
      do {
        return try await BuildDescription.load(
          destinationBuildParameters: destinationBuildParameters,
          toolsBuildParameters: toolsBuildParameters,
          packageGraph: modulesGraph,
          pluginConfiguration: pluginConfiguration,
          traitConfiguration: traitConfiguration,
          disableSandbox: options.swiftPMOrDefault.disableSandbox ?? false,
          scratchDirectory: swiftPMWorkspace.location.scratchDirectory.asURL,
          fileSystem: localFileSystem,
          observabilityScope: observabilitySystem.topScope.makeChildScope(
            description: "Create SwiftPM build description"
          )
        )
      } catch {
        guard SwiftExtensions.Platform.current == .windows else {
          // We only retry loading the build description on Windows. The output-file-map issue does not exist on other
          // platforms.
          throw error
        }
        let isOutputFileMapWriteError: Bool
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
          nsError.code == CocoaError.fileWriteNoPermission.rawValue,
          (nsError.userInfo["NSURL"] as? URL)?.lastPathComponent == "output-file-map.json"
        {
          isOutputFileMapWriteError = true
        } else if let error = error as? FileSystemError,
          error.kind == .invalidAccess && error.path?.basename == "output-file-map.json"
        {
          isOutputFileMapWriteError = true
        } else {
          isOutputFileMapWriteError = false
        }
        if isOutputFileMapWriteError, loadAttempt < maxLoadAttempts {
          logger.log(
            """
            Loading the build description failed to write output-file-map.json \
            (attempt \(loadAttempt)/\(maxLoadAttempts)), trying again.
            \(error.forLogging)
            """
          )
          continue
        }
        throw error
      }
    }
  }

  /// (Re-)load the package settings by parsing the manifest and resolving all the targets and
  /// dependencies.
  ///
  /// - Important: Must only be called on `packageLoadingQueue`.
  private func reloadPackageAssumingOnPackageLoadingQueue() async throws {
    let signposter = logger.makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Reloading package", id: signpostID, "Start reloading package")

    self.connectionToSourceKitLSP.send(
      TaskStartNotification(
        taskId: TaskId(id: "package-reloading"),
        data: WorkDoneProgressTask(title: "SourceKit-LSP: Reloading Package").encodeToLSPAny()
      )
    )
    await testHooks.reloadPackageDidStart?()
    defer {
      signposter.endInterval("Reloading package", state)
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

    signposter.emitEvent("Finished loading modules graph", id: signpostID)

    // We have a whole separate arena if we're performing background indexing. This allows us to also build and run
    // plugins, without having to worry about messing up any regular build state.
    let buildDescription: SourceKitLSPAPI.BuildDescription
    if isForIndexBuild && !(options.swiftPMOrDefault.skipPlugins ?? false) {
      let loaded = try await loadBuildDescriptionWithRetryOnOutputFileMapWriteErrorOnWindows(modulesGraph: modulesGraph)
      if !loaded.errors.isEmpty {
        logger.error("Loading SwiftPM description had errors: \(loaded.errors)")
      }

      signposter.emitEvent("Finished generating build description", id: signpostID)

      buildDescription = loaded.description
    } else {
      let plan = try await BuildPlan(
        destinationBuildParameters: destinationBuildParameters,
        toolsBuildParameters: toolsBuildParameters,
        graph: modulesGraph,
        disableSandbox: options.swiftPMOrDefault.disableSandbox ?? false,
        fileSystem: localFileSystem,
        observabilityScope: observabilitySystem.topScope.makeChildScope(description: "Create SwiftPM build plan")
      )

      signposter.emitEvent("Finished generating build plan", id: signpostID)

      buildDescription = BuildDescription(buildPlan: plan, pluginConfiguration: self.pluginConfiguration)
    }

    /// Make sure to execute any throwing statements before setting any
    /// properties because otherwise we might end up in an inconsistent state
    /// with only some properties modified.

    self.buildDescription = buildDescription
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

    signposter.emitEvent("Finished traversing modules", id: signpostID)

    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  package nonisolated var supportsPreparationAndOutputPaths: Bool { options.backgroundIndexingOrDefault }

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
    return buildPath.appending(components: "index", "db")
  }

  private func indexUnitOutputPath(forSwiftFile uri: DocumentURI) -> String {
    return uri.pseudoPath + ".o"
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
    #if compiler(>=6.4)
    #warning(
      "Once we can guarantee that the toolchain can index multiple Swift files in a single invocation, we no longer need to set -index-unit-output-path since it's always set using an -output-file-map"
    )
    #endif
    var compilerArguments = try buildTarget.compileArguments(for: fileURL)
    if buildTarget.compiler == .swift {
      compilerArguments += [
        // Fake an output path so that we get a different unit file for every Swift file we background index
        "-index-unit-output-path", indexUnitOutputPath(forSwiftFile: file),
      ]
    }
    return compilerArguments
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
        tags: tags,
        capabilities: BuildTargetCapabilities(),
        // Be conservative with the languages that might be used in the target. SourceKit-LSP doesn't use this property.
        languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
        dependencies: self.targetDependencies[targetId, default: []].sorted { $0.uri.stringValue < $1.uri.stringValue },
        dataKind: .sourceKit,
        data: SourceKitBuildTarget(toolchain: URI(toolchain.path)).encodeToLSPAny()
      )
    }
    targets.append(
      BuildTarget(
        id: .forPackageManifest,
        displayName: "Package.swift",
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
    // TODO: Query The SwiftPM build server for the document's language and add it to SourceItem.data
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1267)
    for target in request.targets {
      if target == .forPackageManifest {
        let versionSpecificManifests = try? FileManager.default.contentsOfDirectory(
          at: projectRoot,
          includingPropertiesForKeys: nil
        ).compactMap { (url) -> SourceItem? in
          guard (try? Self.versionSpecificPackageManifestNameRegex.wholeMatch(in: url.lastPathComponent)) != nil else {
            return nil
          }
          return SourceItem(
            uri: DocumentURI(url),
            kind: .file,
            generated: false
          )
        }
        let packageManifest = SourceItem(
          uri: DocumentURI(projectRoot.appending(component: "Package.swift")),
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
      var sources: [SourceItem] = []
      for sourceItem in swiftPMTarget.sources {
        let outputPath: String? =
          if let outputFile = sourceItem.outputFile {
            orLog("Getting file path of output file") { try outputFile.filePath }
          } else if swiftPMTarget.compiler == .swift {
            indexUnitOutputPath(forSwiftFile: DocumentURI(sourceItem.sourceFile))
          } else {
            nil
          }
        sources.append(
          SourceItem(
            uri: DocumentURI(sourceItem.sourceFile),
            kind: .file,
            generated: false,
            dataKind: .sourceKit,
            data: SourceKitSourceItemData(outputPath: outputPath).encodeToLSPAny()
          )
        )
      }
      for url in swiftPMTarget.headers {
        sources.append(
          SourceItem(
            uri: DocumentURI(url),
            kind: .file,
            generated: false,
            dataKind: .sourceKit,
            data: SourceKitSourceItemData(kind: .header).encodeToLSPAny()
          )
        )
      }
      for url in (swiftPMTarget.resources + swiftPMTarget.ignored + swiftPMTarget.others) {
        var data: SourceKitSourceItemData? = nil
        if url.isDirectory, url.pathExtension == "docc" {
          data = SourceKitSourceItemData(kind: .doccCatalog)
        }
        sources.append(
          SourceItem(
            uri: DocumentURI(url),
            kind: url.isDirectory ? .directory : .file,
            generated: false,
            dataKind: data != nil ? .sourceKit : nil,
            data: data?.encodeToLSPAny()
          )
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

    if !swiftPMTarget.sources.lazy.map({ DocumentURI($0.sourceFile) }).contains(request.textDocument.uri),
      let substituteFile = swiftPMTarget.sources.map(\.sourceFile).sorted(by: { $0.description < $1.description }).first
    {
      logger.info("Getting compiler arguments for \(url) using substitute file \(substituteFile)")
      // If `url` is not part of the target's source, it's most likely a header file. Fake compiler arguments for it
      // from a substitute file within the target.
      // Even if the file is not a header, this should give reasonable results: Say, there was a new `.cpp` file in a
      // target and for some reason the `SwiftPMBuildServer` doesn’t know about it. Then we would infer the target based
      // on the file's location on disk and generate compiler arguments for it by picking a source file in that target,
      // getting its compiler arguments and then patching up the compiler arguments by replacing the substitute file
      // with the `.cpp` file.
      let buildSettings = FileBuildSettings(
        compilerArguments: try await compilerArguments(for: DocumentURI(substituteFile), in: swiftPMTarget),
        workingDirectory: try projectRoot.filePath,
        language: request.language
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
    if let triple = options.swiftPMOrDefault.triple {
      arguments += ["--triple", triple]
    }
    if let swiftSDKsDirectory = options.swiftPMOrDefault.swiftSDKsDirectory {
      arguments += ["--swift-sdks-path", swiftSDKsDirectory]
    }
    if let swiftSDK = options.swiftPMOrDefault.swiftSDK {
      arguments += ["--swift-sdk", swiftSDK]
    }
    if let traits = options.swiftPMOrDefault.traits {
      arguments += ["--traits", traits.joined(separator: ",")]
    }
    arguments += toolsets.flatMap { ["--toolset", $0.pathString] }
    arguments += options.swiftPMOrDefault.cCompilerFlags?.flatMap { ["-Xcc", $0] } ?? []
    arguments += options.swiftPMOrDefault.cxxCompilerFlags?.flatMap { ["-Xcxx", $0] } ?? []
    arguments += options.swiftPMOrDefault.swiftCompilerFlags?.flatMap { ["-Xswiftc", $0] } ?? []
    arguments += options.swiftPMOrDefault.linkerFlags?.flatMap { ["-Xlinker", $0] } ?? []
    arguments += options.swiftPMOrDefault.buildToolsSwiftCompilerFlags?.flatMap { ["-Xbuild-tools-swiftc", $0] } ?? []
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
    connectionToSourceKitLSP.send(
      BuildServerProtocol.OnBuildLogMessageNotification(
        type: .info,
        task: taskID,
        message: "\(arguments.joined(separator: " "))",
        structure: .begin(
          StructuredLogBegin(title: "Preparing \(self.swiftPMTargets[target]?.name ?? target.uri.stringValue)")
        )
      )
    )
    let stdoutHandler = PipeAsStringHandler { message in
      self.connectionToSourceKitLSP.send(
        BuildServerProtocol.OnBuildLogMessageNotification(
          type: .info,
          task: taskID,
          message: message,
          structure: .report(StructuredLogReport())
        )
      )
    }
    let stderrHandler = PipeAsStringHandler { message in
      self.connectionToSourceKitLSP.send(
        BuildServerProtocol.OnBuildLogMessageNotification(
          type: .info,
          task: taskID,
          message: message,
          structure: .report(StructuredLogReport())
        )
      )
    }

    let result = try await Process.run(
      arguments: arguments,
      workingDirectory: nil,
      outputRedirection: .stream(
        stdout: { @Sendable bytes in stdoutHandler.handleDataFromPipe(Data(bytes)) },
        stderr: { @Sendable bytes in stderrHandler.handleDataFromPipe(Data(bytes)) }
      )
    )
    let exitStatus = result.exitStatus.exhaustivelySwitchable
    self.connectionToSourceKitLSP.send(
      BuildServerProtocol.OnBuildLogMessageNotification(
        type: exitStatus.isSuccess ? .info : .error,
        task: taskID,
        message: "Finished with \(exitStatus.description) in \(start.duration(to: .now))",
        structure: .end(StructuredLogEnd())
      )
    )
    switch exitStatus {
    case .terminated(code: 0):
      break
    case .terminated(let code):
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
    case .signalled(let signal):
      if !Task.isCancelled {
        // The indexing job finished with a signal. Could be because the compiler crashed.
        // Ignore signal exit codes if this task has been cancelled because the compiler exits with SIGINT if it gets
        // interrupted.
        logger.error("Preparation of target \(target.forLogging) signaled \(signal)")
      }
    case .abnormal(let exception):
      if !Task.isCancelled {
        logger.error("Preparation of target \(target.forLogging) exited abnormally \(exception)")
      }
    }
  }

  private func isPackageManifestOrPackageResolved(_ url: URL) -> Bool {
    guard url.lastPathComponent.contains("Package") else {
      // Fast check to early exit for files that don't like a package manifest or Package.resolved
      return false
    }
    guard
      url.lastPathComponent == "Package.resolved" || url.lastPathComponent == "Package.swift"
        || (try? Self.versionSpecificPackageManifestNameRegex.wholeMatch(in: url.lastPathComponent)) != nil
    else {
      return false
    }
    // Compare the URLs as `DocumentURI`, which is a little more lenient to declare equality, eg. it considers paths
    // equivalent even `url.deletingLastPathComponent()` has a trailing slash while `self.projectRoot` does not.
    return DocumentURI(url.deletingLastPathComponent()) == DocumentURI(self.projectRoot)
  }

  /// An event is relevant if it modifies a file that matches one of the file rules used by the SwiftPM workspace.
  private func fileEventShouldTriggerPackageReload(event: FileEvent) -> Bool {
    guard let fileURL = event.uri.fileURL else {
      return false
    }
    if isPackageManifestOrPackageResolved(fileURL) {
      return true
    }
    switch event.type {
    case .created, .deleted:
      guard let buildDescription else {
        return false
      }

      return buildDescription.fileAffectsSwiftOrClangBuildSettings(fileURL)
    case .changed:
      // Only modified package manifests should trigger a package reload and that's handled above.
      return false
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

fileprivate extension SourceKitLSPOptions.BackgroundPreparationMode {
  var toSwiftPMPreparation: BuildParameters.PrepareForIndexingMode {
    switch self {
    case .build:
      return .off
    case .noLazy:
      return .noLazy
    case .enabled:
      return .on
    }
  }
}

#endif
