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

import Dispatch
import Foundation
import SKSupport

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import func TSCBasic.getEnvSearchPaths
import var TSCBasic.localFileSystem

/// Set of known toolchains.
///
/// Most users will use the `shared` ToolchainRegistry, although it's possible to create more. A
/// ToolchainRegistry is usually initialized by performing a search of predetermined paths,
/// e.g. `ToolchainRegistry(searchPaths: ToolchainRegistry.defaultSearchPaths)`.
public final actor ToolchainRegistry {

  /// The toolchains, in the order they were registered.
  public private(set) var toolchains: [Toolchain] = []

  /// The toolchains indexed by their identifier.
  ///
  /// Multiple toolchains may exist for the XcodeDefault toolchain identifier.
  private var toolchainsByIdentifier: [String: [Toolchain]] = [:]

  /// The toolchains indexed by their path.
  ///
  /// Note: Not all toolchains have a path.
  private var toolchainsByPath: [AbsolutePath: Toolchain] = [:]

  /// The default toolchain.
  private var _default: Toolchain? = nil

  /// The currently selected toolchain identifier on Darwin.
  public lazy var darwinToolchainOverride: String? = {
    if let id = ProcessEnv.vars["TOOLCHAINS"], !id.isEmpty, id != "default" {
      return id
    }
    return nil
  }()

  /// Creates an empty toolchain registry.
  private init() {}

  /// A toolchain registry used for testing that scans for toolchains based on environment variables and Xcode
  /// installations but not next to the `sourcekit-lsp` binary because there is no `sourcekit-lsp` binary during
  /// testing.
  @_spi(Testing)
  public static var forTesting: ToolchainRegistry {
    get async {
      await ToolchainRegistry(localFileSystem)
    }
  }

  /// A toolchain registry that doesn't contain any toolchains.
  @_spi(Testing)
  public static var empty: ToolchainRegistry { ToolchainRegistry() }

  /// Creates a toolchain registry populated by scanning for toolchains according to the given paths
  /// and variables.
  ///
  /// If called with the default values, creates a toolchain registry that searches:
  /// * env SOURCEKIT_TOOLCHAIN_PATH <-- will override default toolchain
  /// * installPath <-- will override default toolchain
  /// * (Darwin) The currently selected Xcode
  /// * (Darwin) [~]/Library/Developer/Toolchains
  /// * env SOURCEKIT_PATH, PATH
  ///
  /// This is equivalent to
  /// ```
  /// let tr = ToolchainRegistry()
  /// tr.scanForToolchains()
  /// ```
  public init(
    installPath: AbsolutePath? = nil,
    _ fileSystem: FileSystem
  ) async {
    scanForToolchains(installPath: installPath, fileSystem)
  }
}

extension ToolchainRegistry {

  /// The default toolchain.
  ///
  /// On Darwin, this is typically the toolchain with the identifier `darwinToolchainIdentifier`,
  /// i.e. the default toolchain of the active Xcode. Otherwise it is the first toolchain that was
  /// registered, if any.
  ///
  /// The default toolchain must be only of the registered toolchains.
  public var `default`: Toolchain? {
    get {
      if _default == nil {
        if let tc = toolchainsByIdentifier[darwinToolchainIdentifier]?.first {
          _default = tc
        } else {
          _default = toolchains.first
        }
      }
      return _default
    }

    set {
      guard let toolchain = newValue else {
        _default = nil
        return
      }
      precondition(
        toolchains.contains { $0 === toolchain },
        "default toolchain must be registered first"
      )
      _default = toolchain
    }
  }

  /// The standard default toolchain identifier on Darwin.
  @_spi(Testing)
  public static let darwinDefaultToolchainIdentifier: String = "com.apple.dt.toolchain.XcodeDefault"

  /// The current toolchain identifier on Darwin, which is either specified byt the `TOOLCHAINS`
  /// environment variable, or defaults to `darwinDefaultToolchainIdentifier`.
  ///
  /// The value of `default.identifier` may be different if the default toolchain has been
  /// explicitly overridden in code, or if there is no toolchain with this identifier.
  @_spi(Testing)
  public var darwinToolchainIdentifier: String {
    return darwinToolchainOverride ?? ToolchainRegistry.darwinDefaultToolchainIdentifier
  }
}

/// Inspecting internal state for testing purposes.
extension ToolchainRegistry {
  @_spi(Testing)
  public func toolchains(identifier: String) -> [Toolchain] {
    return toolchainsByIdentifier[identifier] ?? []
  }

  @_spi(Testing)
  public func toolchain(identifier: String) -> Toolchain? {
    return toolchains(identifier: identifier).first
  }

  @_spi(Testing)
  public func toolchain(path: AbsolutePath) -> Toolchain? {
    return toolchainsByPath[path]
  }
}

extension ToolchainRegistry {
  public enum Error: Swift.Error {

    /// There is already a toolchain with the given identifier.
    case duplicateToolchainIdentifier

    /// There is already a toolchain with the given path.
    case duplicateToolchainPath

    /// The toolchain does not exist, or has no tools.
    case invalidToolchain
  }

  /// Register the given toolchain.
  ///
  /// - parameter toolchain: The new toolchain to register.
  /// - throws: If `toolchain.identifier` has already been seen.
  @_spi(Testing)
  public func registerToolchain(_ toolchain: Toolchain) throws {
    // Non-XcodeDefault toolchain: disallow all duplicates.
    if toolchain.identifier != ToolchainRegistry.darwinDefaultToolchainIdentifier {
      guard toolchainsByIdentifier[toolchain.identifier] == nil else {
        throw Error.duplicateToolchainIdentifier
      }
    }

    // Toolchain should always be unique by path if it is present.
    if let path = toolchain.path {
      guard toolchainsByPath[path] == nil else {
        throw Error.duplicateToolchainPath
      }
      toolchainsByPath[path] = toolchain
    }

    toolchainsByIdentifier[toolchain.identifier, default: []].append(toolchain)
    toolchains.append(toolchain)
  }

  /// Register the toolchain at the given path.
  ///
  /// - parameter path: The path to search for a toolchain to register.
  /// - returns: The toolchain, if any.
  /// - throws: If there is no toolchain at the given `path`, or if `toolchain.identifier` has
  ///   already been seen.
  public func registerToolchain(
    _ path: AbsolutePath,
    _ fileSystem: FileSystem = localFileSystem
  ) throws -> Toolchain {
    guard let toolchain = Toolchain(path, fileSystem) else {
      throw Error.invalidToolchain
    }
    try registerToolchain(toolchain)
    return toolchain
  }
}

extension ToolchainRegistry {

  /// Scans for toolchains according to the given paths and variables.
  ///
  /// If called with the default values, creates a toolchain registry that searches:
  /// * env SOURCEKIT_TOOLCHAIN_PATH <-- will override default toolchain
  /// * installPath <-- will override default toolchain
  /// * (Darwin) The currently selected Xcode
  /// * (Darwin) [~]/Library/Developer/Toolchains
  /// * env SOURCEKIT_PATH, PATH (or Path)
  @_spi(Testing)
  public func scanForToolchains(
    installPath: AbsolutePath? = nil,
    environmentVariables: [String] = ["SOURCEKIT_TOOLCHAIN_PATH"],
    xcodes: [AbsolutePath] = [currentXcodeDeveloperPath].compactMap({ $0 }),
    xctoolchainSearchPaths: [AbsolutePath]? = nil,
    pathVariables: [String] = ["SOURCEKIT_PATH", "PATH", "Path"],
    _ fileSystem: FileSystem
  ) {
    let xctoolchainSearchPaths =
      try! xctoolchainSearchPaths ?? [
        AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains"),
        AbsolutePath(validating: "/Library/Developer/Toolchains"),
      ]

    scanForToolchains(environmentVariables: environmentVariables, setDefault: true, fileSystem)
    if let installPath = installPath,
      let toolchain = try? registerToolchain(installPath, fileSystem),
      _default == nil
    {
      _default = toolchain
    }
    for xcode in xcodes {
      scanForToolchains(xcode: xcode, fileSystem)
    }
    for xctoolchainSearchPath in xctoolchainSearchPaths {
      scanForToolchains(xctoolchainSearchPath: xctoolchainSearchPath, fileSystem)
    }
    scanForToolchains(pathVariables: pathVariables, fileSystem)
  }

  /// Scan for toolchains in the paths given by `environmentVariables` and possibly override the
  /// default toolchain with the first one found.
  ///
  /// - parameters:
  ///   - environmentVariables: A list of environment variable names to search for toolchain paths.
  ///   - setDefault: If true, the first toolchain found will be set as the default.
  @_spi(Testing)
  public func scanForToolchains(
    environmentVariables: [String],
    setDefault: Bool,
    _ fileSystem: FileSystem = localFileSystem
  ) {
    var shouldSetDefault = setDefault
    for envVar in environmentVariables {
      if let pathStr = ProcessEnv.vars[envVar],
        let path = try? AbsolutePath(validating: pathStr),
        let toolchain = try? registerToolchain(path, fileSystem),
        shouldSetDefault
      {
        shouldSetDefault = false
        _default = toolchain
      }
    }
  }

  /// Scan for toolchains by the given PATH-like environment variables.
  ///
  /// - parameters:
  ///   - pathVariables: A list of PATH-like environment variable names to search.
  ///   - setDefault: If true, the first toolchain found will be set as the default.
  @_spi(Testing)
  public func scanForToolchains(pathVariables: [String], _ fileSystem: FileSystem = localFileSystem) {
    pathVariables.lazy.flatMap { envVar in
      getEnvSearchPaths(pathString: ProcessEnv.vars[envVar], currentWorkingDirectory: nil)
    }
    .forEach { path in
      _ = try? registerToolchain(path, fileSystem)
    }
  }

  /// Scan for toolchains in the given Xcode, which should be given as a path to either the
  /// application (e.g. "Xcode.app") or the application's Developer directory.
  ///
  /// - parameter xcode: The path to Xcode.app or Xcode.app/Contents/Developer.
  @_spi(Testing)
  public func scanForToolchains(xcode: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) {
    var path = xcode
    if path.extension == "app" {
      path = path.appending(components: "Contents", "Developer")
    }
    scanForToolchains(xctoolchainSearchPath: path.appending(component: "Toolchains"), fileSystem)
  }

  /// Scan for `xctoolchain` directories in the given search path.
  ///
  /// - parameter toolchains: Directory containing xctoolchains, e.g. /Library/Developer/Toolchains
  @_spi(Testing)
  public func scanForToolchains(
    xctoolchainSearchPath searchPath: AbsolutePath,
    _ fileSystem: FileSystem = localFileSystem
  ) {
    guard let direntries = try? fileSystem.getDirectoryContents(searchPath) else { return }
    for name in direntries {
      let path = searchPath.appending(component: name)
      if path.extension == "xctoolchain" {
        _ = try? registerToolchain(path, fileSystem)
      }
    }
  }

  /// The path of the current Xcode.app/Contents/Developer.
  @_spi(Testing)
  public static var currentXcodeDeveloperPath: AbsolutePath? {
    guard let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p") else { return nil }
    return try? AbsolutePath(validating: str.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
