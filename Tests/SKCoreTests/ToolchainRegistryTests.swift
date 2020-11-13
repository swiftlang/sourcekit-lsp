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

import SKCore
import TSCBasic
import TSCUtility
import XCTest

final class ToolchainRegistryTests: XCTestCase {
  func testDefaultBasic() {
    let tr = ToolchainRegistry()
    XCTAssertNil(tr.default)
    try! tr.registerToolchain(Toolchain(identifier: "a", displayName: "a", path: nil))
    XCTAssertEqual(tr.default?.identifier, "a")
    let b = Toolchain(identifier: "b", displayName: "b", path: nil)
    try! tr.registerToolchain(b)
    XCTAssertEqual(tr.default?.identifier, "a")
    tr.default = b
    XCTAssertEqual(tr.default?.identifier, "b")
    tr.default = nil
    XCTAssertEqual(tr.default?.identifier, "a")
    XCTAssert(tr.default === tr.toolchain(identifier: "a"))
  }

  func testDefaultDarwin() {
    let prevPlatform = Platform.currentPlatform
    defer { Platform.currentPlatform = prevPlatform }
    Platform.currentPlatform = .darwin

    let tr = ToolchainRegistry()
    tr.darwinToolchainOverride = nil
    XCTAssertNil(tr.default)
    let a = Toolchain(identifier: "a", displayName: "a", path: nil)
    try! tr.registerToolchain(a)
    try! tr.registerToolchain(Toolchain(identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier, displayName: "a", path: nil))
    XCTAssertEqual(tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)
    tr.default = a
    XCTAssertEqual(tr.default?.identifier, "a")
    tr.default = nil
    XCTAssertEqual(tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)
  }

  func testUnknownPlatform() {
    let prevPlatform = Platform.currentPlatform
    defer { Platform.currentPlatform = prevPlatform }
    Platform.currentPlatform = nil

    let fs = InMemoryFileSystem()
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fs, sourcekitdInProc: true)

    guard let t = Toolchain(binPath, fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
  }

  func testSearchDarwin() {
// FIXME: requires PropertyListEncoder
#if os(macOS)
    let fs = InMemoryFileSystem()
    let tr1 = ToolchainRegistry(fs)
    tr1.darwinToolchainOverride = nil

    let xcodeDeveloper = ToolchainRegistry.currentXcodeDeveloperPath!
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    makeXCToolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      opensource: false,
      toolchains.appending(component: "XcodeDefault.xctoolchain"), fs,
      sourcekitd: true)

    XCTAssertNil(tr1.default)
    XCTAssert(tr1.toolchains.isEmpty)

    tr1.scanForToolchains(xcode: xcodeDeveloper, fs)

    XCTAssertEqual(tr1.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)
    XCTAssertEqual(tr1.default?.path, toolchains.appending(component: "XcodeDefault.xctoolchain"))
    XCTAssertNotNil(tr1.default?.sourcekitd)
    XCTAssertEqual(tr1.toolchains.count, 1)

    let tr = ToolchainRegistry(fs)
    tr.darwinToolchainOverride = nil

    XCTAssertEqual(tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)
    XCTAssertEqual(tr.default?.path, toolchains.appending(component: "XcodeDefault.xctoolchain"))
    XCTAssertNotNil(tr.default?.sourcekitd)
    XCTAssertEqual(tr.toolchains.count, 1)

    let defaultToolchain = tr.default!

    XCTAssert(tr.toolchains.first === defaultToolchain)

    makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      toolchains.appending(component: "A.xctoolchain"), fs,
      sourcekitd: true)
    makeXCToolchain(
      identifier: "com.apple.fake.B",
      opensource: false,
      toolchains.appending(component: "B.xctoolchain"), fs,
      sourcekitd: true)

    tr.scanForToolchains(fs)
    XCTAssertEqual(tr.toolchains.count, 3)

    makeXCToolchain(
      identifier: "com.apple.fake.C",
      opensource: false,
      toolchains.appending(component: "C.wrong_extension"), fs,
      sourcekitd: true)
    makeXCToolchain(
      identifier: "com.apple.fake.D",
      opensource: false,
      toolchains.appending(component: "D_no_extension"), fs,
      sourcekitd: true)

    tr.scanForToolchains(fs)
    XCTAssertEqual(tr.toolchains.count, 3)

    makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      toolchains.appending(component: "E.xctoolchain"), fs,
      sourcekitd: true)

    tr.scanForToolchains(fs)
    XCTAssertEqual(tr.toolchains.count, 3)

    makeXCToolchain(
      identifier: "org.fake.global.A",
      opensource: true,
      AbsolutePath("/Library/Developer/Toolchains/A.xctoolchain"), fs,
      sourcekitd: true)
    makeXCToolchain(
      identifier: "org.fake.global.B",
      opensource: true,
      AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains/B.xctoolchain"), fs,
      sourcekitd: true)

    tr.scanForToolchains(fs)
    XCTAssertEqual(tr.toolchains.count, 5)

    let path = toolchains.appending(component: "Explicit.xctoolchain")
    makeXCToolchain(
      identifier: "org.fake.explicit",
      opensource: false,
      toolchains.appending(component: "Explicit.xctoolchain"), fs,
      sourcekitd: true)

    let tc = Toolchain(path, fs)
    XCTAssertNotNil(tc)
    XCTAssertEqual(tc?.identifier, "org.fake.explicit")

    let tcBin = Toolchain(path.appending(components: "usr", "bin"), fs)
    XCTAssertNotNil(tcBin)
    XCTAssertEqual(tc?.identifier, tcBin?.identifier)
    XCTAssertEqual(tc?.path, tcBin?.path)
    XCTAssertEqual(tc?.displayName, tcBin?.displayName)


    let trInstall = ToolchainRegistry()
    trInstall.scanForToolchains(installPath: path.appending(components: "usr", "bin"), environmentVariables: [], xcodes: [], xctoolchainSearchPaths: [], pathVariables: [], fs)
    XCTAssertEqual(trInstall.default?.identifier, "org.fake.explicit")
    XCTAssertEqual(trInstall.default?.path, path)

    let overrideReg = ToolchainRegistry(fs)
    overrideReg.darwinToolchainOverride = "org.fake.global.B"
    XCTAssertEqual(overrideReg.darwinToolchainIdentifier, "org.fake.global.B")
    XCTAssertEqual(overrideReg.default?.identifier, "org.fake.global.B")

    let checkByDir = ToolchainRegistry()
    checkByDir.scanForToolchains(xctoolchainSearchPath: toolchains, fs)
    XCTAssertEqual(checkByDir.toolchains.count, 4)
#endif
  }

  func testSearchPATH() {
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fs)
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fs, sourcekitd: true)

    XCTAssertNil(tr.default)
    XCTAssert(tr.toolchains.isEmpty)

    try! ProcessEnv.setVar("SOURCEKIT_PATH", value: "/bogus:\(binPath):/bogus2")
    defer { try! ProcessEnv.setVar("SOURCEKIT_PATH", value: "") }

    tr.scanForToolchains(fs)

    guard let tc = tr.toolchains.first(where: { tc in tc.path == binPath }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    XCTAssertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc.identifier, binPath.pathString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)

    let binPath2 = AbsolutePath("/other/my_toolchain/bin")
    try! ProcessEnv.setVar("SOME_TEST_ENV_PATH", value: "/bogus:\(binPath2):/bogus2")
    makeToolchain(binPath: binPath2, fs, sourcekitd: true)
    tr.scanForToolchains(pathVariables: ["NOPE", "SOME_TEST_ENV_PATH", "MORE_NOPE"], fs)

    guard let tc2 = tr.toolchains.first(where: { tc in tc.path == binPath2 }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    XCTAssertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc2.identifier, binPath2.pathString)
    XCTAssertNotNil(tc2.sourcekitd)
  }

  func testSearchExplicitEnvBuiltin() {
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fs)
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fs, sourcekitd: true)

    XCTAssertNil(tr.default)
    XCTAssert(tr.toolchains.isEmpty)

    try! ProcessEnv.setVar("TEST_SOURCEKIT_TOOLCHAIN_PATH_1", value: binPath.parentDirectory.pathString)

    tr.scanForToolchains(environmentVariables: ["TEST_SOURCEKIT_TOOLCHAIN_PATH_1"], fs)

    guard let tc = tr.toolchains.first(where: { tc in tc.path == binPath.parentDirectory }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    XCTAssertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc.identifier, binPath.parentDirectory.pathString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)
  }

  func testSearchExplicitEnv() {
    let fs = InMemoryFileSystem()
    let tr = ToolchainRegistry(fs)
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fs, sourcekitd: true)

    XCTAssertNil(tr.default)
    XCTAssert(tr.toolchains.isEmpty)

    try! ProcessEnv.setVar("TEST_ENV_SOURCEKIT_TOOLCHAIN_PATH_2", value: binPath.parentDirectory.pathString)

    tr.scanForToolchains(
      environmentVariables: ["TEST_ENV_SOURCEKIT_TOOLCHAIN_PATH_2"],
      setDefault: false,
      fs)

    guard let tc = tr.toolchains.first(where: { tc in tc.path == binPath.parentDirectory }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    XCTAssertEqual(tc.identifier, binPath.parentDirectory.pathString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)
  }

  func testFromDirectory() {
    // This test uses the real file system because the in-memory system doesn't support marking files executable.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      let path = tempDir.appending(components: "A.xctoolchain", "usr")
      makeToolchain(
        binPath: path.appending(component: "bin"), fs,
        clang: true,
        clangd: true,
        swiftc: true,
        shouldChmod: false,
        sourcekitd: true)

      try! fs.writeFileContents(path.appending(components: "bin", "other") , bytes: "")

      let t1 = Toolchain(path.parentDirectory, fs)!
      XCTAssertNotNil(t1.sourcekitd)
      XCTAssertNil(t1.clang)
      XCTAssertNil(t1.clangd)
      XCTAssertNil(t1.swiftc)

#if !os(Windows)
      func chmodRX(_ path: AbsolutePath) {
        XCTAssertEqual(chmod(path.pathString, S_IRUSR | S_IXUSR), 0)
      }

      chmodRX(path.appending(components: "bin", "clang"))
      chmodRX(path.appending(components: "bin", "clangd"))
      chmodRX(path.appending(components: "bin", "swiftc"))
      chmodRX(path.appending(components: "bin", "other"))
#endif

      let t2 = Toolchain(path.parentDirectory, fs)!
      XCTAssertNotNil(t2.sourcekitd)
      XCTAssertNotNil(t2.clang)
      XCTAssertNotNil(t2.clangd)
      XCTAssertNotNil(t2.swiftc)

      let tr = ToolchainRegistry()
      let t3 = try! tr.registerToolchain(path.parentDirectory, fs)
      XCTAssertEqual(t3.identifier, t2.identifier)
      XCTAssertEqual(t3.sourcekitd, t2.sourcekitd)
      XCTAssertEqual(t3.clang, t2.clang)
      XCTAssertEqual(t3.clangd, t2.clangd)
      XCTAssertEqual(t3.swiftc, t2.swiftc)
    }
  }

  func testDylibNames() {
    let fs = InMemoryFileSystem()
    let binPath = AbsolutePath("/foo/bar/my_toolchain/bin")
    makeToolchain(binPath: binPath, fs, sourcekitdInProc: true, libIndexStore: true)
    guard let t = Toolchain(binPath, fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
    XCTAssertNotNil(t.libIndexStore)
  }

  func testSubDirs() {
    let fs = InMemoryFileSystem()
    makeToolchain(binPath: AbsolutePath("/t1/bin"), fs, sourcekitd: true)
    makeToolchain(binPath: AbsolutePath("/t2/usr/bin"), fs, sourcekitd: true)

    XCTAssertNotNil(Toolchain(AbsolutePath("/t1"), fs))
    XCTAssertNotNil(Toolchain(AbsolutePath("/t1/bin"), fs))
    XCTAssertNotNil(Toolchain(AbsolutePath("/t2"), fs))

    XCTAssertNil(Toolchain(AbsolutePath("/t3"), fs))
    try! fs.createDirectory(AbsolutePath("/t3/bin"), recursive: true)
    try! fs.createDirectory(AbsolutePath("/t3/lib/sourcekitd.framework"), recursive: true)
    XCTAssertNil(Toolchain(AbsolutePath("/t3"), fs))
    makeToolchain(binPath: AbsolutePath("/t3/bin"), fs, sourcekitd: true)
    XCTAssertNotNil(Toolchain(AbsolutePath("/t3"), fs))
  }

  func testDuplicateError() {
    let tr = ToolchainRegistry()
    let toolchain = Toolchain(identifier: "a", displayName: "a", path: nil)
    XCTAssertNoThrow(try tr.registerToolchain(toolchain), "Error registering toolchain")
    XCTAssertThrowsError(try tr.registerToolchain(toolchain),
                         "Expected error registering toolchain twice") { e in
      guard let error = e as? ToolchainRegistry.Error, error == .duplicateToolchainIdentifier else {
        XCTFail("Expected .duplicateToolchainIdentifier not \(e)")
        return
      }
    }
  }

  func testDuplicatePathError() {
    let tr = ToolchainRegistry()
    let path = AbsolutePath("/foo/bar")
    let first = Toolchain(identifier: "a", displayName: "a", path: path)
    let second = Toolchain(identifier: "b", displayName: "b", path: path)
    XCTAssertNoThrow(try tr.registerToolchain(first), "Error registering toolchain")
    XCTAssertThrowsError(try tr.registerToolchain(second),
                         "Expected error registering toolchain twice") { e in
      guard let error = e as? ToolchainRegistry.Error, error == .duplicateToolchainPath else {
        XCTFail("Error mismatch: expected duplicateToolchainPath not \(e)")
        return
      }
    }
  }

  func testDuplicateXcodeError() {
    let tr = ToolchainRegistry()
    let xcodeToolchain = Toolchain(identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
                                   displayName: "a",
                                   path: AbsolutePath("/versionA"))
    XCTAssertNoThrow(try tr.registerToolchain(xcodeToolchain), "Error registering toolchain")
    XCTAssertThrowsError(try tr.registerToolchain(xcodeToolchain),
                         "Expected error registering toolchain twice") { e in
      guard let error = e as? ToolchainRegistry.Error, error == .duplicateToolchainPath else {
        XCTFail("Error mismatch: expected duplicateToolchainPath not \(e)")
        return
      }
    }
  }

  func testMultipleXcodes() {
    let tr = ToolchainRegistry()
    let pathA = AbsolutePath("/versionA")
    let xcodeA = Toolchain(identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
                           displayName: "a",
                           path: pathA)
    let pathB = AbsolutePath("/versionB")
    let xcodeB = Toolchain(identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
                           displayName: "b",
                           path: pathB)
    XCTAssertNoThrow(try tr.registerToolchain(xcodeA))
    XCTAssertNoThrow(try tr.registerToolchain(xcodeB))
    XCTAssert(tr.toolchain(path: pathA) === xcodeA)
    XCTAssert(tr.toolchain(path: pathB) === xcodeB)

    let toolchains = tr.toolchains(identifier: xcodeA.identifier)
    XCTAssert(toolchains.count == 2)
    XCTAssert(toolchains[0] === xcodeA)
    XCTAssert(toolchains[1] === xcodeB)
  }

  func testInstallPath() {
    let fs = InMemoryFileSystem()
    makeToolchain(binPath: AbsolutePath("/t1/bin"), fs, sourcekitd: true)

    let trEmpty = ToolchainRegistry(installPath: nil, fs)
    XCTAssertNil(trEmpty.default)

    let tr1 = ToolchainRegistry(installPath: AbsolutePath("/t1/bin"), fs)
    XCTAssertEqual(tr1.default?.path, AbsolutePath("/t1/bin"))
    XCTAssertNotNil(tr1.default?.sourcekitd)

    let tr2 = ToolchainRegistry(installPath: AbsolutePath("/t2/bin"), fs)
    XCTAssertNil(tr2.default)
  }

  func testInstallPathVsEnv() {
    let fs = InMemoryFileSystem()
    makeToolchain(binPath: AbsolutePath("/t1/bin"), fs, sourcekitd: true)
    makeToolchain(binPath: AbsolutePath("/t2/bin"), fs, sourcekitd: true)

    try! ProcessEnv.setVar("TEST_SOURCEKIT_TOOLCHAIN_PATH_1", value: "/t2/bin")

    let tr = ToolchainRegistry()
    tr.scanForToolchains(installPath: AbsolutePath("/t1/bin"), environmentVariables: ["TEST_SOURCEKIT_TOOLCHAIN_PATH_1"], fs)
    XCTAssertEqual(tr.toolchains.count, 2)

    // Env variable wins.
    XCTAssertEqual(tr.default?.path, AbsolutePath("/t2/bin"))
  }
}

#if os(macOS)
private func makeXCToolchain(
  identifier: String,
  opensource: Bool,
  _ path: AbsolutePath,
  _ fs: FileSystem,
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
    fs,
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
  _ fs: FileSystem,
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
#if !os(Windows)
    if shouldChmod {
      XCTAssertEqual(chmod(path.pathString, S_IRUSR | S_IXUSR), 0)
    }
#endif
  }

  let execExt = Platform.currentPlatform?.executableExtension ?? ""

  if clang {
    makeExec(binPath.appending(component: "clang\(execExt)"))
  }
  if clangd {
    makeExec(binPath.appending(component: "clangd\(execExt)"))
  }
  if swiftc {
    makeExec(binPath.appending(component: "swiftc\(execExt)"))
  }

  let dylibExt = Platform.currentPlatform?.dynamicLibraryExtension ?? ".so"

  if sourcekitd {
    try! fs.createDirectory(libPath.appending(component: "sourcekitd.framework"))
    try! fs.writeFileContents(libPath.appending(components: "sourcekitd.framework", "sourcekitd") , bytes: "")
  }
  if sourcekitdInProc {
    try! fs.writeFileContents(libPath.appending(component: "libsourcekitdInProc\(dylibExt)") , bytes: "")
  }
  if libIndexStore {
    try! fs.writeFileContents(libPath.appending(component: "libIndexStore\(dylibExt)") , bytes: "")
  }
}
