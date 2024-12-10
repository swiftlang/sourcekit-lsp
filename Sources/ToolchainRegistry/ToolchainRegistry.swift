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
import LanguageServerProtocolExtensions
import SwiftExtensions
import TSCExtensions

#if compiler(>=6)
package import Foundation
package import class TSCBasic.Process
package import enum TSCBasic.ProcessEnv
package import struct TSCBasic.ProcessEnvironmentKey
package import func TSCBasic.getEnvSearchPaths
#else
import Foundation
import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import struct TSCBasic.ProcessEnvironmentKey
import func TSCBasic.getEnvSearchPaths
#endif

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
  ///
  /// Note: Not all toolchains have a path.
  private let toolchainsByPath: [URL: Toolchain]

  /// The currently selected toolchain identifier on Darwin.
  package let darwinToolchainOverride: String?

  /// Create a toolchain registry with a pre-defined list of toolchains.
  ///
  /// For testing purposes only.
  public init(toolchains: [Toolchain]) {
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
    for (toolchain, reason) in toolchainsAndReasonsParam {
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
      toolchainsAndReasons.append((toolchain, reason))
    }

    self.toolchainsAndReasons = toolchainsAndReasons
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
          return $0.appendingPathComponent("Contents").appendingPathComponent("Developer").appendingPathComponent(
            "Toolchains"
          )
        } else {
          return $0.appendingPathComponent("Toolchains")
        }
      }
    toolchainSearchPaths += libraryDirectories.compactMap {
      $0.appendingPathComponent("Developer").appendingPathComponent("Toolchains")
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

    let toolchainsAndReasons = toolchainPaths.compactMap {
      if let toolchain = Toolchain($0.path) {
        return (toolchain, $0.reason)
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
    get {
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
}

/// Inspecting internal state for testing purposes.
extension ToolchainRegistry {
  package func toolchains(withIdentifier identifier: String) -> [Toolchain] {
    return toolchainsByIdentifier[identifier] ?? []
  }

  package func toolchain(withPath path: URL) -> Toolchain? {
    return toolchainsByPath[path]
  }
}

extension ToolchainRegistry {
  /// The path of the current Xcode.app/Contents/Developer.
  package static var _currentXcodeDeveloperPath: URL? {
    guard let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p") else { return nil }
    return URL(fileURLWithPath: str.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
