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

@testable import SKCore
import Basic
import Utility
import XCTest
import POSIX

final class ToolchainRegistryTests: XCTestCase {
  func testDefaultBasic() {
    let tr = ToolchainRegistry()

    XCTAssertNil(tr.default)
    tr.registerToolchain(Toolchain(identifier: "a", displayName: "a", path: nil))
    XCTAssertEqual(tr.default?.identifier, "a")
    tr.registerToolchain(Toolchain(identifier: "b", displayName: "b", path: nil), isDefault: true)
    XCTAssertEqual(tr.default?.identifier, "b")
    tr.setDefaultToolchain(identifier: "a")
    XCTAssertEqual(tr.default?.identifier, "a")
    tr.setDefaultToolchain(identifier: nil)
    XCTAssertNil(tr.default)
  }

  func testDefaultDarwin() {
    let prevPlatform = Platform.currentPlatform
    defer { Platform.currentPlatform = prevPlatform }
    Platform.currentPlatform = .darwin

    let tr = ToolchainRegistry()
    XCTAssertNil(tr.default)
    tr.registerToolchain(Toolchain(identifier: "a", displayName: "a", path: nil))
    XCTAssertEqual(tr.default?.identifier, "a")
    tr.registerToolchain(Toolchain(identifier: ToolchainRegistry.darwinDefaultToolchainID, displayName: "a", path: nil))
    XCTAssertEqual(tr.default?.identifier, "a")
    tr.setDefaultToolchain(identifier: nil)
    tr.updateDefaultToolchainIfNeeded()
    XCTAssertEqual(tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainID)
  }

  func testUnknownPlatform() {
    let prevPlatform = Platform.currentPlatform
    defer { Platform.currentPlatform = prevPlatform }
    Platform.currentPlatform = nil

    let fs = InMemoryFileSystem()
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fileSystem: fs, sourcekitdInProc: true)

    guard let t = Toolchain(path: binPath, fileSystem: fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
  }

  func testSearchDarwin() {
// FIXME: requires PropertyListEncoder
#if os(macOS)
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fileSystem: fs)

    let xcodeDeveloper = tr.currentXcodeDeveloperPath!
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    makeXCToolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainID,
      opensource: false,
      path: toolchains.appending(component: "XcodeDefault.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)

    XCTAssertNil(tr.default)
    XCTAssert(tr.toolchains.isEmpty)

    tr.scanForToolchains()

    XCTAssertEqual(tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainID)
    XCTAssertEqual(tr.default?.path, toolchains.appending(component: "XcodeDefault.xctoolchain"))
    XCTAssertNotNil(tr.default?.sourcekitd)
    XCTAssertEqual(tr.toolchains.count, 1)

    let defaultToolchain = tr.default!

    XCTAssert(tr.toolchains.first?.value === defaultToolchain)

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 1)
    XCTAssert(tr.default === defaultToolchain)

    makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      path: toolchains.appending(component: "A.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)
    makeXCToolchain(
      identifier: "com.apple.fake.B",
      opensource: false,
      path: toolchains.appending(component: "B.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 3)

    makeXCToolchain(
      identifier: "com.apple.fake.C",
      opensource: false,
      path: toolchains.appending(component: "C.wrong_extension"),
      fileSystem: fs,
      sourcekitd: true)
    makeXCToolchain(
      identifier: "com.apple.fake.D",
      opensource: false,
      path: toolchains.appending(component: "D_no_extension"),
      fileSystem: fs,
      sourcekitd: true)

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 3)

    makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      path: toolchains.appending(component: "E.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 3)

    makeXCToolchain(
      identifier: "org.fake.global.A",
      opensource: true,
      path: AbsolutePath("/Library/Developer/Toolchains/A.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)
    makeXCToolchain(
      identifier: "org.fake.global.B",
      opensource: true,
      path: AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains/B.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 5)

    let path = toolchains.appending(component: "Explicit.xctoolchain")
    makeXCToolchain(
      identifier: "org.fake.explicit",
      opensource: false,
      path: toolchains.appending(component: "Explicit.xctoolchain"),
      fileSystem: fs,
      sourcekitd: true)

    let tc = Toolchain(path: path, fileSystem: fs)
    XCTAssertNotNil(tc)
    XCTAssertEqual(tc?.identifier, "org.fake.explicit")
#endif
  }

  func testSearchPATH() {
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fileSystem: fs)
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fileSystem: fs, sourcekitd: true)

    XCTAssertNil(tr.default)
    XCTAssert(tr.toolchains.isEmpty)

    try! setenv("SOURCEKIT_PATH", value: "/bogus:\(binPath.asString):/bogus2")
    defer { try! setenv("SOURCEKIT_PATH", value: "") }

    tr.scanForToolchains()

    guard case (_, let tc)? = tr.toolchains.first(where: { _, value in value.path == binPath }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    XCTAssertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc.identifier, binPath.asString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)
  }

  func testSearchExplicitEnv() {
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fileSystem: fs)
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fileSystem: fs, sourcekitd: true)

    XCTAssertNil(tr.default)
    XCTAssert(tr.toolchains.isEmpty)

    try! setenv("SOURCEKIT_TOOLCHAIN_PATH", value: binPath.parentDirectory.asString)
    defer { try! setenv("SOURCEKIT_TOOLCHAIN_PATH", value: "") }

    tr.scanForToolchains()

    guard case (_, let tc)? = tr.toolchains.first(where: { _, value in value.path == binPath.parentDirectory }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    XCTAssertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc.identifier, binPath.parentDirectory.asString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)
  }

  func testFromDirectory() {
    // This test uses the real file system because the in-memory system doesn't support marking files executable.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)

    let path = tempDir.path.appending(components: "A.xctoolchain", "usr")
    makeToolchain(
      binPath: path.appending(component: "bin"),
      fileSystem: fs,
      clang: true,
      clangd: true,
      swiftc: true,
      shouldChmod: false,
      sourcekitd: true)

    try! fs.writeFileContents(path.appending(components: "bin", "other") , bytes: "")

    let t1 = Toolchain(path: path.parentDirectory, fileSystem: fs)!
    XCTAssertNotNil(t1.sourcekitd)
    XCTAssertNil(t1.clang)
    XCTAssertNil(t1.clangd)
    XCTAssertNil(t1.swiftc)

    func chmodRX(_ path: AbsolutePath) {
      XCTAssertEqual(chmod(path.asString, S_IRUSR | S_IXUSR), 0)
    }

    chmodRX(path.appending(components: "bin", "clang"))
    chmodRX(path.appending(components: "bin", "clangd"))
    chmodRX(path.appending(components: "bin", "swiftc"))
    chmodRX(path.appending(components: "bin", "other"))

    let t2 = Toolchain(path: path.parentDirectory, fileSystem: fs)!
    XCTAssertNotNil(t2.sourcekitd)
    XCTAssertNotNil(t2.clang)
    XCTAssertNotNil(t2.clangd)
    XCTAssertNotNil(t2.swiftc)
  }

  func testDylibNames() {
    let fs = InMemoryFileSystem()
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fileSystem: fs, sourcekitdInProc: true, libIndexStore: true)
    guard let t = Toolchain(path: binPath, fileSystem: fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
    XCTAssertNotNil(t.libIndexStore)
  }

  func testSubDirs() {
    let fs = InMemoryFileSystem()
    makeToolchain(binPath: AbsolutePath("/t1/bin"), fileSystem: fs, sourcekitd: true)
    makeToolchain(binPath: AbsolutePath("/t2/usr/bin"), fileSystem: fs, sourcekitd: true)

    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t1"), fileSystem: fs))
    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t1/bin"), fileSystem: fs))
    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t2"), fileSystem: fs))

    XCTAssertNil(Toolchain(path: AbsolutePath("/t3"), fileSystem: fs))
    try! fs.createDirectory(AbsolutePath("/t3/bin"), recursive: true)
    try! fs.createDirectory(AbsolutePath("/t3/lib/sourcekitd.framework"), recursive: true)
    XCTAssertNil(Toolchain(path: AbsolutePath("/t3"), fileSystem: fs))
    makeToolchain(binPath: AbsolutePath("/t3/bin"), fileSystem: fs, sourcekitd: true)
    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t3"), fileSystem: fs))
  }

  static var allTests = [
    ("testDefaultBasic", testDefaultBasic),
    ("testDefaultDarwin", testDefaultDarwin),
    ("testUnknownPlatform", testUnknownPlatform),
    ("testSearchDarwin", testSearchDarwin),
    ("testSearchPATH", testSearchPATH),
    ("testFromDirectory", testFromDirectory),
    ]
}

#if os(macOS)
private func makeXCToolchain(
  identifier: String,
  opensource: Bool,
  path: AbsolutePath,
  fileSystem fs: FileSystem,
  clang: Bool = false,
  clangd: Bool = false,
  swiftc: Bool = false,
  shouldChmod: Bool = true, // whether to mark exec
  sourcekitd: Bool = false,
  sourcekitdInProc: Bool = false,
  libIndexStore: Bool = false
) {
  try! fs.createDirectory(path, recursive: true)
  let infoPlistPath = path.appending(component: opensource ? "Info.plist" : "ToolchainInfo.plist")
  let infoPlist = try! PropertyListEncoder().encode(
    XCToolchainPlist(identifier: identifier, displayName: "name-\(identifier)"))
  try! fs.writeFileContents(infoPlistPath, body: { stream in
    stream.write(infoPlist)
  })

  makeToolchain(
    binPath: path.appending(components: "usr", "bin"),
    fileSystem: fs,
    clang: clang,
    clangd: clangd,
    swiftc: swiftc,
    shouldChmod: shouldChmod,
    sourcekitd: sourcekitd,
    sourcekitdInProc: sourcekitdInProc,
    libIndexStore: libIndexStore)
}
#endif

private func makeToolchain(
  binPath: AbsolutePath,
  fileSystem fs: FileSystem,
  clang: Bool = false,
  clangd: Bool = false,
  swiftc: Bool = false,
  shouldChmod: Bool = true, // whether to mark exec
  sourcekitd: Bool = false,
  sourcekitdInProc: Bool = false,
  libIndexStore: Bool = false
) {
  precondition(!clang && !swiftc && !clangd || fs === localFileSystem || !shouldChmod,
    "Cannot make toolchain binaries exectuable with InMemoryFileSystem")

  let libPath = binPath.parentDirectory.appending(component: "lib")
  try! fs.createDirectory(binPath, recursive: true)
  try! fs.createDirectory(libPath)

  let makeExec = { (path: AbsolutePath) in
    try! fs.writeFileContents(path , bytes: "")
    if shouldChmod {
      XCTAssertEqual(chmod(path.asString, S_IRUSR | S_IXUSR), 0)
    }
  }

  if clang {
    makeExec(binPath.appending(component: "clang"))
  }
  if clangd {
    makeExec(binPath.appending(component: "clangd"))
  }
  if swiftc {
    makeExec(binPath.appending(component: "swiftc"))
  }

  let dylibExt = Platform.currentPlatform?.dynamicLibraryExtension ?? "so"

  if sourcekitd {
    try! fs.createDirectory(libPath.appending(component: "sourcekitd.framework"))
    try! fs.writeFileContents(libPath.appending(components: "sourcekitd.framework", "sourcekitd") , bytes: "")
  }
  if sourcekitdInProc {
    try! fs.writeFileContents(libPath.appending(component: "libsourcekitdInProc.\(dylibExt)") , bytes: "")
  }
  if libIndexStore {
    try! fs.writeFileContents(libPath.appending(component: "libIndexStore.\(dylibExt)") , bytes: "")
  }
}
