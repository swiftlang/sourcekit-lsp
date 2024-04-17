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
import Build
import BuildServerProtocol
import Dispatch
import LSPLogging
import LanguageServerProtocol
import PackageGraph
import PackageLoading
import PackageModel
import SKCore
import SKSupport
import SourceControl
import SourceKitLSPAPI
import Workspace

import struct Basics.AbsolutePath
import struct Basics.TSCAbsolutePath
import struct Foundation.URL
import protocol TSCBasic.FileSystem
import var TSCBasic.localFileSystem
import func TSCBasic.resolveSymlinks

#if canImport(SPMBuildCore)
import SPMBuildCore
#endif

/// Parameter of `reloadPackageStatusCallback` in ``SwiftPMWorkspace``.
///
/// Informs the callback about whether `reloadPackage` started or finished executing.
public enum ReloadPackageStatus: Sendable {
  case start
  case end
}

/// A build target in SwiftPM
public typealias SwiftBuildTarget = SourceKitLSPAPI.BuildTarget

/// A build target in `BuildServerProtocol`
public typealias BuildServerTarget = BuildServerProtocol.BuildTarget

/// Same as `toolchainRegistry.default`.
///
/// Needed to work around a compiler crash that prevents us from accessing `toolchainRegistry.default` in
/// `SwiftPMWorkspace.init`.
private func getDefaultToolchain(_ toolchainRegistry: ToolchainRegistry) async -> SKCore.Toolchain? {
  return await toolchainRegistry.default
}

/// Swift Package Manager build system and workspace support.
///
/// This class implements the `BuildSystem` interface to provide the build settings for a Swift
/// Package Manager (SwiftPM) package. The settings are determined by loading the Package.swift
/// manifest using `libSwiftPM` and constructing a build plan using the default (debug) parameters.
public actor SwiftPMBuildSystem {

  public enum Error: Swift.Error {

    /// Could not find a manifest (Package.swift file). This is not a package.
    case noManifest(workspacePath: TSCAbsolutePath)

    /// Could not determine an appropriate toolchain for swiftpm to use for manifest loading.
    case cannotDetermineHostToolchain
  }

  /// Delegate to handle any build system events.
  public weak var delegate: SKCore.BuildSystemDelegate? = nil

  public func setDelegate(_ delegate: SKCore.BuildSystemDelegate?) async {
    self.delegate = delegate
  }

  let workspacePath: TSCAbsolutePath
  /// The directory containing `Package.swift`.
  public var projectRoot: TSCAbsolutePath
  var modulesGraph: ModulesGraph
  let workspace: Workspace
  public let buildParameters: BuildParameters
  let fileSystem: FileSystem

  var fileToTarget: [AbsolutePath: SwiftBuildTarget] = [:]
  var sourceDirToTarget: [AbsolutePath: SwiftBuildTarget] = [:]

  /// The URIs for which the delegate has registered for change notifications,
  /// mapped to the language the delegate specified when registering for change notifications.
  var watchedFiles: Set<DocumentURI> = []

  /// This callback is informed when `reloadPackage` starts and ends executing.
  var reloadPackageStatusCallback: (ReloadPackageStatus) async -> Void

  /// Debounces calls to `delegate.filesDependenciesUpdated`.
  ///
  /// This is to ensure we don't call `filesDependenciesUpdated` for the same file multiple time if the client does not
  /// debounce `workspace/didChangeWatchedFiles` and sends a separate notification eg. for every file within a target as
  /// it's being updated by a git checkout, which would cause other files within that target to receive a
  /// `fileDependenciesUpdated` call once for every updated file within the target.
  ///
  /// Force-unwrapped optional because initializing it requires access to `self`.
  var fileDependenciesUpdatedDebouncer: Debouncer<Set<DocumentURI>>! = nil

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - workspace: The workspace root path.
  ///   - toolchainRegistry: The toolchain registry to use to provide the Swift compiler used for
  ///     manifest parsing and runtime support.
  ///   - reloadPackageStatusCallback: Will be informed when `reloadPackage` starts and ends executing.
  /// - Throws: If there is an error loading the package, or no manifest is found.
  public init(
    workspacePath: TSCAbsolutePath,
    toolchainRegistry: ToolchainRegistry,
    fileSystem: FileSystem = localFileSystem,
    buildSetup: BuildSetup,
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) async -> Void = { _ in }
  ) async throws {
    self.workspacePath = workspacePath
    self.fileSystem = fileSystem

    guard let packageRoot = findPackageDirectory(containing: workspacePath, fileSystem) else {
      throw Error.noManifest(workspacePath: workspacePath)
    }

    self.projectRoot = try resolveSymlinks(packageRoot)

    guard let destinationToolchainBinDir = await getDefaultToolchain(toolchainRegistry)?.swiftc?.parentDirectory else {
      throw Error.cannotDetermineHostToolchain
    }

    let swiftSDK = try SwiftSDK.hostSwiftSDK(AbsolutePath(destinationToolchainBinDir))
    let toolchain = try UserToolchain(swiftSDK: swiftSDK)

    var location = try Workspace.Location(
      forRootPackage: AbsolutePath(packageRoot),
      fileSystem: fileSystem
    )
    if let scratchDirectory = buildSetup.path {
      location.scratchDirectory = AbsolutePath(scratchDirectory)
    }

    var configuration = WorkspaceConfiguration.default
    configuration.skipDependenciesUpdates = true

    self.workspace = try Workspace(
      fileSystem: fileSystem,
      location: location,
      configuration: configuration,
      customHostToolchain: toolchain
    )

    let buildConfiguration: PackageModel.BuildConfiguration
    switch buildSetup.configuration {
    case .debug, nil:
      buildConfiguration = .debug
    case .release:
      buildConfiguration = .release
    }

    self.buildParameters = try BuildParameters(
      dataPath: location.scratchDirectory.appending(component: toolchain.targetTriple.platformBuildPathComponent),
      configuration: buildConfiguration,
      toolchain: toolchain,
      flags: buildSetup.flags
    )

    self.modulesGraph = try ModulesGraph(rootPackages: [], dependencies: [], binaryArtifacts: [:])
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

    try await reloadPackage()
  }

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - reloadPackageStatusCallback: Will be informed when `reloadPackage` starts and ends executing.
  /// - Returns: nil if `workspacePath` is not part of a package or there is an error.
  public init?(
    url: URL,
    toolchainRegistry: ToolchainRegistry,
    buildSetup: BuildSetup,
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) async -> Void
  ) async {
    do {
      try await self.init(
        workspacePath: try TSCAbsolutePath(validating: url.path),
        toolchainRegistry: toolchainRegistry,
        fileSystem: localFileSystem,
        buildSetup: buildSetup,
        reloadPackageStatusCallback: reloadPackageStatusCallback
      )
    } catch Error.noManifest {
      return nil
    } catch {
      logger.error("failed to create SwiftPMWorkspace at \(url.path): \(error.forLogging)")
      return nil
    }
  }
}

extension SwiftPMBuildSystem {

  /// (Re-)load the package settings by parsing the manifest and resolving all the targets and
  /// dependencies.
  func reloadPackage() async throws {
    await reloadPackageStatusCallback(.start)
    defer {
      Task {
        await reloadPackageStatusCallback(.end)
      }
    }

    let observabilitySystem = ObservabilitySystem({ scope, diagnostic in
      logger.log(level: diagnostic.severity.asLogLevel, "SwiftPM log: \(diagnostic.description)")
    })

    let modulesGraph = try self.workspace.loadPackageGraph(
      rootInput: PackageGraphRootInput(packages: [AbsolutePath(projectRoot)]),
      forceResolvedVersions: true,
      availableLibraries: self.buildParameters.toolchain.providedLibraries,
      observabilityScope: observabilitySystem.topScope
    )

    let plan = try BuildPlan(
      productsBuildParameters: buildParameters,
      toolsBuildParameters: buildParameters,
      graph: modulesGraph,
      fileSystem: fileSystem,
      observabilityScope: observabilitySystem.topScope
    )
    let buildDescription = BuildDescription(buildPlan: plan)

    /// Make sure to execute any throwing statements before setting any
    /// properties because otherwise we might end up in an inconsistent state
    /// with only some properties modified.
    self.modulesGraph = modulesGraph

    self.fileToTarget = [AbsolutePath: SwiftBuildTarget](
      modulesGraph.allTargets.flatMap { target in
        return target.sources.paths.compactMap {
          guard let buildTarget = buildDescription.getBuildTarget(for: target) else {
            return nil
          }
          return (key: $0, value: buildTarget)
        }
      },
      uniquingKeysWith: { td, _ in
        // FIXME: is there  a preferred target?
        return td
      }
    )

    self.sourceDirToTarget = [AbsolutePath: SwiftBuildTarget](
      modulesGraph.allTargets.compactMap { (target) -> (AbsolutePath, SwiftBuildTarget)? in
        guard let buildTarget = buildDescription.getBuildTarget(for: target) else {
          return nil
        }
        return (key: target.sources.root, value: buildTarget)
      },
      uniquingKeysWith: { td, _ in
        // FIXME: is there  a preferred target?
        return td
      }
    )

    guard let delegate = self.delegate else {
      return
    }
    await delegate.fileBuildSettingsChanged(self.watchedFiles)
    await delegate.fileHandlingCapabilityChanged()
  }
}

extension SwiftPMBuildSystem: SKCore.BuildSystem {

  public var buildPath: TSCAbsolutePath {
    return TSCAbsolutePath(buildParameters.buildPath)
  }

  public var indexStorePath: TSCAbsolutePath? {
    return buildParameters.indexStoreMode == .off ? nil : TSCAbsolutePath(buildParameters.indexStore)
  }

  public var indexDatabasePath: TSCAbsolutePath? {
    return buildPath.appending(components: "index", "db")
  }

  public var indexPrefixMappings: [PathPrefixMapping] { return [] }

  public func buildSettings(for uri: DocumentURI, language: Language) throws -> FileBuildSettings? {
    guard let url = uri.fileURL else {
      // We can't determine build settings for non-file URIs.
      return nil
    }
    guard let path = try? AbsolutePath(validating: url.path) else {
      return nil
    }

    if let buildTarget = try buildTarget(for: path) {
      return FileBuildSettings(
        compilerArguments: try buildTarget.compileArguments(for: path.asURL),
        workingDirectory: workspacePath.pathString
      )
    }

    if path.basename == "Package.swift" {
      return try settings(forPackageManifest: path)
    }

    if path.extension == "h" {
      return try settings(forHeader: path, language)
    }

    return nil
  }

  public func registerForChangeNotifications(for uri: DocumentURI) async {
    self.watchedFiles.insert(uri)
  }

  /// Unregister the given file for build-system level change notifications, such as command
  /// line flag changes, dependency changes, etc.
  public func unregisterForChangeNotifications(for uri: DocumentURI) {
    self.watchedFiles.remove(uri)
  }

  /// Returns the resolved target description for the given file, if one is known.
  private func buildTarget(for file: AbsolutePath) throws -> SwiftBuildTarget? {
    if let td = fileToTarget[file] {
      return td
    }

    let realpath = try resolveSymlinks(file)
    if realpath != file, let td = fileToTarget[realpath] {
      fileToTarget[file] = td
      return td
    }

    return nil
  }

  /// An event is relevant if it modifies a file that matches one of the file rules used by the SwiftPM workspace.
  private func fileEventShouldTriggerPackageReload(event: FileEvent) -> Bool {
    guard let fileURL = event.uri.fileURL else {
      return false
    }
    switch event.type {
    case .created, .deleted:
      guard let path = try? AbsolutePath(validating: fileURL.path) else {
        return false
      }

      return self.workspace.fileAffectsSwiftOrClangBuildSettings(
        filePath: path,
        packageGraph: self.modulesGraph
      )
    case .changed:
      return fileURL.lastPathComponent == "Package.swift"
    default:  // Unknown file change type
      return false
    }
  }

  public func filesDidChange(_ events: [FileEvent]) async {
    if events.contains(where: { self.fileEventShouldTriggerPackageReload(event: $0) }) {
      logger.log("Reloading package because of file change")
      await orLog("Reloading package") {
        // TODO: It should not be necessary to reload the entire package just to get build settings for one file.
        try await self.reloadPackage()
      }
    }

    var filesWithUpdatedDependencies: Set<DocumentURI> = []
    // If a Swift file within a target is updated, reload all the other files within the target since they might be
    // referring to a function in the updated file.
    for event in events {
      guard let url = event.uri.fileURL,
        url.pathExtension == "swift",
        let absolutePath = try? AbsolutePath(validating: url.path),
        let target = fileToTarget[absolutePath]
      else {
        continue
      }
      filesWithUpdatedDependencies.formUnion(target.sources.map { DocumentURI($0) })
    }

    // If a `.swiftmodule` file is updated, this means that we have performed a build / are
    // performing a build and files that depend on this module have updated dependencies.
    // We don't have access to the build graph from the SwiftPM API offered to SourceKit-LSP to figure out which files
    // depend on the updated module, so assume that all files have updated dependencies.
    // The file watching here is somewhat fragile as well because it assumes that the `.swiftmodule` files are being
    // written to a directory within the workspace root. This is not necessarily true if the user specifies a build
    // directory outside the source tree.
    // All of this shouldn't be necessary once we have background preparation, in which case we know when preparation of
    // a target has finished.
    if events.contains(where: { $0.uri.fileURL?.pathExtension == "swiftmodule" }) {
      filesWithUpdatedDependencies.formUnion(self.fileToTarget.keys.map { DocumentURI($0.asURL) })
    }
    await self.fileDependenciesUpdatedDebouncer.scheduleCall(filesWithUpdatedDependencies)
  }

  public func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability {
    guard let fileUrl = uri.fileURL else {
      return .unhandled
    }
    if (try? buildTarget(for: AbsolutePath(validating: fileUrl.path))) != nil {
      return .handled
    } else {
      return .unhandled
    }
  }
}

extension SwiftPMBuildSystem {

  // MARK: Implementation details

  /// Retrieve settings for a package manifest (Package.swift).
  private func settings(forPackageManifest path: AbsolutePath) throws -> FileBuildSettings? {
    func impl(_ path: AbsolutePath) -> FileBuildSettings? {
      for package in modulesGraph.packages where path == package.manifest.path {
        let compilerArgs = workspace.interpreterFlags(for: package.path) + [path.pathString]
        return FileBuildSettings(compilerArguments: compilerArgs)
      }
      return nil
    }

    if let result = impl(path) {
      return result
    }

    let canonicalPath = try resolveSymlinks(path)
    return canonicalPath == path ? nil : impl(canonicalPath)
  }

  /// Retrieve settings for a given header file.
  ///
  /// This finds the target the header belongs to based on its location in the file system, retrieves the build settings
  /// for any file within that target and generates compiler arguments by replacing that picked file with the header
  /// file.
  /// This is safe because all files within one target have the same build settings except for reference to the file
  /// itself, which we are replacing.
  private func settings(forHeader path: AbsolutePath, _ language: Language) throws -> FileBuildSettings? {
    func impl(_ path: AbsolutePath) throws -> FileBuildSettings? {
      var dir = path.parentDirectory
      while !dir.isRoot {
        if let buildTarget = sourceDirToTarget[dir] {
          if let sourceFile = buildTarget.sources.first {
            return FileBuildSettings(
              compilerArguments: try buildTarget.compileArguments(for: sourceFile),
              workingDirectory: workspacePath.pathString
            ).patching(newFile: path.pathString, originalFile: sourceFile.absoluteString)
          }
          return nil
        }
        dir = dir.parentDirectory
      }
      return nil
    }

    if let result = try impl(path) {
      return result
    }

    let canonicalPath = try resolveSymlinks(path)
    return try canonicalPath == path ? nil : impl(canonicalPath)
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
