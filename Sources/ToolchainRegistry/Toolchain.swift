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

import RegexBuilder
import SKLogging
import SwiftExtensions

import enum PackageLoading.Platform
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import class TSCBasic.Process
import var TSCBasic.localFileSystem

/// A Swift version consisting of the major and minor component.
package struct SwiftVersion: Sendable, Comparable, CustomStringConvertible {
  package let major: Int
  package let minor: Int

  package static func < (lhs: SwiftVersion, rhs: SwiftVersion) -> Bool {
    return (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
  }

  package init(_ major: Int, _ minor: Int) {
    self.major = major
    self.minor = minor
  }

  package var description: String {
    return "\(major).\(minor)"
  }
}

fileprivate enum SwiftVersionParsingError: Error, CustomStringConvertible {
  case failedToFindSwiftc
  case failedToParseOutput(output: String?)

  var description: String {
    switch self {
    case .failedToFindSwiftc:
      return "Default toolchain does not contain a swiftc executable"
    case .failedToParseOutput(let output):
      return """
        Failed to parse Swift version. Output of swift --version:
        \(output ?? "<empty>")
        """
    }
  }
}

/// A Toolchain is a collection of related compilers and libraries meant to be used together to
/// build and edit source code.
///
/// This can be an explicit toolchain, such as an xctoolchain directory on Darwin, or an implicit
/// toolchain, such as the contents from `/usr/bin`.
public final class Toolchain: Sendable {

  /// The unique toolchain identifier.
  ///
  /// For an xctoolchain, this is a reverse domain name e.g. "com.apple.dt.toolchain.XcodeDefault".
  /// Otherwise, it is typically derived from `path`.
  package let identifier: String

  /// The human-readable name for the toolchain.
  package let displayName: String

  /// The path to this toolchain, if applicable.
  ///
  /// For example, this may be the path to an ".xctoolchain" directory.
  package let path: AbsolutePath?

  // MARK: Tool Paths

  /// The path to the Clang compiler if available.
  package let clang: AbsolutePath?

  /// The path to the Swift driver if available.
  package let swift: AbsolutePath?

  /// The path to the Swift compiler if available.
  package let swiftc: AbsolutePath?

  /// The path to the swift-format executable, if available.
  package let swiftFormat: AbsolutePath?

  /// The path to the clangd language server if available.
  package let clangd: AbsolutePath?

  /// The path to the Swift language server if available.
  package let sourcekitd: AbsolutePath?

  /// The path to the indexstore library if available.
  package let libIndexStore: AbsolutePath?

  private let swiftVersionTask = ThreadSafeBox<Task<SwiftVersion, any Error>?>(initialValue: nil)

  /// The Swift version installed in the toolchain. Throws an error if the version could not be parsed or if no Swift
  /// compiler is installed in the toolchain.
  package var swiftVersion: SwiftVersion {
    get async throws {
      let task = swiftVersionTask.withLock { task in
        if let task {
          return task
        }
        let newTask = Task { () -> SwiftVersion in
          guard let swiftc else {
            throw SwiftVersionParsingError.failedToFindSwiftc
          }

          let process = Process(args: swiftc.pathString, "--version")
          try process.launch()
          let result = try await process.waitUntilExit()
          let output = String(bytes: try result.output.get(), encoding: .utf8)
          let regex = Regex {
            "Swift version "
            Capture { OneOrMore(.digit) }
            "."
            Capture { OneOrMore(.digit) }
          }
          guard let match = output?.firstMatch(of: regex) else {
            throw SwiftVersionParsingError.failedToParseOutput(output: output)
          }
          guard let major = Int(match.1), let minor = Int(match.2) else {
            throw SwiftVersionParsingError.failedToParseOutput(output: output)
          }
          return SwiftVersion(major, minor)
        }
        task = newTask
        return newTask
      }

      return try await task.value
    }
  }

  public init(
    identifier: String,
    displayName: String,
    path: AbsolutePath? = nil,
    clang: AbsolutePath? = nil,
    swift: AbsolutePath? = nil,
    swiftc: AbsolutePath? = nil,
    swiftFormat: AbsolutePath? = nil,
    clangd: AbsolutePath? = nil,
    sourcekitd: AbsolutePath? = nil,
    libIndexStore: AbsolutePath? = nil
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.path = path
    self.clang = clang
    self.swift = swift
    self.swiftc = swiftc
    self.swiftFormat = swiftFormat
    self.clangd = clangd
    self.sourcekitd = sourcekitd
    self.libIndexStore = libIndexStore
  }

  /// Returns `true` if this toolchain has strictly more tools than `other`.
  ///
  /// ### Examples
  /// - A toolchain that contains both `swiftc` and  `clangd` is a superset of one that only contains `swiftc`.
  /// - A toolchain that contains only `swiftc`, `clangd` is not a superset of a toolchain that contains `swiftc` and
  ///   `libIndexStore`. These toolchains are not comparable.
  /// - Two toolchains that both contain `swiftc` and `clangd` are supersets of each other.
  func isSuperset(of other: Toolchain) -> Bool {
    func isSuperset(for tool: KeyPath<Toolchain, AbsolutePath?>) -> Bool {
      if self[keyPath: tool] == nil && other[keyPath: tool] != nil {
        // This toolchain doesn't contain the tool but the other toolchain does. It is not a superset.
        return false
      } else {
        return true
      }
    }
    return isSuperset(for: \.clang) && isSuperset(for: \.swift) && isSuperset(for: \.swiftc)
      && isSuperset(for: \.clangd) && isSuperset(for: \.sourcekitd) && isSuperset(for: \.libIndexStore)
  }

  /// Same as `isSuperset` but returns `false` if both toolchains have the same set of tools.
  func isProperSuperset(of other: Toolchain) -> Bool {
    return self.isSuperset(of: other) && !other.isSuperset(of: self)
  }
}

extension Toolchain {
  /// Create a toolchain for the given path, if it contains at least one tool, otherwise return nil.
  ///
  /// This initializer looks for a toolchain using the following basic layout:
  ///
  /// ```
  /// bin/clang
  ///    /clangd
  ///    /swiftc
  /// lib/sourcekitd.framework/sourcekitd
  ///    /libsourcekitdInProc.{so,dylib}
  ///    /libIndexStore.{so,dylib}
  /// ```
  ///
  /// The above directory layout can found relative to `path` in the following ways:
  /// * `path` (=bin), `path/../lib`
  /// * `path/bin`, `path/lib`
  /// * `path/usr/bin`, `path/usr/lib`
  ///
  /// If `path` contains an ".xctoolchain", we try to read an Info.plist file to provide the
  /// toolchain identifier, etc.  Otherwise this information is derived from the path.
  convenience package init?(_ path: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) {
    // Properties that need to be initialized
    let identifier: String
    let displayName: String
    let toolchainPath: AbsolutePath?
    var clang: AbsolutePath? = nil
    var clangd: AbsolutePath? = nil
    var swift: AbsolutePath? = nil
    var swiftc: AbsolutePath? = nil
    var swiftFormat: AbsolutePath? = nil
    var sourcekitd: AbsolutePath? = nil
    var libIndexStore: AbsolutePath? = nil

    if let (infoPlist, xctoolchainPath) = containingXCToolchain(path, fileSystem) {
      identifier = infoPlist.identifier
      displayName = infoPlist.displayName ?? xctoolchainPath.basenameWithoutExt
      toolchainPath = xctoolchainPath
    } else {
      identifier = path.pathString
      displayName = path.basename
      toolchainPath = path
    }

    // Find tools in the toolchain

    var foundAny = false
    let searchPaths = [path, path.appending(components: "bin"), path.appending(components: "usr", "bin")]
    for binPath in searchPaths {
      let libPath = binPath.parentDirectory.appending(component: "lib")

      guard fileSystem.isDirectory(binPath) || fileSystem.isDirectory(libPath) else { continue }

      let execExt = Platform.current?.executableExtension ?? ""

      let clangPath = binPath.appending(component: "clang\(execExt)")
      if fileSystem.isExecutableFile(clangPath) {
        clang = clangPath
        foundAny = true
      }
      let clangdPath = binPath.appending(component: "clangd\(execExt)")
      if fileSystem.isExecutableFile(clangdPath) {
        clangd = clangdPath
        foundAny = true
      }

      let swiftPath = binPath.appending(component: "swift\(execExt)")
      if fileSystem.isExecutableFile(swiftPath) {
        swift = swiftPath
        foundAny = true
      }

      let swiftcPath = binPath.appending(component: "swiftc\(execExt)")
      if fileSystem.isExecutableFile(swiftcPath) {
        swiftc = swiftcPath
        foundAny = true
      }

      let swiftFormatPath = binPath.appending(component: "swift-format\(execExt)")
      if fileSystem.isExecutableFile(swiftFormatPath) {
        swiftFormat = swiftFormatPath
        foundAny = true
      }

      // If 'currentPlatform' is nil it's most likely an unknown linux flavor.
      let dylibExt: String
      if let dynamicLibraryExtension = Platform.current?.dynamicLibraryExtension {
        dylibExt = dynamicLibraryExtension
      } else {
        logger.fault("Could not determine host OS. Falling back to using '.so' as dynamic library extension")
        dylibExt = ".so"
      }

      let sourcekitdPath = libPath.appending(components: "sourcekitd.framework", "sourcekitd")
      if fileSystem.isFile(sourcekitdPath) {
        sourcekitd = sourcekitdPath
        foundAny = true
      } else {
        #if os(Windows)
        let sourcekitdPath = binPath.appending(component: "sourcekitdInProc\(dylibExt)")
        #else
        let sourcekitdPath = libPath.appending(component: "libsourcekitdInProc\(dylibExt)")
        #endif
        if fileSystem.isFile(sourcekitdPath) {
          sourcekitd = sourcekitdPath
          foundAny = true
        }
      }

      #if os(Windows)
      let libIndexStorePath = binPath.appending(components: "libIndexStore\(dylibExt)")
      #else
      let libIndexStorePath = libPath.appending(components: "libIndexStore\(dylibExt)")
      #endif
      if fileSystem.isFile(libIndexStorePath) {
        libIndexStore = libIndexStorePath
        foundAny = true
      }

      if foundAny {
        break
      }
    }
    if !foundAny {
      return nil
    }

    self.init(
      identifier: identifier,
      displayName: displayName,
      path: toolchainPath,
      clang: clang,
      swift: swift,
      swiftc: swiftc,
      swiftFormat: swiftFormat,
      clangd: clangd,
      sourcekitd: sourcekitd,
      libIndexStore: libIndexStore
    )
  }
}

/// Find a containing xctoolchain with plist, if available.
func containingXCToolchain(
  _ path: AbsolutePath,
  _ fileSystem: FileSystem
) -> (XCToolchainPlist, AbsolutePath)? {
  var path = path
  while !path.isRoot {
    if path.extension == "xctoolchain" {
      if let infoPlist = orLog("", { try XCToolchainPlist(fromDirectory: path, fileSystem) }) {
        return (infoPlist, path)
      }
      return nil
    }
    path = path.parentDirectory
  }
  return nil
}
