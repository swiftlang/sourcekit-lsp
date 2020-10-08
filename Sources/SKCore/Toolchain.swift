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
import LSPLogging
import SKSupport
import TSCBasic
import TSCUtility

/// A Toolchain is a collection of related compilers and libraries meant to be used together to
/// build and edit source code.
///
/// This can be an explicit toolchain, such as an xctoolchain directory on Darwin, or an implicit
/// toolchain, such as the contents from `/usr/bin`.
public final class Toolchain {

  /// The unique toolchain identifer.
  ///
  /// For an xctoolchain, this is a reverse domain name e.g. "com.apple.dt.toolchain.XcodeDefault".
  /// Otherwise, it is typically derived from `path`.
  public var identifier: String

  /// The human-readable name for the toolchain.
  public var displayName: String

  /// The path to this toolchain, if applicable.
  ///
  /// For example, this may be the path to an ".xctoolchain" directory.
  public var path: AbsolutePath? = nil

  // MARK: Tool Paths

  /// The path to the Clang compiler if available.
  public var clang: AbsolutePath?

  /// The path to the Swift compiler if available.
  public var swiftc: AbsolutePath?

  /// The path to the clangd language server if available.
  public var clangd: AbsolutePath?

  /// The path to the Swift language server if available.
  public var sourcekitd: AbsolutePath?

  /// The path to the indexstore library if available.
  public var libIndexStore: AbsolutePath?

  public init(
    identifier: String,
    displayName: String,
    path: AbsolutePath? = nil,
    clang: AbsolutePath? = nil,
    swiftc: AbsolutePath? = nil,
    clangd: AbsolutePath? = nil,
    sourcekitd: AbsolutePath? = nil,
    libIndexStore: AbsolutePath? = nil)
  {
    self.identifier = identifier
    self.displayName = displayName
    self.path = path
    self.clang = clang
    self.swiftc = swiftc
    self.clangd = clangd
    self.sourcekitd = sourcekitd
    self.libIndexStore = libIndexStore
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
  convenience public init?(_ path: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) {
    if let (infoPlist, xctoolchainPath) = containingXCToolchain(path, fileSystem) {
      let displayName = infoPlist.displayName ?? xctoolchainPath.basenameWithoutExt
      self.init(identifier: infoPlist.identifier, displayName: displayName, path: xctoolchainPath)
    } else {
      self.init(identifier: path.pathString, displayName: path.basename, path: path)
    }

    if !searchForTools(path, fileSystem) {
      return nil
    }
  }

  /// Search `path` for tools, returning true if any are found.
  @discardableResult
  func searchForTools(_ path: AbsolutePath, _ fs: FileSystem = localFileSystem) -> Bool {
    return
      searchForTools(binPath: path, fs) ||
      searchForTools(binPath: path.appending(components: "bin"), fs) ||
      searchForTools(binPath: path.appending(components: "usr", "bin"), fs)
  }

  private func searchForTools(binPath: AbsolutePath, _ fs: FileSystem) -> Bool {

    let libPath = binPath.parentDirectory.appending(component: "lib")

    guard fs.isDirectory(binPath) || fs.isDirectory(libPath) else { return false }

    var foundAny = false

    let execExt = Platform.currentPlatform?.executableExtension ?? ""

    let clangPath = binPath.appending(component: "clang\(execExt)")
    if fs.isExecutableFile(clangPath) {
      self.clang = clangPath
      foundAny = true
    }
    let clangdPath = binPath.appending(component: "clangd\(execExt)")
    if fs.isExecutableFile(clangdPath) {
      self.clangd = clangdPath
      foundAny = true
    }

    let swiftcPath = binPath.appending(component: "swiftc\(execExt)")
    if fs.isExecutableFile(swiftcPath) {
      self.swiftc = swiftcPath
      foundAny = true
    }

    // If 'currentPlatform' is nil it's most likely an unknown linux flavor.
    let dylibExt = Platform.currentPlatform?.dynamicLibraryExtension ?? ".so"

    let sourcekitdPath = libPath.appending(components: "sourcekitd.framework", "sourcekitd")
    if fs.isFile(sourcekitdPath) {
      self.sourcekitd = sourcekitdPath
      foundAny = true
    } else {
#if os(Windows)
      let sourcekitdPath = binPath.appending(component: "sourcekitdInProc\(dylibExt)")
#else
      let sourcekitdPath = libPath.appending(component: "libsourcekitdInProc\(dylibExt)")
#endif
      if fs.isFile(sourcekitdPath) {
        self.sourcekitd = sourcekitdPath
        foundAny = true
      }
    }

#if os(Windows)
    let libIndexStore = binPath.appending(components: "libIndexStore\(dylibExt)")
#else
    let libIndexStore = libPath.appending(components: "libIndexStore\(dylibExt)")
#endif
    if fs.isFile(libIndexStore) {
      self.libIndexStore = libIndexStore
      foundAny = true
    }

    return foundAny
  }
}

/// Find a containing xctoolchain with plist, if available.
func containingXCToolchain(
  _ path: AbsolutePath,
  _ fileSystem: FileSystem) -> (XCToolchainPlist, AbsolutePath)?
{
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
