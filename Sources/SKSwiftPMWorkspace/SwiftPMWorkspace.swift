//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKCore
import Basic
import SPMUtility
import SKSupport
import Build
import PackageModel
import PackageGraph
import PackageLoading
import Workspace

/// Swift Package Manager build system and workspace support.
///
/// This class implements the `BuildSystem` interface to provide the build settings for a Swift
/// Package Manager (SwiftPM) package. The settings are determined by loading the Package.swift
/// manifest using `libSwiftPM` and constructing a build plan using the default (debug) parameters.
public final class SwiftPMWorkspace {

  public enum Error: Swift.Error {

    /// Could not find a manifest (Package.swift file). This is not a package.
    case noManifest(workspacePath: AbsolutePath)

    /// Could not determine an appropriate toolchain for swiftpm to use for manifest loading.
    case cannotDetermineHostToolchain
  }

  let workspacePath: AbsolutePath
  let packageRoot: AbsolutePath
  var packageGraph: PackageGraph
  let workspace: Workspace
  let buildParameters: BuildParameters
  let toolchainRegistry: ToolchainRegistry
  let fileSystem: FileSystem

  var fileToTarget: [AbsolutePath: TargetBuildDescription] = [:]
  var sourceDirToTarget: [AbsolutePath: TargetBuildDescription] = [:]

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Parameters:
  ///   - workspace: The workspace root path.
  ///   - toolchainRegistry: The toolchain registry to use to provide the Swift compiler used for
  ///     manifest parsing and runtime support.
  /// - Throws: If there is an error loading the package, or no manifest is found.
  public init(
    workspacePath: AbsolutePath,
    toolchainRegistry: ToolchainRegistry,
    fileSystem: FileSystem = localFileSystem,
    buildSetup: BuildSetup) throws
  {
    self.workspacePath = workspacePath
    self.toolchainRegistry = toolchainRegistry
    self.fileSystem = fileSystem

    guard let packageRoot = findPackageDirectory(containing: workspacePath, fileSystem) else {
      throw Error.noManifest(workspacePath: workspacePath)
    }

    guard var swiftPMToolchain = toolchainRegistry.swiftPMHost else {
      throw Error.cannotDetermineHostToolchain
    }

    self.packageRoot = packageRoot

    // FIXME: duplicating code from UserToolchain setup in swiftpm.
    var sdk: AbsolutePath? = nil
    var platformPath: AbsolutePath? = nil

    if case .darwin? = Platform.currentPlatform {
      if let path = try? Process.checkNonZeroExit(args:
        "/usr/bin/xcrun", "--show-sdk-path", "--sdk", "macosx")
      {
        sdk = try? AbsolutePath(validating: path.spm_chomp())
      }
      if let path = try? Process.checkNonZeroExit(args:
        "/usr/bin/xcrun", "--show-sdk-platform-path", "--sdk", "macosx")
      {
        platformPath = try? AbsolutePath(validating: path.spm_chomp())
      }
    }

    var extraSwiftFlags: [String] = []
    var extraClangFlags: [String] = []
    if let sdk = sdk {
      extraSwiftFlags += ["-sdk", sdk.pathString]
      extraClangFlags += ["-isysroot", sdk.pathString]
    }

    if let platformPath = platformPath {
      let flags = [
        "-F",
        platformPath.appending(components: "Developer", "Library", "Frameworks").pathString
      ]
      extraSwiftFlags += flags
      extraClangFlags += flags
    }

    swiftPMToolchain.sdkRoot = sdk
    swiftPMToolchain.extraCCFlags = extraClangFlags
    swiftPMToolchain.extraSwiftCFlags = extraSwiftFlags
    swiftPMToolchain.extraCPPFlags = extraClangFlags

    let buildPath: AbsolutePath = buildSetup.path ?? packageRoot.appending(component: ".build")

    self.workspace = Workspace(
      dataPath: buildPath,
      editablesPath: packageRoot.appending(component: "Packages"),
      pinsFile: packageRoot.appending(component: "Package.resolved"),
      manifestLoader: ManifestLoader(manifestResources: swiftPMToolchain),
      delegate: BuildSettingProviderWorkspaceDelegate(),
      fileSystem: fileSystem,
      skipUpdate: true)

    let triple = Triple.hostTriple

    let swiftPMConfiguration: PackageModel.BuildConfiguration
    switch buildSetup.configuration {
    case .debug:
      swiftPMConfiguration = .debug
    case .release:
      swiftPMConfiguration = .release
    }

    self.buildParameters = BuildParameters(
      dataPath: buildPath.appending(component: triple.tripleString),
      configuration: swiftPMConfiguration,
      toolchain: swiftPMToolchain,
      flags: buildSetup.flags)

    self.packageGraph = PackageGraph(rootPackages: [])

    try reloadPackage()
  }

  /// Creates a build system using the Swift Package Manager, if this workspace is a package.
  ///
  /// - Returns: nil if `workspacePath` is not part of a package or there is an error.
  public convenience init?(url: LanguageServerProtocol.URL,
                           toolchainRegistry: ToolchainRegistry,
                           buildSetup: BuildSetup)
  {
    do {
      try self.init(
        workspacePath: try AbsolutePath(validating: url.path),
        toolchainRegistry: toolchainRegistry,
        fileSystem: localFileSystem,
        buildSetup: buildSetup)
    } catch Error.noManifest(let path) {
      log("could not find manifest, or not a SwiftPM package: \(path)", level: .warning)
      return nil
    } catch {
      log("failed to create \(SwiftPMWorkspace.self): \(error)", level: .error)
      return nil
    }
  }
}

extension SwiftPMWorkspace {

  /// (Re-)load the package settings by parsing the manifest and resolving all the targets and
  /// dependencies.
  func reloadPackage() throws {

    let diags = DiagnosticsEngine(handlers: [{ diag in
      log(diag.localizedDescription, level: diag.behavior.asLogLevel)
    }])

    self.packageGraph = self.workspace.loadPackageGraph(
      root: PackageGraphRootInput(packages: [packageRoot]),
      diagnostics: diags)

    let plan = try BuildPlan(
      buildParameters: buildParameters,
      graph: packageGraph,
      diagnostics: diags,
      fileSystem: fileSystem)

    self.fileToTarget = [AbsolutePath: TargetBuildDescription](
      packageGraph.allTargets.flatMap { target in
        return target.sources.paths.compactMap {
          guard let td = plan.targetMap[target] else {
            return nil
          }
          return (key: $0, value: td)
        }
      }, uniquingKeysWith: { td, _ in
        // FIXME: is there  a preferred target?
        return td
    })

    self.sourceDirToTarget = [AbsolutePath: TargetBuildDescription](
      packageGraph.allTargets.compactMap { target in
        guard let td = plan.targetMap[target] else {
          return nil
        }
        return (key: target.sources.root, value: td)
      }, uniquingKeysWith: { td, _ in
        // FIXME: is there  a preferred target?
        return td
    })
  }
}

extension SwiftPMWorkspace: BuildSystem {

  public var buildPath: AbsolutePath {
    return buildParameters.buildPath
  }

  public var indexStorePath: AbsolutePath? {
    return buildParameters.indexStoreMode == .off ? nil : buildParameters.indexStore
  }

  public var indexDatabasePath: AbsolutePath? {
    return buildPath.appending(components: "index", "db")
  }

  public func settings(
    for url: LanguageServerProtocol.URL,
    _ language: Language) -> FileBuildSettings?
  {
    guard let path = try? AbsolutePath(validating: url.path) else {
      return nil
    }

    if let td = self.fileToTarget[path] {
      return settings(for: path, language, td)
    }

    if path.basename == "Package.swift" {
      return settings(forPackageManifest: path)
    }

    if path.extension == "h" {
      return settings(forHeader: path, language)
    }

    return nil
  }
}

extension SwiftPMWorkspace {

  // MARK: Implementation details

  /// Retrieve settings for the given file, which is part of a known target build description.
  public func settings(
    for path: AbsolutePath,
    _ language: Language,
    _ td: TargetBuildDescription) -> FileBuildSettings?
  {
    switch (td, language) {
    case (.swift(let td), .swift):
      return settings(forSwiftFile: path, td)
    case (.clang, .swift):
      return nil
    case (.clang(let td), _):
      return settings(forClangFile: path, language, td)
    default:
      return nil
    }
  }

  /// Retrieve settings for a package manifest (Package.swift).
  func settings(forPackageManifest path: AbsolutePath) -> FileBuildSettings? {
    for package in packageGraph.packages where path == package.manifest.path {
        let compilerArgs = workspace.interpreterFlags(for: package.path) + [path.pathString]
        return FileBuildSettings(
          preferredToolchain: nil,
          compilerArguments: compilerArgs
        )
    }
    return nil
  }

  /// Retrieve settings for a given header file.
  public func settings(forHeader path: AbsolutePath, _ language: Language) -> FileBuildSettings? {
    var dir = path.parentDirectory
    while !dir.isRoot {
      if let td = sourceDirToTarget[dir] {
        return settings(for: path, language, td)
      }
      dir = dir.parentDirectory
    }
    return nil
  }

  /// Retrieve settings for the given swift file, which is part of a known target build description.
  public func settings(
    forSwiftFile path: AbsolutePath,
    _ td: SwiftTargetBuildDescription) -> FileBuildSettings?
  {
    // FIXME: this is re-implementing llbuild's constructCommandLineArgs.
    var args: [String] = [
      "-module-name",
      td.target.c99name,
      "-incremental",
      "-emit-dependencies",
      "-emit-module",
      "-emit-module-path",
      buildPath.appending(component: "\(td.target.c99name).swiftmodule").pathString
      // -output-file-map <path>
    ]
    if td.target.type == .library || td.target.type == .test {
      args += ["-parse-as-library"]
    }
    args += ["-c"]
    args += td.target.sources.paths.map { $0.pathString }
    args += ["-I", buildPath.pathString]
    args += td.compileArguments()

    return FileBuildSettings(
      preferredToolchain: nil,
      compilerArguments: args,
      workingDirectory: workspacePath.pathString)
  }

  /// Retrieve settings for the given C-family language file, which is part of a known target build
  /// description.
  ///
  /// - Note: language must be a C-family language.
  public func settings(
    forClangFile path: AbsolutePath,
    _ language: Language,
    _ td: ClangTargetBuildDescription) -> FileBuildSettings?
  {
    // FIXME: this is re-implementing things from swiftpm's createClangCompileTarget

    var args = td.basicArguments()

    let compilePath = td.compilePaths().first(where: { $0.source == path })
    if let compilePath = compilePath {
      args += [
        "-MD",
        "-MT",
        "dependencies",
        "-MF",
        compilePath.deps.pathString,
      ]
    }

    switch language {
    case .c:
      if let std = td.clangTarget.cLanguageStandard {
        args += ["-std=\(std)"]
      }
    case .cpp:
      if let std = td.clangTarget.cxxLanguageStandard {
        args += ["-std=\(std)"]
      }
    default:
      break
    }

    if let compilePath = compilePath {
      args += [
        "-c",
        compilePath.source.pathString,
        "-o",
        compilePath.object.pathString
      ]
    } else if path.extension == "h" {
      args += ["-c"]
      if let xflag = language.xflagHeader {
        args += ["-x", xflag]
      }
      args += [path.pathString]
    } else {
      args += [
        "-c",
        path.pathString,
      ]
    }

    return FileBuildSettings(
      preferredToolchain: nil,
      compilerArguments: args,
      workingDirectory: workspacePath.pathString)
  }
}

/// A SwiftPM-compatible toolchain.
///
/// Appropriate for both building a pacakge (Build.Toolchain) and for loading the package manifest
/// (ManifestResourceProvider).
private struct SwiftPMToolchain: Build.Toolchain, ManifestResourceProvider {
  var swiftCompiler: AbsolutePath
  var clangCompiler: AbsolutePath
  var libDir: AbsolutePath
  var sdkRoot: AbsolutePath?
  var extraCCFlags: [String]
  var extraSwiftCFlags: [String]
  var extraCPPFlags: [String]
  var dynamicLibraryExtension: String

  func getClangCompiler() throws -> AbsolutePath { return clangCompiler }
}

extension ToolchainRegistry {

  /// A toolchain appropriate for using to load swiftpm manifests.
  fileprivate var swiftPMHost: SwiftPMToolchain? {
    var swiftc: AbsolutePath? = self.default?.swiftc
    var clang: AbsolutePath? = self.default?.clang
    if swiftc == nil {
      swiftc = toolchains.first(where: { $0.swiftc != nil })?.swiftc
    }
    if clang == nil {
      clang = toolchains.first(where: { $0.clang != nil })?.clang
    }

    if swiftc == nil || clang == nil {
      return nil
    }

    return SwiftPMToolchain(
      swiftCompiler: swiftc!,
      clangCompiler: clang!,
      libDir: swiftc!.parentDirectory.parentDirectory.appending(components: "lib", "swift", "pm"),
      sdkRoot: nil,
      extraCCFlags: [],
      extraSwiftCFlags: [],
      extraCPPFlags: [],
      dynamicLibraryExtension: Platform.currentPlatform?.dynamicLibraryExtension ?? "so"
    )
  }
}

/// Find a Swift Package root directory that contains the given path, if any.
private func findPackageDirectory(
  containing path: AbsolutePath,
  _ fileSystem: FileSystem) -> AbsolutePath? {
  var path = path
  while !fileSystem.isFile(path.appending(component: "Package.swift")) {
    if path.isRoot {
      return nil
    }
    path = path.parentDirectory
  }
  return path
}

public final class BuildSettingProviderWorkspaceDelegate: WorkspaceDelegate {
  public func packageGraphWillLoad(
    currentGraph: PackageGraph,
    dependencies: AnySequence<ManagedDependency>,
    missingURLs: Set<String>)
  {}

  public func fetchingWillBegin(repository: String) {}

  public func fetchingDidFinish(repository: String, diagnostic: Basic.Diagnostic?) {}

  public func cloning(repository: String) {}

  public func removing(repository: String) {}

  public func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {}
}

extension Basic.Diagnostic.Behavior {
  var asLogLevel: LogLevel {
    switch self {
    case .error: return .error
    case .warning: return .warning
    default: return .info
    }
  }
}
