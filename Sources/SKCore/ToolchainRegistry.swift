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
import struct TSCBasic.ProcessEnvironmentKey
import func TSCBasic.getEnvSearchPaths
import var TSCBasic.localFileSystem

/// Set of known toolchains.
///
/// Most users will use the `shared` ToolchainRegistry, although it's possible to create more. A
/// ToolchainRegistry is usually initialized by performing a search of predetermined paths,
/// e.g. `ToolchainRegistry(searchPaths: ToolchainRegistry.defaultSearchPaths)`.
public final actor ToolchainRegistry {

  /// The toolchains, in the order they were registered.
  public let toolchains: [Toolchain]

  /// The toolchains indexed by their identifier.
  ///
  /// Multiple toolchains may exist for the XcodeDefault toolchain identifier.
  private let toolchainsByIdentifier: [String: [Toolchain]]

  /// The toolchains indexed by their path.
  ///
  /// Note: Not all toolchains have a path.
  private let toolchainsByPath: [AbsolutePath: Toolchain]

  /// The currently selected toolchain identifier on Darwin.
  public let darwinToolchainOverride: String?

  /// Creates a toolchain registry from a list of toolchains.
  ///
  /// - Parameters:
  ///   - toolchains: The toolchains that should be stored in the registry.
  ///   - darwinToolchainOverride: The contents of the `TOOLCHAINS` environment
  ///     variable, which picks the default toolchain.
  @_spi(Testing)
  public init(
    toolchains toolchainsParam: [Toolchain],
    darwinToolchainOverride: String?
  ) {
    var toolchains: [Toolchain] = []
    var toolchainsByIdentifier: [String: [Toolchain]] = [:]
    var toolchainsByPath: [AbsolutePath: Toolchain] = [:]
    for toolchain in toolchainsParam {
      // Non-XcodeDefault toolchain: disallow all duplicates.
      if toolchain.identifier != ToolchainRegistry.darwinDefaultToolchainIdentifier {
        guard toolchainsByIdentifier[toolchain.identifier] == nil else {
          continue
        }
      }

      // Toolchain should always be unique by path if it is present.
      if let path = toolchain.path {
        guard toolchainsByPath[path] == nil else {
          continue
        }
        toolchainsByPath[path] = toolchain
      }

      toolchainsByIdentifier[toolchain.identifier, default: []].append(toolchain)
      toolchains.append(toolchain)
    }

    self.toolchains = toolchains
    self.toolchainsByIdentifier = toolchainsByIdentifier
    self.toolchainsByPath = toolchainsByPath

    if let darwinToolchainOverride, !darwinToolchainOverride.isEmpty, darwinToolchainOverride != "default" {
      self.darwinToolchainOverride = darwinToolchainOverride
    } else {
      self.darwinToolchainOverride = nil
    }
  }

  /// A toolchain registry used for testing that scans for toolchains based on environment variables and Xcode
  /// installations but not next to the `sourcekit-lsp` binary because there is no `sourcekit-lsp` binary during
  /// testing.
  @_spi(Testing)
  public static var forTesting: ToolchainRegistry {
    ToolchainRegistry(localFileSystem)
  }

  /// Creates a toolchain registry populated by scanning for toolchains according to the given paths
  /// and variables.
  ///
  /// If called with the default values, creates a toolchain registry that searches:
  /// * `env SOURCEKIT_TOOLCHAIN_PATH` <-- will override default toolchain
  /// * `installPath` <-- will override default toolchain
  /// * (Darwin) The currently selected Xcode
  /// * (Darwin) `[~]/Library/Developer/Toolchains`
  /// * `env SOURCEKIT_PATH, PATH`
  public init(
    installPath: AbsolutePath? = nil,
    environmentVariables: [ProcessEnvironmentKey] = ["SOURCEKIT_TOOLCHAIN_PATH"],
    xcodes: [AbsolutePath] = [_currentXcodeDeveloperPath].compactMap({ $0 }),
    darwinToolchainOverride: String? = ProcessEnv.block["TOOLCHAINS"],
    _ fileSystem: FileSystem = localFileSystem
  ) {
    // The paths at which we have found toolchains
    var toolchainPaths: [AbsolutePath] = []

    // Scan for toolchains in the paths given by `environmentVariables`.
    for envVar in environmentVariables {
      if let pathStr = ProcessEnv.block[envVar], let path = try? AbsolutePath(validating: pathStr) {
        toolchainPaths.append(path)
      }
    }

    // Search for toolchains relative to the path at which sourcekit-lsp is installed.
    if let installPath = installPath {
      toolchainPaths.append(installPath)
    }

    // Search for toolchains in the Xcode developer directories and global toolchain install paths
    let toolchainSearchPaths =
      xcodes.map {
        if $0.extension == "app" {
          return $0.appending(components: "Contents", "Developer", "Toolchains")
        } else {
          return $0.appending(component: "Toolchains")
        }
      } + [
        try! AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains"),
        try! AbsolutePath(validating: "/Library/Developer/Toolchains"),
      ]

    for xctoolchainSearchPath in toolchainSearchPaths {
      guard let direntries = try? fileSystem.getDirectoryContents(xctoolchainSearchPath) else {
        continue
      }
      for name in direntries {
        let path = xctoolchainSearchPath.appending(component: name)
        if path.extension == "xctoolchain" {
          toolchainPaths.append(path)
        }
      }
    }

    // Scan for toolchains by the given PATH-like environment variables.
    for envVar: ProcessEnvironmentKey in ["SOURCEKIT_PATH", "PATH", "Path"] {
      for path in getEnvSearchPaths(pathString: ProcessEnv.block[envVar], currentWorkingDirectory: nil) {
        toolchainPaths.append(path)
      }
    }

    self.init(
      toolchains: toolchainPaths.compactMap { Toolchain($0, fileSystem) },
      darwinToolchainOverride: darwinToolchainOverride
    )
  }

  /// The default toolchain.
  ///
  /// On Darwin, this is typically the toolchain with the identifier `darwinToolchainIdentifier`,
  /// i.e. the default toolchain of the active Xcode. Otherwise it is the first toolchain that was
  /// registered, if any.
  ///
  /// The default toolchain must be only of the registered toolchains.
  public var `default`: Toolchain? {
    get {
      if let tc = toolchainsByIdentifier[darwinToolchainIdentifier]?.first {
        return tc
      } else {
        return toolchains.first
      }
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
  /// The path of the current Xcode.app/Contents/Developer.
  public static var _currentXcodeDeveloperPath: AbsolutePath? {
    guard let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p") else { return nil }
    return try? AbsolutePath(validating: str.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
