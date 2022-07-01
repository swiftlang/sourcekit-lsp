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

import SKSupport
import TSCBasic
import Dispatch
import Foundation

/// Set of known toolchains.
///
/// Most users will use the `shared` ToolchainRegistry, although it's possible to create more. A
/// ToolchainRegistry is usually initialized by performing a search of predetermined paths,
/// e.g. `ToolchainRegistry(searchPaths: ToolchainRegistry.defaultSearchPaths)`.
public final class ToolchainRegistry {

  /// The toolchains, in the order they were registered. **Must be accessed on `queue`**.
  var _toolchains: [Toolchain] = []

  /// The toolchains indexed by their identifier. **Must be accessed on `queue`**.
  /// Multiple toolchains may exist for the XcodeDefault toolchain identifier.
  var toolchainsByIdentifier: [String: [Toolchain]] = [:]

  /// The toolchains indexed by their path. **Must be accessed on `queue`**.
  /// Note: Not all toolchains have a path.
  var toolchainsByPath: [AbsolutePath: Toolchain] = [:]

  /// The default toolchain. **Must be accessed on `queue`**.
  var _default: Toolchain? = nil

  /// Mutex for registering and accessing toolchains.
  var queue: DispatchQueue = DispatchQueue(label: "toolchain-registry-queue")

  /// The currently selected toolchain identifier on Darwin.
  public lazy var darwinToolchainOverride: String? = {
    if let id = ProcessEnv.vars["TOOLCHAINS"], !id.isEmpty, id != "default" {
      return id
    }
    return nil
  }()

  /// Creates an empty toolchain registry.
  public init() {}
}

extension ToolchainRegistry {

  /// The global toolchain registry, initially populated by scanning for toolchains.
  ///
  /// Scans for toolchains in:
  /// * env SOURCEKIT_TOOLCHAIN_PATH <-- will override default toolchain
  /// * (Darwin) The currently selected Xcode
  /// * (Darwin) [~]/Library/Developer/Toolchains
  /// * env SOURCEKIT_PATH, PATH
  public static var shared: ToolchainRegistry = ToolchainRegistry(localFileSystem)

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
  public convenience init(installPath: AbsolutePath? = nil, _ fileSystem: FileSystem) {
    self.init()
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
      return queue.sync {
        if _default == nil {
          if let tc = toolchainsByIdentifier[darwinToolchainIdentifier]?.first {
            _default = tc
          } else {
            _default = _toolchains.first
          }
        }
        return _default
      }
    }

    set {
      queue.sync {
        guard let toolchain = newValue else {
          _default = nil
          return
        }
        precondition(_toolchains.contains { $0 === toolchain },
                     "default toolchain must be registered first")
        _default = toolchain
      }
    }
  }

  /// The standard default toolchain identifier on Darwin.
  public static let darwinDefaultToolchainIdentifier: String = "com.apple.dt.toolchain.XcodeDefault"

  /// The current toolchain identifier on Darwin, which is either specified byt the `TOOLCHAINS`
  /// environment variable, or defaults to `darwinDefaultToolchainIdentifier`.
  ///
  /// The value of `default.identifier` may be different if the default toolchain has been
  /// explicitly overridden in code, or if there is no toolchain with this identifier.
  public var darwinToolchainIdentifier: String {
    return darwinToolchainOverride ?? ToolchainRegistry.darwinDefaultToolchainIdentifier
  }

  /// All toolchains, in the order they were added.
  public var toolchains: [Toolchain] {
    return queue.sync { _toolchains }
  }

  public func toolchains(identifier: String) -> [Toolchain] {
    return queue.sync { toolchainsByIdentifier[identifier] ?? [] }
  }

  public func toolchain(identifier: String) -> Toolchain? {
    return toolchains(identifier: identifier).first
  }

  public func toolchain(path: AbsolutePath) -> Toolchain? {
    return queue.sync { toolchainsByPath[path] }
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
  public func registerToolchain(_ toolchain: Toolchain) throws {
    try queue.sync { try _registerToolchain(toolchain) }
  }

  func _registerToolchain(_ toolchain: Toolchain) throws {
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

    var toolchains = toolchainsByIdentifier[toolchain.identifier] ?? []
    toolchains.append(toolchain)
    toolchainsByIdentifier[toolchain.identifier] = toolchains
    _toolchains.append(toolchain)
  }

  /// Register the toolchain at the given path.
  ///
  /// - parameter path: The path to search for a toolchain to register.
  /// - returns: The toolchain, if any.
  /// - throws: If there is no toolchain at the given `path`, or if `toolchain.identifier` has
  ///   already been seen.
  public func registerToolchain(
    _ path: AbsolutePath,
    _ fileSystem: FileSystem = localFileSystem) throws -> Toolchain
  {
    return try queue.sync { try _registerToolchain(path, fileSystem) }
  }

  func _registerToolchain(_ path: AbsolutePath, _ fileSystem: FileSystem) throws -> Toolchain {
    if let toolchain = Toolchain(path, fileSystem) {
      try _registerToolchain(toolchain)
      return toolchain
    } else {
      throw Error.invalidToolchain
    }
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
  public func scanForToolchains(
    installPath: AbsolutePath? = nil,
    environmentVariables: [String] = ["SOURCEKIT_TOOLCHAIN_PATH"],
    xcodes: [AbsolutePath] = [currentXcodeDeveloperPath].compactMap({$0}),
    xctoolchainSearchPaths: [AbsolutePath] = [
      AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains"),
      AbsolutePath("/Library/Developer/Toolchains"),
    ],
    pathVariables: [String] = ["SOURCEKIT_PATH", "PATH", "Path"],
    _ fileSystem: FileSystem)
  {
    queue.sync {
      _scanForToolchains(environmentVariables: environmentVariables, setDefault: true, fileSystem)
      if let installPath = installPath,
        let toolchain = try? _registerToolchain(installPath, fileSystem),
        _default == nil
      {
        _default = toolchain
      }
      xcodes.forEach { _scanForToolchains(xcode: $0, fileSystem) }
      xctoolchainSearchPaths.forEach { _scanForToolchains(xctoolchainSearchPath: $0, fileSystem) }
      _scanForToolchains(pathVariables: pathVariables, fileSystem)
    }
  }

  /// Scan for toolchains in the paths given by `environmentVariables` and possibly override the
  /// default toolchain with the first one found.
  ///
  /// - parameters:
  ///   - environmentVariables: A list of environment variable names to search for toolchain paths.
  ///   - setDefault: If true, the first toolchain found will be set as the default.
  public func scanForToolchains(
    environmentVariables: [String],
    setDefault: Bool,
    _ fileSystem: FileSystem = localFileSystem)
  {
    queue.sync {
      _scanForToolchains(
        environmentVariables: environmentVariables,
        setDefault: setDefault,
        fileSystem)
    }
  }

  func _scanForToolchains(
    environmentVariables: [String],
    setDefault: Bool,
    _ fileSystem: FileSystem)
  {
    var shouldSetDefault = setDefault
    for envVar in environmentVariables {
      if let pathStr = ProcessEnv.vars[envVar],
         let path = try? AbsolutePath(validating: pathStr),
         let toolchain = try? _registerToolchain(path, fileSystem),
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
  public
  func scanForToolchains(pathVariables: [String], _ fileSystem: FileSystem = localFileSystem) {
    queue.sync { _scanForToolchains(pathVariables: pathVariables, fileSystem) }
  }

  func _scanForToolchains(pathVariables: [String], _ fileSystem: FileSystem) {
    pathVariables.lazy.flatMap { envVar in
      getEnvSearchPaths(pathString: ProcessEnv.vars[envVar], currentWorkingDirectory: nil)
    }
    .forEach { path in
      _ = try? _registerToolchain(path, fileSystem)
    }
  }

  /// Scan for toolchains in the given Xcode, which should be given as a path to either the
  /// application (e.g. "Xcode.app") or the application's Developer directory.
  ///
  /// - parameter xcode: The path to Xcode.app or Xcode.app/Contents/Developer.
  public func scanForToolchains(xcode: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) {
    queue.sync { _scanForToolchains(xcode: xcode, fileSystem) }
  }

  func _scanForToolchains(xcode: AbsolutePath, _ fileSystem: FileSystem) {
    var path = xcode
    if path.extension == "app" {
      path = path.appending(components: "Contents", "Developer")
    }
    _scanForToolchains(xctoolchainSearchPath: path.appending(component: "Toolchains"), fileSystem)
  }

  /// Scan for `xctoolchain` directories in the given search path.
  ///
  /// - parameter toolchains: Directory containing xctoolchains, e.g. /Library/Developer/Toolchains
  public func scanForToolchains(
    xctoolchainSearchPath searchPath: AbsolutePath,
    _ fileSystem: FileSystem = localFileSystem)
  {
    queue.sync { _scanForToolchains(xctoolchainSearchPath: searchPath, fileSystem) }
  }

  func _scanForToolchains(xctoolchainSearchPath searchPath: AbsolutePath, _ fileSystem: FileSystem){
    guard let direntries = try? fileSystem.getDirectoryContents(searchPath) else { return }
    for name in direntries {
      let path = searchPath.appending(component: name)
      if path.extension == "xctoolchain" {
        _ = try? _registerToolchain(path, fileSystem)
      }
    }
  }

  /// The path of the current Xcode.app/Contents/Developer.
  public static var currentXcodeDeveloperPath: AbsolutePath? {
    if let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p"),
       let path = try? AbsolutePath(validating: str.spm_chomp())
    {
      return path
    }
    return nil
  }
}
