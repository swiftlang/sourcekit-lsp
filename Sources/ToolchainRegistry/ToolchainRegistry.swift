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
package import Foundation
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions
import TSCExtensions

package import class TSCBasic.Process
package import enum TSCBasic.ProcessEnv
package import struct TSCBasic.ProcessEnvironmentKey
package import func TSCBasic.getEnvSearchPaths

/// Caches xcrun resolutions for /usr/bin compiler shims.
/// Uses background tasks since ToolchainRegistry methods are synchronous.
private final class XcrunResolverCache: Sendable {
  private let cache: ThreadSafeBox<[URL: URL?]> = ThreadSafeBox(initialValue: [:])
  private let inflightTasks: ThreadSafeBox<[URL: Task<URL?, Never>]> = ThreadSafeBox(initialValue: [:])

  func getCached(_ compiler: URL) -> URL? {
    return cache.withLock { $0[compiler] ?? nil }
  }

  func triggerResolution(_ compiler: URL) {
    let hasTask = inflightTasks.withLock { $0[compiler] != nil }
    if hasTask { return }

    let task = Task {
      let resolved = await orLog("Resolving /usr/bin compiler via xcrun") {
        let result = try await Process.run(
          arguments: ["xcrun", "-f", compiler.lastPathComponent],
          workingDirectory: nil
        )
        let path = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(at: url) ? url : nil
      }
      self.cache.withLock { $0[compiler] = resolved }
      _ = self.inflightTasks.withLock { $0.removeValue(forKey: compiler) }
      return resolved
    }
    inflightTasks.withLock { $0[compiler] = task }
  }

  func clearCache() {
    cache.withLock { $0.removeAll() }
  }
}

/// Set of known toolchains.
///
/// Most users will use the `shared` ToolchainRegistry, although it's possible to create more. A
/// ToolchainRegistry is usually initialized by performing a search of predetermined paths,
/// e.g. `ToolchainRegistry(searchPaths: ToolchainRegistry.defaultSearchPaths)`.
package final actor ToolchainRegistry {
  /// The reason why a toolchain got added to the registry.
  ///
  /// Used to determine the default toolchain. For example, a toolchain discoverd by the `SOURCEKIT_TOOLCHAIN_PATH`
  /// environment variable always takes precedence.
  private enum ToolchainRegisterReason: Comparable {
    /// The toolchain was found because of the `SOURCEKIT_TOOLCHAIN_PATH` environment variable (or equivalent if
    /// overridden in `ToolchainRegistry.init`).
    case sourcekitToolchainEnvironmentVariable

    /// The toolchain was found relative to the location where sourcekit-lsp is installed.
    case relativeToInstallPath

    /// The toolchain was found in an Xcode installation
    case xcode

    /// The toolchain was found relative to the `SOURCEKIT_PATH` or `PATH` environment variables.
    case pathEnvironmentVariable
  }

  /// The toolchains and the reasons why they were added to the registry.s
  private let toolchainsAndReasons: [(toolchain: Toolchain, reason: ToolchainRegisterReason)]

  /// The toolchains, in the order they were registered.
  package var toolchains: [Toolchain] {
    return toolchainsAndReasons.map(\.toolchain)
  }

  /// The toolchains indexed by their identifier.
  ///
  /// Multiple toolchains may exist for the XcodeDefault toolchain identifier.
  private let toolchainsByIdentifier: [String: [Toolchain]]

  /// The toolchains indexed by their path.
  private var toolchainsByPath: [URL: Toolchain]

  /// Map from compiler paths (`clang`, `swift`, `swiftc`) mapping to the toolchain that contained them.
  ///
  /// This allows us to find the toolchain that should be used for semantic functionality based on which compiler it is
  /// built with in the `compile_commands.json`.
  private var toolchainsByCompiler: [URL: Toolchain]

  /// Cache for xcrun resolution of /usr/bin compiler shims.
  private let xcrunResolverCache = XcrunResolverCache()

  /// The currently selected toolchain identifier on Darwin.
  package let darwinToolchainOverride: String?

  /// Create a toolchain registry with a pre-defined list of toolchains.
  ///
  /// For testing purposes only.
  package init(toolchains: [Toolchain]) {
    self.init(
      toolchainsAndReasons: toolchains.map { ($0, .xcode) },
      darwinToolchainOverride: nil
    )
  }

  /// Creates a toolchain registry from a list of toolchains.
  ///
  /// - Parameters:
  ///   - toolchainsAndReasons: The toolchains that should be stored in the registry and why they should be added.
  ///   - darwinToolchainOverride: The contents of the `TOOLCHAINS` environment
  ///     variable, which picks the default toolchain.
  private init(
    toolchainsAndReasons toolchainsAndReasonsParam: [(toolchain: Toolchain, reason: ToolchainRegisterReason)],
    darwinToolchainOverride: String?
  ) {
    var toolchainsAndReasons: [(toolchain: Toolchain, reason: ToolchainRegisterReason)] = []
    var toolchainsByIdentifier: [String: [Toolchain]] = [:]
    var toolchainsByPath: [URL: Toolchain] = [:]
    var toolchainsByCompiler: [URL: Toolchain] = [:]
    for (toolchain, reason) in toolchainsAndReasonsParam {
      // Toolchain should always be unique by path. It isn't particularly useful to log if we already have a toolchain
      // though, as we could have just found toolchains through symlinks (this is actually quite normal - eg. OSS
      // toolchains add a `swift-latest.xctoolchain` symlink on macOS).
      if toolchainsByPath[toolchain.path] != nil {
        continue
      }

      // Non-XcodeDefault toolchain: disallow all duplicates.
      if toolchainsByIdentifier[toolchain.identifier] != nil,
        toolchain.identifier != ToolchainRegistry.darwinDefaultToolchainIdentifier
      {
        logger.error("Found two toolchains with the same identifier: \(toolchain.identifier)")
        continue
      }

      toolchainsByPath[toolchain.path] = toolchain
      toolchainsByIdentifier[toolchain.identifier, default: []].append(toolchain)

      for case .some(let compiler) in [toolchain.clang, toolchain.swift, toolchain.swiftc] {
        guard toolchainsByCompiler[compiler] == nil else {
          logger.fault("Found two toolchains with the same compiler: \(compiler)")
          continue
        }
        toolchainsByCompiler[compiler] = toolchain
      }

      toolchainsAndReasons.append((toolchain, reason))
    }

    self.toolchainsAndReasons = toolchainsAndReasons
    self.toolchainsByIdentifier = toolchainsByIdentifier
    self.toolchainsByPath = toolchainsByPath
    self.toolchainsByCompiler = toolchainsByCompiler

    if let darwinToolchainOverride, !darwinToolchainOverride.isEmpty, darwinToolchainOverride != "default" {
      self.darwinToolchainOverride = darwinToolchainOverride
    } else {
      self.darwinToolchainOverride = nil
    }
  }

  package init(xcodeToolchains toolchainPaths: [URL]) {
    let toolchainsAndReasons: [(toolchain: Toolchain, reason: ToolchainRegisterReason)] = toolchainPaths.compactMap {
      path in
      guard let toolchain = Toolchain(path) else {
        return nil
      }
      return (toolchain, .xcode)
    }
    self.init(toolchainsAndReasons: toolchainsAndReasons, darwinToolchainOverride: nil)
  }

  /// A toolchain registry used for testing that scans for toolchains based on environment variables and Xcode
  /// installations but not next to the `sourcekit-lsp` binary because there is no `sourcekit-lsp` binary during
  /// testing.
  package static var forTesting: ToolchainRegistry {
    ToolchainRegistry()
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
  package init(
    installPath: URL? = nil,
    environmentVariables: [ProcessEnvironmentKey] = ["SOURCEKIT_TOOLCHAIN_PATH"],
    xcodes: [URL] = [_currentXcodeDeveloperPath].compactMap({ $0 }),
    libraryDirectories: [URL] = FileManager.default.urls(for: .libraryDirectory, in: .allDomainsMask),
    pathEnvironmentVariables: [ProcessEnvironmentKey] = ["SOURCEKIT_PATH", "PATH"],
    darwinToolchainOverride: String? = ProcessEnv.block["TOOLCHAINS"]
  ) {
    // The paths at which we have found toolchains
    var toolchainPaths: [(path: URL, reason: ToolchainRegisterReason)] = []

    // Scan for toolchains in the paths given by `environmentVariables`.
    for envVar in environmentVariables {
      if let pathStr = ProcessEnv.block[envVar] {
        toolchainPaths.append((URL(fileURLWithPath: pathStr), .sourcekitToolchainEnvironmentVariable))
      }
    }

    // Search for toolchains relative to the path at which sourcekit-lsp is installed.
    if let installPath = installPath {
      toolchainPaths.append((installPath, .relativeToInstallPath))
    }

    // Search for toolchains in the Xcode developer directories and global toolchain install paths
    var toolchainSearchPaths =
      xcodes.map {
        if $0.pathExtension == "app" {
          return $0.appending(components: "Contents", "Developer", "Toolchains")
        } else {
          return $0.appending(component: "Toolchains")
        }
      }
    toolchainSearchPaths += libraryDirectories.compactMap {
      $0.appending(components: "Developer", "Toolchains")
    }

    for xctoolchainSearchPath in toolchainSearchPaths {
      let entries =
        (try? FileManager.default.contentsOfDirectory(at: xctoolchainSearchPath, includingPropertiesForKeys: nil)) ?? []
      for entry in entries {
        if entry.pathExtension == "xctoolchain" {
          toolchainPaths.append((entry, .xcode))
        }
      }
    }

    // Scan for toolchains by the given PATH-like environment variables.
    for envVar: ProcessEnvironmentKey in pathEnvironmentVariables {
      for path in getEnvSearchPaths(pathString: ProcessEnv.block[envVar], currentWorkingDirectory: nil) {
        toolchainPaths.append((path.asURL, .pathEnvironmentVariable))
      }
    }

    let toolchainsAndReasons = toolchainPaths.compactMap { toolchainAndReason in
      let resolvedPath = orLog("Toolchain realpath") {
        try toolchainAndReason.path.realpath
      }
      if let resolvedPath,
        let toolchain = Toolchain(resolvedPath)
      {
        return (toolchain, toolchainAndReason.reason)
      }
      return nil
    }
    self.init(toolchainsAndReasons: toolchainsAndReasons, darwinToolchainOverride: darwinToolchainOverride)
  }

  /// The default toolchain.
  ///
  /// On Darwin, this is typically the toolchain with the identifier `darwinToolchainIdentifier`,
  /// i.e. the default toolchain of the active Xcode. Otherwise it is the first toolchain that was
  /// registered, if any.
  ///
  /// The default toolchain must be only of the registered toolchains.
  package var `default`: Toolchain? {
    // Toolchains discovered from the `SOURCEKIT_TOOLCHAIN_PATH` environment variable or relative to sourcekit-lsp's
    // install path always take precedence over Xcode toolchains.
    if let (toolchain, reason) = toolchainsAndReasons.first, reason < .xcode {
      return toolchain
    }
    // Try finding the Xcode default toolchain.
    if let tc = toolchainsByIdentifier[darwinToolchainIdentifier]?.first {
      return tc
    }
    var result: Toolchain? = nil
    for toolchain in toolchains {
      if result == nil || toolchain.isProperSuperset(of: result!) {
        result = toolchain
      }
    }
    return result
  }

  /// The standard default toolchain identifier on Darwin.
  package static let darwinDefaultToolchainIdentifier: String = "com.apple.dt.toolchain.XcodeDefault"

  /// The current toolchain identifier on Darwin, which is either specified byt the `TOOLCHAINS`
  /// environment variable, or defaults to `darwinDefaultToolchainIdentifier`.
  ///
  /// The value of `default.identifier` may be different if the default toolchain has been
  /// explicitly overridden in code, or if there is no toolchain with this identifier.
  package var darwinToolchainIdentifier: String {
    return darwinToolchainOverride ?? ToolchainRegistry.darwinDefaultToolchainIdentifier
  }

  /// Returns the preferred toolchain that contains all the tools at the given key paths.
  package func preferredToolchain(containing requiredTools: [KeyPath<Toolchain, URL?>]) -> Toolchain? {
    if let toolchain = self.default, requiredTools.allSatisfy({ toolchain[keyPath: $0] != nil }) {
      return toolchain
    }

    for toolchain in toolchains {
      if requiredTools.allSatisfy({ toolchain[keyPath: $0] != nil }) {
        return toolchain
      }
    }

    return nil
  }

  /// If we have a toolchain in the toolchain registry that contains the compiler with the given URL, return it.
  /// Otherwise, return `nil`.
  package func toolchain(withCompiler compiler: URL) -> Toolchain? {
    if let toolchain = toolchainsByCompiler[compiler] {
      return toolchain
    }

    // Only canonicalize the folder path, as we don't want to resolve symlinks to eg. `swift-driver`.
    let resolvedPath = orLog("Compiler realpath") {
      try compiler.deletingLastPathComponent().realpath
    }?.appending(component: compiler.lastPathComponent)

    if let resolvedPath, let toolchain = toolchainsByCompiler[resolvedPath] {
      toolchainsByCompiler[compiler] = toolchain
      return toolchain
    }

    // Handle /usr/bin shims on Darwin
    #if canImport(Darwin)
    if compiler.deletingLastPathComponent() == URL(filePath: "/usr/bin/") {
      // Check cache from previous xcrun call
      if let cachedResolved = xcrunResolverCache.getCached(compiler),
        let toolchain = toolchainsByCompiler[cachedResolved]
      {
        toolchainsByCompiler[compiler] = toolchain
        return toolchain
      }
      // Trigger background resolution for next call
      xcrunResolverCache.triggerResolution(compiler)
      // Immediate fallback based on compiler type
      let name = compiler.lastPathComponent
      if name.contains("swift") {
        return preferredToolchain(containing: [\.swift, \.swiftc])
      } else if name.contains("clang") {
        return preferredToolchain(containing: [\.clang])
      }
    }
    #endif

    return nil
  }

  /// If we have a toolchain in the toolchain registry with the given URL, return it. Otherwise, return `nil`.
  package func toolchain(withPath path: URL) -> Toolchain? {
    if let toolchain = toolchainsByPath[path] {
      return toolchain
    }

    let resolvedPath = orLog("Toolchain realpath") {
      try path.realpath
    }
    guard let resolvedPath,
      let toolchain = toolchainsByPath[resolvedPath]
    else {
      return nil
    }

    // Cache mapping of non-realpath to the realpath toolchain for faster subsequent lookups
    toolchainsByPath[path] = toolchain
    return toolchain
  }

  /// Clears the xcrun resolution cache.
  package func clearXcrunCache() {
    xcrunResolverCache.clearCache()
  }
}

/// Inspecting internal state for testing purposes.
extension ToolchainRegistry {
  package func toolchains(withIdentifier identifier: String) -> [Toolchain] {
    return toolchainsByIdentifier[identifier] ?? []
  }
}

extension ToolchainRegistry {
  /// The path of the current Xcode.app/Contents/Developer.
  package static var _currentXcodeDeveloperPath: URL? {
    guard let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p") else { return nil }
    return URL(fileURLWithPath: str.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
