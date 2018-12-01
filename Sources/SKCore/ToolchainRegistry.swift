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
import Basic
import Utility
import Dispatch
import POSIX
import Foundation

public final class ToolchainRegistry {

  var _toolchains: [String: Toolchain] = [:]

  var defaultID: String? = nil

  var queue: DispatchQueue = DispatchQueue(label: "toolchain-registry-queue")

  let fs: FileSystem

  /// The known toolchains, keyed by toolchain identifier.
  public var toolchains: [String: Toolchain] { return queue.sync { _toolchains } }

  /// The default toolchain, or nil.
  public var `default`: Toolchain? {
    return queue.sync {
      return defaultID.flatMap { _toolchains[$0] }
    }
  }

  public init(fileSystem: FileSystem = localFileSystem) {
    self.fs = fileSystem
  }

  public func scanForToolchains() {
    // Force the default toolchain using SOURCEKIT_TOOLCHAIN_PATH.
    if let pathStr = getenv("SOURCEKIT_TOOLCHAIN_PATH"),
       let path = try? AbsolutePath(validating: pathStr),
       let toolchain = scanForToolchain(path: path)
    {
      setDefaultToolchain(identifier: toolchain.identifier)
    }

    // Find any XCToolchains.
    if case .darwin? = Platform.currentPlatform {
      scanForToolchainsDarwin()
    }

    // Find any toolchains in PATH-like environment variables.
    scanForToolchainsInPATH()

    updateDefaultToolchainIfNeeded()
  }

  func updateDefaultToolchainIfNeeded() {
    queue.sync { _updateDefaultToolchainIfNeeded() }
  }

  // Must called on `queue`.
  private func _updateDefaultToolchainIfNeeded() {
    if case .darwin? = Platform.currentPlatform,
       let tc = _toolchains[ToolchainRegistry.darwinDefaultToolchainID] {
      defaultID = defaultID ?? tc.identifier
    }
    // Fallback to arbitrarily choosing a default toolchain.
    defaultID = defaultID ?? _toolchains.values.first?.identifier
  }

  func scanForToolchainsInPATH() {
    let searchPaths =
      getEnvSearchPaths(pathString: getenv("SOURCEKIT_PATH"), currentWorkingDirectory: nil) +
      getEnvSearchPaths(pathString: getenv("PATH"), currentWorkingDirectory: nil)

    for dir in searchPaths {
      scanForToolchain(path: dir)
    }
  }

  @discardableResult
  func scanForToolchain(path: AbsolutePath) -> Toolchain? {
    if let toolchain = Toolchain(path: path, fileSystem: fs) {
      registerToolchain(toolchain)
      return toolchain
    }
    return nil
  }

  /// Register the given toolchain if we have not seen a toolchain with this identifier before and (optionally) set it as the default toolchain.
  ///
  /// If the toolchain has been seen before we will **not** change the default toolchain.
  ///
  /// - returns: `false` if this toolchain identifier has already been seen.
  @discardableResult
  public func registerToolchain(_ toolchain: Toolchain, isDefault: Bool = false) -> Bool {
    return queue.sync {
      // If we have seen this identifier before, we keep the first one.
      if _toolchains[toolchain.identifier] == nil {
        _toolchains[toolchain.identifier] = toolchain
        if isDefault {
          defaultID = toolchain.identifier
        } else {
          _updateDefaultToolchainIfNeeded()
        }
        return true
      }
      return false
    }
  }

  public func setDefaultToolchain(identifier: String?) {
    queue.sync {
      defaultID = identifier
    }
  }
}

extension ToolchainRegistry {

  // MARK: - Darwin

  public static let darwinDefaultToolchainID: String = "com.apple.dt.toolchain.XcodeDefault"

  /// The paths to search for xctoolchains outside of Xcode.
  static let defaultXCToolchainSearchPaths: [AbsolutePath] = [
    AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains"),
    AbsolutePath("/Library/Developer/Toolchains"),
    ]

  var currentXcodeDeveloperPath: AbsolutePath? {
    if let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p"), let path = try? AbsolutePath(validating: str.spm_chomp()) {
      return path
    }
    return nil
  }

  private func scanForToolchainsDarwin() {
    // Try to find the current Xcode's toolchains using `xcode-select -p`
    if let path = currentXcodeDeveloperPath {
      scanForXCToolchains(path.appending(components: "Toolchains"))
    }

    // Next, search any other known locations.
    for path in ToolchainRegistry.defaultXCToolchainSearchPaths {
      scanForXCToolchains(path)
    }
  }

  private func scanForXCToolchains(_ toolchains: AbsolutePath) {
    guard let contents = try? fs.getDirectoryContents(toolchains) else {
      return
    }
    for name in contents {
      let path = toolchains.appending(component: name)
      if path.extension == "xctoolchain", let toolchain = Toolchain(path: path, fileSystem: fs) {
        registerToolchain(toolchain)
      }
    }
  }
}


