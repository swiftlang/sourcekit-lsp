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

  var queue = DispatchQueue(label: "toolchain-registry-queue")

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
    if let toolchain = Toolchain(
      identifier: path.asString,
      displayName: path.basename,
      searchForTools: path,
      fileSystem: fs)
    {
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

  var currentXodeDeveloperPath: AbsolutePath? {
    if let str = try? Process.checkNonZeroExit(args: "/usr/bin/xcode-select", "-p"), let path = try? AbsolutePath(validating: str.chomp()) {
      return path
    }
    return nil
  }

  private func scanForToolchainsDarwin() {
    // Try to find the current Xcode's toolchains using `xcode-select -p`
    if let path = currentXodeDeveloperPath {
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
      if path.extension == "xctoolchain" {
        // Ignore failure.
        _ = try? registerXCToolchain(at: path)
      }
    }
  }

  /// Returns the Info.plist contents from the xctoolchain at `path`, or nil.
  func readXCToolchainPlist(fromDirectory path: AbsolutePath) throws -> XCToolchainPlist {
    let plistNames = [
      RelativePath("ToolchainInfo.plist"), // Xcode
      RelativePath("Info.plist"), // Swift.org
    ]

#if os(macOS)
    for name in plistNames {
      let plistPath = path.appending(name)
      if fs.isFile(plistPath) {
        let bytes = try fs.readFileContents(plistPath)
        return bytes.withUnsafeData { data in
          var format = PropertyListSerialization.PropertyListFormat.binary
          do {
            return try PropertyListDecoder().decode(XCToolchainPlist.self, from: data, format: &format)
          } catch {
            // Error!
            fatalError(error.localizedDescription)
          }
        }
      }
    }
#else
    fatalError("readXCToolchainPlist not implemented")
#endif

    throw FileSystemError.noEntry
  }

  /// Register an xctoolchain at the given `path` if we have not seen a toolchain with this identifier before.
  ///
  /// - returns: `false` if this toolchain identifier has already been seen.
  /// - throws: An error if there is a problem reading the Info.plist or loading the toolchain.
  @discardableResult
  public func registerXCToolchain(at path: AbsolutePath) throws -> Bool {
    return try queue.sync {

      let infoPlist = try readXCToolchainPlist(fromDirectory: path)

      // If we have seen this identifier before, we keep the first one.
      if _toolchains[infoPlist.identifier] == nil {
        let displayName = infoPlist.displayName ?? String(path.basename.dropLast(path.suffix?.count ?? 0))
        self._toolchains[infoPlist.identifier] = Toolchain(identifier: infoPlist.identifier, displayName: displayName, xctoolchainPath: path, fileSystem: fs)
        return true
      }
      return false
    }
  }
}

/// A helper type for decoding the Info.plist or ToolchainInfo.plist file from a .xctoolchain.
struct XCToolchainPlist {
  var identifier: String
  var displayName: String?
}

extension XCToolchainPlist: Codable {
  private enum CodingKeys: String, CodingKey {
    case Identifier
    case CFBundleIdentifier
    case DisplayName
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let identifier = try container.decodeIfPresent(String.self, forKey: .Identifier) {
      self.identifier = identifier
    } else {
      self.identifier = try container.decode(String.self, forKey: .CFBundleIdentifier)
    }
    self.displayName = try container.decodeIfPresent(String.self, forKey: .DisplayName)
  }

  /// Encode the info plist. **For testing**.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if identifier.starts(with: "com.apple") {
      try container.encode(identifier, forKey: .Identifier)
    } else {
      try container.encode(identifier, forKey: .CFBundleIdentifier)
    }
    try container.encodeIfPresent(displayName, forKey: .DisplayName)
  }
}
