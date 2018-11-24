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

import Basic
import Utility

public final class Toolchain {

  public var identifier: String
  public var displayName: String
  public var path: AbsolutePath? = nil

  public var clang: AbsolutePath?
  public var swiftc: AbsolutePath?
  public var clangd: AbsolutePath?
  public var sourcekitd: AbsolutePath?
  public var libIndexStore: AbsolutePath?

  public init(identifier: String, displayName: String, path: AbsolutePath?) {
    self.identifier = identifier
    self.displayName = displayName
    self.path = path
  }

  public convenience init?(
    identifier: String,
    displayName: String,
    searchForTools path: AbsolutePath,
    fileSystem fs: FileSystem = localFileSystem)
  {
    self.init(identifier: identifier, displayName: displayName, path: path)
    if !searchForTools(path: path, fileSystem: fs) {
      return nil
    }
  }

  public convenience init(
    identifier: String,
    displayName: String,
    xctoolchainPath path: AbsolutePath,
    fileSystem fs: FileSystem = localFileSystem
  ) {
    self.init(identifier: identifier, displayName: displayName, path: path)
    searchForTools(path: path, fileSystem: fs)
  }

  /// Search `path` for tools, returning true if any are found.
  @discardableResult
  func searchForTools(path: AbsolutePath, fileSystem fs: FileSystem = localFileSystem) -> Bool {
    return
      searchForTools(binPath: path, fs) ||
      searchForTools(binPath: path.appending(components: "bin"), fs) ||
      searchForTools(binPath: path.appending(components: "usr", "bin"), fs)
  }

  private func searchForTools(binPath: AbsolutePath, _ fs: FileSystem) -> Bool {

    let libPath = binPath.parentDirectory.appending(component: "lib")

    guard fs.isDirectory(binPath) || fs.isDirectory(libPath) else { return false }

    var foundAny = false

    let clangPath = binPath.appending(component: "clang")
    if fs.isExecutableFile(clangPath) {
      self.clang = clangPath
      foundAny = true
    }
    let clangdPath = binPath.appending(component: "clangd")
    if fs.isExecutableFile(clangdPath) {
      self.clangd = clangdPath
      foundAny = true
    }

    let swiftcPath = binPath.appending(component: "swiftc")
    if fs.isExecutableFile(swiftcPath) {
      self.swiftc = swiftcPath
      foundAny = true
    }

    // If 'currentPlatform' is nil it's most likely an unknown linux flavor.
    let dylibExt = Platform.currentPlatform?.dynamicLibraryExtension ?? "so"

    let sourcekitdPath = libPath.appending(components: "sourcekitd.framework", "sourcekitd")
    if fs.isFile(sourcekitdPath) {
      self.sourcekitd = sourcekitdPath
      foundAny = true
    } else {
      let sourcekitdPath = libPath.appending(component: "libsourcekitdInProc.\(dylibExt)")
      if fs.isFile(sourcekitdPath) {
        self.sourcekitd = sourcekitdPath
        foundAny = true
      }
    }

    let libIndexStore = libPath.appending(components: "libIndexStore.\(dylibExt)")
    if fs.isFile(libIndexStore) {
      self.libIndexStore = libIndexStore
      foundAny = true
    }

    return foundAny
  }
}

extension Platform {
  var dynamicLibraryExtension: String {
    switch self {
    case .darwin: return "dylib"
    case .linux: return "so"
    }
  }
}
