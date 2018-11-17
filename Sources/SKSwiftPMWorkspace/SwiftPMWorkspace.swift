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
import Utility
import SKSupport
import Build
import PackageModel
import PackageGraph
import PackageLoading
import Workspace

public final class SwiftPMWorkspace {

  public enum Error: Swift.Error {

    /// We could not find an appropriate toolchain for swiftpm to use for manifest loading.
    case cannotDetermineHostToolchain
  }

  let workspacePath: AbsolutePath
  let packageRoot: AbsolutePath
  let packageGraph: PackageGraph
  let workspace: Workspace
  let buildParameters: BuildParameters
  let toolchainRegistry: ToolchainRegistry
  let fs: FileSystem

  var fileToTarget: [AbsolutePath: TargetBuildDescription] = [:]
  var sourceDirToTarget: [AbsolutePath: TargetBuildDescription] = [:]

  /// Creates a `BuildSettingsProvider` using the Swift Package Manager, if this workspace is part of a package.
  ///
  /// - returns: nil if `workspacePath` is not part of a package or there is an error.
  public convenience init?(url: LanguageServerProtocol.URL, toolchainRegistry: ToolchainRegistry) {
    do {
      try self.init(workspacePath: try AbsolutePath(validating: url.path), toolchainRegistry: toolchainRegistry, fileSystem: localFileSystem)
    } catch {
      log("failed to create \(SwiftPMWorkspace.self): \(error)", level: .error)
      return nil
    }
  }

  /// Creates a `BuildSettingsProvider` using the Swift Package Manager, if this workspace is part of a package.
  ///
  /// - returns: nil if `workspacePath` is not part of a package.
  /// - throws: If there is an error loading the package.
  public init?(workspacePath: AbsolutePath, toolchainRegistry: ToolchainRegistry, fileSystem: FileSystem) throws {

    self.workspacePath = workspacePath
    self.toolchainRegistry = toolchainRegistry
    guard let packageRoot = findPackageDirectory(containing: workspacePath, fileSystem: fileSystem) else {
      log("workspace not a swiftpm package \(workspacePath)")
      return nil
    }
    self.packageRoot = packageRoot
    self.fs = fileSystem

    guard var swiftpmToolchain = toolchainRegistry.swiftpmHost else {
      throw Error.cannotDetermineHostToolchain
    }

    // FIXME: duplicating code from UserToolchain setup in swiftpm.
    var sdkpath: AbsolutePath? = nil
    var platformPath: AbsolutePath? = nil
    let target: Triple = Triple.hostTriple
    if case .darwin? = Platform.currentPlatform {
      if let path = try? Process.checkNonZeroExit(args: "/usr/bin/xcrun", "--show-sdk-path", "--sdk", "macosx") {
        sdkpath = try? AbsolutePath(validating: path.spm_chomp())
      }
      if let path = try? Process.checkNonZeroExit(args: "/usr/bin/xcrun", "--show-sdk-platform-path", "--sdk", "macosx") {
        platformPath = try? AbsolutePath(validating: path.spm_chomp())
      }
    }

    var extraSwiftFlags = ["-target", target.tripleString]
    var extraClangFlags = ["-arch", target.arch.rawValue]
    if let sdkpath = sdkpath {
      extraSwiftFlags += [
        "-sdk", sdkpath.asString
      ]
      extraClangFlags += [
        "-isysroot", sdkpath.asString
      ]
    }

    if let platformPath = platformPath {
      let flags = [
        "-F",
        platformPath.appending(components: "Developer", "Library", "Frameworks").asString
      ]
      extraSwiftFlags += flags
      extraClangFlags += flags
    }

    swiftpmToolchain.sdkRoot = sdkpath
    swiftpmToolchain.extraCCFlags = extraClangFlags
    swiftpmToolchain.extraSwiftCFlags = extraSwiftFlags
    swiftpmToolchain.extraCPPFlags = extraClangFlags

    self.workspace = Workspace(
      dataPath: packageRoot.appending(component: ".build"),
      editablesPath: packageRoot.appending(component: "Packages"),
      pinsFile: packageRoot.appending(component: "Package.resolved"),
      manifestLoader: ManifestLoader(manifestResources: swiftpmToolchain),
      delegate: BuildSettingProviderWorkspaceDelegate(),
      fileSystem: fs,
      skipUpdate: true
    )

    // FIXME: make these configurable

    self.buildParameters = BuildParameters(
      dataPath: packageRoot.appending(component: ".build"),
      configuration: .debug,
      toolchain: swiftpmToolchain,
      flags: BuildFlags()
    )

    // FIXME: the rest of this should be done asynchronously.

    // FIXME: connect to logging?
    let diags = DiagnosticsEngine()

    self.packageGraph = self.workspace.loadPackageGraph(root: PackageGraphRootInput(packages: [packageRoot]), diagnostics: diags)

    let plan = try BuildPlan(buildParameters: buildParameters, graph: packageGraph, diagnostics: diags, fileSystem: self.fs)

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

extension SwiftPMWorkspace: ExternalWorkspace, BuildSettingsProvider {

  public var buildSystem: BuildSettingsProvider { return self }

  public var buildPath: AbsolutePath {
    return buildParameters.buildPath
  }

  public var indexStorePath: AbsolutePath? {
    return buildPath.appending(components: "index", "store")
  }

  public var indexDatabasePath: AbsolutePath? {
    return buildPath.appending(components: "index", "db")
  }

  public func settings(for url: LanguageServerProtocol.URL, language: Language) -> FileBuildSettings? {
    guard let path = try? AbsolutePath(validating: url.path) else {
      return nil
    }

    if let td = self.fileToTarget[path] {
      return settings(for: path, language: language, targetDescription: td)
    }

    if path.basename == "Package.swift" {
      return packageDescriptionSettings(path)
    }

    if path.extension == "h" {
      return settings(forHeader: path, language: language)
    }

    return nil
  }
}

extension SwiftPMWorkspace {

  // MARK: Implementation details

  public func settings(
    for path: AbsolutePath,
    language: Language,
    targetDescription td: TargetBuildDescription
  ) -> FileBuildSettings? {

    let buildPath = self.buildPath

    switch (td, language) {
    case (.swift(let td), .swift):
      // FIXME: this is re-implementing llbuild's constructCommandLineArgs.
      var args: [String] = [
        "-module-name",
        td.target.c99name,
        "-incremental",
        "-emit-dependencies",
        "-emit-module",
        "-emit-module-path",
        buildPath.appending(component: "\(td.target.c99name).swiftmodule").asString,
        // -output-file-map <path>
      ]
      if td.target.type == .library || td.target.type == .test {
        args += ["-parse-as-library"]
      }
      args += ["-c"]
      args += td.target.sources.paths.map{ $0.asString }
      args += ["-I", buildPath.asString]
      args += td.compileArguments()

      return FileBuildSettings(
        preferredToolchain: nil,
        compilerArguments: args,
        workingDirectory: workspacePath.asString
      )

    case (.clang(_), .swift):
      return nil

    case (.clang(let td), _):
      // FIXME: this is re-implementing things from swiftpm's createClangCompileTarget

      let compilePath = td.compilePaths().first(where: { $0.source == path })

      var args = td.basicArguments()

      if let compilePath = compilePath {
        args += [
          "-MD",
          "-MT",
          "dependencies",
          "-MF",
          compilePath.deps.asString,
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
          compilePath.source.asString,
          "-o",
          compilePath.object.asString
        ]
      } else if path.extension == "h" {
        args += ["-c"]
        if let xflag = language.xflagHeader {
          args += ["-x", xflag]
        }
        args += [path.asString]
      } else {
        args += [
          "-c",
          path.asString,
        ]
      }

      return FileBuildSettings(
        preferredToolchain: nil,
        compilerArguments: args,
        workingDirectory: workspacePath.asString
      )

    default:
      return nil
    }
  }

  func packageDescriptionSettings(_ path: AbsolutePath) -> FileBuildSettings? {
    for package in packageGraph.packages {
      if path == package.manifest.path {
        return FileBuildSettings(
          preferredToolchain: nil,
          compilerArguments:
            workspace.interpreterFlags(for: package.path) + [path.asString])
      }
    }
    return nil
  }

  public func settings(forHeader path: AbsolutePath, language: Language) -> FileBuildSettings? {
    var dir = path.parentDirectory
    while !dir.isRoot {
      if let td = sourceDirToTarget[dir] {
        return settings(for: path, language: language, targetDescription: td)
      }
      dir = dir.parentDirectory
    }
    return nil
  }
}

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
  fileprivate var swiftpmHost: SwiftPMToolchain? {
    guard let base = self.default, base.swiftc != nil else {
      return nil
    }

    guard let clang = base.clang ?? toolchains.values.first(where: { $0.clang != nil })?.clang else { return nil }

    return SwiftPMToolchain(
      swiftCompiler: base.swiftc!,
      clangCompiler: clang,
      libDir: base.swiftc!.parentDirectory.parentDirectory.appending(components: "lib", "swift", "pm"),
      sdkRoot: nil,
      extraCCFlags: [],
      extraSwiftCFlags: [],
      extraCPPFlags: [],
      dynamicLibraryExtension: {
        if case .darwin? = Platform.currentPlatform {
          return "dylib"
        } else {
          return "so"
        }
      }()
    )
  }
}

private func findPackageDirectory(containing path: AbsolutePath, fileSystem fs: FileSystem) -> AbsolutePath? {
  var path = path
  while !fs.isFile(path.appending(component: "Package.swift")) {
    if path.isRoot {
      return nil
    }
    path = path.parentDirectory
  }
  return path
}

public final class BuildSettingProviderWorkspaceDelegate: WorkspaceDelegate {
  public func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>) {
  }

  public func fetchingWillBegin(repository: String) {
  }

  public func fetchingDidFinish(repository: String, diagnostic: Basic.Diagnostic?) {
  }

  public func cloning(repository: String) {
  }

  public func removing(repository: String) {
  }

  public func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
  }
}
