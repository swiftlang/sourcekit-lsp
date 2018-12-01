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

    let makeToolchain = { (binPath: AbsolutePath) in
      let libPath = binPath.parentDirectory.appending(component: "lib")
      try! fs.createDirectory(libPath, recursive: true)
      try! fs.writeFileContents(libPath.appending(components: "libsourcekitdInProc.so") , bytes: "")
    }

    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath)

    guard let t = Toolchain(path: binPath, fileSystem: fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
  }

  func testSearchDarwin() {
// FIXME: requires PropertyListEncoder
#if os(macOS)
    let prevPlatform = Platform.currentPlatform
    defer { Platform.currentPlatform = prevPlatform }
    Platform.currentPlatform = .darwin

    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fileSystem: fs)

    let xcodeDeveloper = tr.currentXcodeDeveloperPath!
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    let makeToolchain = { (id: String, opensource: Bool, path: AbsolutePath) in
      let skpath: AbsolutePath = path.appending(components: "usr", "lib", "sourcekitd.framework")
      try! fs.createDirectory(skpath, recursive: true)
      try! fs.writeFileContents(skpath.appending(component: "sourcekitd"), bytes: "")

      let infoPlistPath = path.appending(component: opensource ? "Info.plist" : "ToolchainInfo.plist")
      let infoPlist = try! PropertyListEncoder().encode(XCToolchainPlist(identifier: id, displayName: "name-\(id)"))
      try! fs.writeFileContents(infoPlistPath, body: { stream in
        stream.write(infoPlist)
      })
    }

    makeToolchain(ToolchainRegistry.darwinDefaultToolchainID, false, toolchains.appending(component: "XcodeDefault.xctoolchain"))

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

    makeToolchain("com.apple.fake.A", false, toolchains.appending(component: "A.xctoolchain"))
    makeToolchain("com.apple.fake.B", false, toolchains.appending(component: "B.xctoolchain"))

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 3)

    makeToolchain("com.apple.fake.C", false, toolchains.appending(component: "C.wrong_extension"))
    makeToolchain("com.apple.fake.D", false, toolchains.appending(component: "D_no_extension"))

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 3)

    makeToolchain("com.apple.fake.A", false, toolchains.appending(component: "E.xctoolchain"))

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 3)

    makeToolchain("org.fake.global.A", true, AbsolutePath("/Library/Developer/Toolchains/A.xctoolchain"))
    makeToolchain("org.fake.global.B", true, AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains/B.xctoolchain"))

    tr.scanForToolchains()
    XCTAssertEqual(tr.toolchains.count, 5)

    let path = toolchains.appending(component: "Explicit.xctoolchain")
    makeToolchain("org.fake.explicit", false, path)
    let tc = Toolchain(path: path, fileSystem: fs)
    XCTAssertNotNil(tc)
    XCTAssertEqual(tc?.identifier, "org.fake.explicit")
#endif
  }

  func testSearchPATH() {
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fileSystem: fs)

    let makeToolchain = { (binPath: AbsolutePath) in
      let libPath = binPath.parentDirectory.appending(component: "lib")
      try! fs.createDirectory(binPath, recursive: true)
      try! fs.createDirectory(libPath.appending(component: "sourcekitd.framework"), recursive: true)
      try! fs.writeFileContents(libPath.appending(components: "sourcekitd.framework", "sourcekitd") , bytes: "")
    }

    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath)

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

    let makeToolchain = { (binPath: AbsolutePath) in
      let libPath = binPath.parentDirectory.appending(component: "lib")
      try! fs.createDirectory(binPath, recursive: true)
      try! fs.createDirectory(libPath.appending(component: "sourcekitd.framework"), recursive: true)
      try! fs.writeFileContents(libPath.appending(components: "sourcekitd.framework", "sourcekitd") , bytes: "")
    }

    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath)

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
    try! fs.createDirectory(path.appending(component: "bin"), recursive: true)
    try! fs.createDirectory(path.appending(components: "lib", "sourcekitd.framework"), recursive: true)
    try! fs.writeFileContents(path.appending(components: "bin", "clang") , bytes: "")
    try! fs.writeFileContents(path.appending(components: "bin", "clangd") , bytes: "")
    try! fs.writeFileContents(path.appending(components: "bin", "swiftc") , bytes: "")
    try! fs.writeFileContents(path.appending(components: "bin", "other") , bytes: "")
    try! fs.writeFileContents(path.appending(components: "lib", "sourcekitd.framework", "sourcekitd") , bytes: "")

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

    let ext = Platform.currentPlatform?.dynamicLibraryExtension ?? "so"

    let makeToolchain = { (binPath: AbsolutePath) in
      let libPath = binPath.parentDirectory.appending(component: "lib")
      try! fs.createDirectory(libPath, recursive: true)
      try! fs.writeFileContents(libPath.appending(component: "libsourcekitdInProc.\(ext)") , bytes: "")
      try! fs.writeFileContents(libPath.appending(component: "libIndexStore.\(ext)") , bytes: "")
    }

    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath)

    guard let t = Toolchain(path: binPath, fileSystem: fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
    XCTAssertNotNil(t.libIndexStore)
  }

  func testSubDirs() {
    let fs = InMemoryFileSystem()

    let makeToolchain = { (binPath: AbsolutePath) in
      let libPath = binPath.parentDirectory.appending(component: "lib")
      try! fs.createDirectory(libPath.appending(component: "sourcekitd.framework"), recursive: true)
      try! fs.writeFileContents(libPath.appending(components: "sourcekitd.framework", "sourcekitd") , bytes: "")
    }

    makeToolchain(AbsolutePath("/t1/bin"))
    makeToolchain(AbsolutePath("/t2/usr/bin"))

    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t1"), fileSystem: fs))
    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t1/bin"), fileSystem: fs))
    XCTAssertNotNil(Toolchain(path: AbsolutePath("/t2"), fileSystem: fs))

    XCTAssertNil(Toolchain(path: AbsolutePath("/t3"), fileSystem: fs))
    try! fs.createDirectory(AbsolutePath("/t3/bin"), recursive: true)
    try! fs.createDirectory(AbsolutePath("/t3/lib/sourcekitd.framework"), recursive: true)
    XCTAssertNil(Toolchain(path: AbsolutePath("/t3"), fileSystem: fs))
    makeToolchain(AbsolutePath("/t3/bin"))
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
