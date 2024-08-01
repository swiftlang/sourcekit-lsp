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

import SKTestSupport
import TSCBasic
import ToolchainRegistry
import XCTest

import enum PackageLoading.Platform

final class ToolchainRegistryTests: XCTestCase {
  func testDefaultSingleToolchain() async throws {
    let tr = ToolchainRegistry(toolchains: [Toolchain(identifier: "a", displayName: "a", path: nil)])
    await assertEqual(tr.default?.identifier, "a")
  }

  func testDefaultTwoToolchains() async throws {
    let tr = ToolchainRegistry(
      toolchains: [
        Toolchain(identifier: "a", displayName: "a", path: nil),
        Toolchain(identifier: "b", displayName: "b", path: nil),
      ]
    )
    await assertEqual(tr.default?.identifier, "a")
    await assertTrue(tr.default === tr.toolchains(withIdentifier: "a").only)
  }

  func testFindXcodeDefaultToolchain() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")
    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")
    try makeXCToolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      opensource: false,
      path: toolchains.appending(component: "XcodeDefault.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let tr = ToolchainRegistry(
      xcodes: [xcodeDeveloper],
      darwinToolchainOverride: nil,
      fs
    )

    assertEqual(await tr.toolchains.count, 1)
    assertEqual(await tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)
    assertEqual(await tr.default?.path, toolchains.appending(component: "XcodeDefault.xctoolchain"))
    assertNotNil(await tr.default?.sourcekitd)

    assertTrue(await tr.toolchains.first === tr.default)
  }

  func testFindNonXcodeDefaultToolchains() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")
    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    try makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      path: toolchains.appending(component: "A.xctoolchain"),
      fs,
      sourcekitd: true
    )
    try makeXCToolchain(
      identifier: "com.apple.fake.B",
      opensource: false,
      path: toolchains.appending(component: "B.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let tr = ToolchainRegistry(
      xcodes: [xcodeDeveloper],
      darwinToolchainOverride: nil,
      fs
    )

    assertEqual(await tr.toolchains.map(\.identifier).sorted(), ["com.apple.fake.A", "com.apple.fake.B"])
  }

  func testIgnoreToolchainsWithWrongExtensions() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")
    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    try makeXCToolchain(
      identifier: "com.apple.fake.C",
      opensource: false,
      path: toolchains.appending(component: "C.wrong_extension"),
      fs,
      sourcekitd: true
    )
    try makeXCToolchain(
      identifier: "com.apple.fake.D",
      opensource: false,
      path: toolchains.appending(component: "D_no_extension"),
      fs,
      sourcekitd: true
    )

    let tr = ToolchainRegistry(
      darwinToolchainOverride: nil,
      fs
    )

    assertTrue(await tr.toolchains.isEmpty)

  }
  func testTwoToolchainsWithSameIdentifier() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")
    try makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      path: toolchains.appending(component: "A.xctoolchain"),
      fs,
      sourcekitd: true
    )

    try makeXCToolchain(
      identifier: "com.apple.fake.A",
      opensource: false,
      path: toolchains.appending(component: "E.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let tr = ToolchainRegistry(
      xcodes: [xcodeDeveloper],
      darwinToolchainOverride: nil,
      fs
    )

    assertEqual(await tr.toolchains.count, 1)
  }

  func testGloballyInstalledToolchains() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")
    let fs = InMemoryFileSystem()

    try makeXCToolchain(
      identifier: "org.fake.global.A",
      opensource: true,
      path: try AbsolutePath(validating: "/Library/Developer/Toolchains/A.xctoolchain"),
      fs,
      sourcekitd: true
    )
    try makeXCToolchain(
      identifier: "org.fake.global.B",
      opensource: true,
      path: try AbsolutePath(expandingTilde: "~/Library/Developer/Toolchains/B.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let tr = ToolchainRegistry(
      darwinToolchainOverride: nil,
      fs
    )
    assertEqual(await tr.toolchains.map(\.identifier), ["org.fake.global.B", "org.fake.global.A"])
  }

  func testFindToolchainBasedOnInstallPath() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")
    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    let path = toolchains.appending(component: "Explicit.xctoolchain")
    try makeXCToolchain(
      identifier: "org.fake.explicit",
      opensource: false,
      path: toolchains.appending(component: "Explicit.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let trInstall = ToolchainRegistry(
      installPath: path.appending(components: "usr", "bin"),
      xcodes: [],
      darwinToolchainOverride: nil,
      fs
    )
    await assertEqual(trInstall.default?.identifier, "org.fake.explicit")
    await assertEqual(trInstall.default?.path, path)
  }

  func testDarwinToolchainOverride() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")
    try makeXCToolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      opensource: false,
      path: toolchains.appending(component: "XcodeDefault.xctoolchain"),
      fs,
      sourcekitd: true
    )

    try makeXCToolchain(
      identifier: "org.fake.global.A",
      opensource: false,
      path: toolchains.appending(component: "A.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let toolchainRegistry = ToolchainRegistry(
      xcodes: [xcodeDeveloper],
      darwinToolchainOverride: nil,
      fs
    )
    await assertEqual(toolchainRegistry.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)

    let darwinToolchainOverrideRegistry = ToolchainRegistry(
      xcodes: [xcodeDeveloper],
      darwinToolchainOverride: "org.fake.global.A",
      fs
    )
    await assertEqual(darwinToolchainOverrideRegistry.darwinToolchainIdentifier, "org.fake.global.A")
    await assertEqual(darwinToolchainOverrideRegistry.default?.identifier, "org.fake.global.A")
  }

  func testCreateToolchainFromBinPath() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    let fs = InMemoryFileSystem()
    let xcodeDeveloper = try AbsolutePath(validating: "/Applications/Xcode.app/Developer")
    let toolchains = xcodeDeveloper.appending(components: "Toolchains")

    let path = toolchains.appending(component: "Explicit.xctoolchain")
    try makeXCToolchain(
      identifier: "org.fake.explicit",
      opensource: false,
      path: toolchains.appending(component: "Explicit.xctoolchain"),
      fs,
      sourcekitd: true
    )

    let tc = Toolchain(path, fs)
    XCTAssertNotNil(tc)
    XCTAssertEqual(tc?.identifier, "org.fake.explicit")

    let tcBin = Toolchain(path.appending(components: "usr", "bin"), fs)
    XCTAssertNotNil(tcBin)
    XCTAssertEqual(tc?.identifier, tcBin?.identifier)
    XCTAssertEqual(tc?.path, tcBin?.path)
    XCTAssertEqual(tc?.displayName, tcBin?.displayName)
  }

  func testSearchPATH() async throws {
    let fs = InMemoryFileSystem()
    let binPath = try AbsolutePath(validating: "/foo/bar/my_toolchain/bin")
    try makeToolchain(binPath: binPath, fs, sourcekitd: true)

    #if os(Windows)
    let separator: String = ";"
    #else
    let separator: String = ":"
    #endif

    try ProcessEnv.setVar(
      "SOURCEKIT_PATH",
      value: ["/bogus", binPath.pathString, "/bogus2"].joined(separator: separator)
    )
    defer { try! ProcessEnv.setVar("SOURCEKIT_PATH", value: "") }

    let tr = ToolchainRegistry(fs)

    let tc = try unwrap(await tr.toolchains.first(where: { tc in tc.path == binPath }))

    await assertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc.identifier, binPath.pathString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)
  }

  func testSearchExplicitEnvBuiltin() async throws {
    let fs = InMemoryFileSystem()

    let binPath = try AbsolutePath(validating: "/foo/bar/my_toolchain/bin")
    try makeToolchain(binPath: binPath, fs, sourcekitd: true)

    try ProcessEnv.setVar("TEST_SOURCEKIT_TOOLCHAIN_PATH_1", value: binPath.parentDirectory.pathString)

    let tr = ToolchainRegistry(
      environmentVariables: ["TEST_SOURCEKIT_TOOLCHAIN_PATH_1"],
      fs
    )

    guard let tc = await tr.toolchains.first(where: { tc in tc.path == binPath.parentDirectory }) else {
      XCTFail("couldn't find expected toolchain")
      return
    }

    await assertEqual(tr.default?.identifier, tc.identifier)
    XCTAssertEqual(tc.identifier, binPath.parentDirectory.pathString)
    XCTAssertNil(tc.clang)
    XCTAssertNil(tc.clangd)
    XCTAssertNil(tc.swiftc)
    XCTAssertNotNil(tc.sourcekitd)
    XCTAssertNil(tc.libIndexStore)
  }

  func testSearchExplicitEnv() async throws {
    let fs = InMemoryFileSystem()
    let binPath = try AbsolutePath(validating: "/foo/bar/my_toolchain/bin")
    try makeToolchain(binPath: binPath, fs, sourcekitd: true)

    try ProcessEnv.setVar("TEST_ENV_SOURCEKIT_TOOLCHAIN_PATH_2", value: binPath.parentDirectory.pathString)

    let tr = ToolchainRegistry(
      environmentVariables: ["TEST_ENV_SOURCEKIT_TOOLCHAIN_PATH_2"],
      fs
    )

    guard let tc = await tr.toolchains.first(where: { tc in tc.path == binPath.parentDirectory }) else {
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

  func testFromDirectory() async throws {
    // This test uses the real file system because the in-memory system doesn't support marking files executable.
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      let path = tempDir.appending(components: "A.xctoolchain", "usr")
      try makeToolchain(
        binPath: path.appending(component: "bin"),
        fs,
        clang: true,
        clangd: true,
        swiftc: true,
        shouldChmod: false,
        sourcekitd: true
      )

      try fs.writeFileContents(path.appending(components: "bin", "other"), bytes: "")

      let t1 = Toolchain(path.parentDirectory, fs)!
      XCTAssertNotNil(t1.sourcekitd)
      #if os(Windows)
      // Windows does not have file permissions but rather checks the contents
      // which have been written out.
      XCTAssertNotNil(t1.clang)
      XCTAssertNotNil(t1.clangd)
      XCTAssertNotNil(t1.swiftc)
      #else
      XCTAssertNil(t1.clang)
      XCTAssertNil(t1.clangd)
      XCTAssertNil(t1.swiftc)
      #endif

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

      let tr = ToolchainRegistry(toolchains: [Toolchain(path.parentDirectory, fs)!])
      let t3 = try await unwrap(tr.toolchains(withIdentifier: t2.identifier).only)
      XCTAssertEqual(t3.sourcekitd, t2.sourcekitd)
      XCTAssertEqual(t3.clang, t2.clang)
      XCTAssertEqual(t3.clangd, t2.clangd)
      XCTAssertEqual(t3.swiftc, t2.swiftc)
    }
  }

  func testDylibNames() throws {
    let fs = InMemoryFileSystem()
    let binPath = try AbsolutePath(validating: "/foo/bar/my_toolchain/bin")
    try makeToolchain(binPath: binPath, fs, sourcekitdInProc: true, libIndexStore: true)
    guard let t = Toolchain(binPath, fs) else {
      XCTFail("could not find any tools")
      return
    }
    XCTAssertNotNil(t.sourcekitd)
    XCTAssertNotNil(t.libIndexStore)
  }

  func testSubDirs() throws {
    let fs = InMemoryFileSystem()
    try makeToolchain(binPath: try AbsolutePath(validating: "/t1/bin"), fs, sourcekitd: true)
    try makeToolchain(binPath: try AbsolutePath(validating: "/t2/usr/bin"), fs, sourcekitd: true)

    XCTAssertNotNil(Toolchain(try AbsolutePath(validating: "/t1"), fs))
    XCTAssertNotNil(Toolchain(try AbsolutePath(validating: "/t1/bin"), fs))
    XCTAssertNotNil(Toolchain(try AbsolutePath(validating: "/t2"), fs))

    XCTAssertNil(Toolchain(try AbsolutePath(validating: "/t3"), fs))
    try fs.createDirectory(try AbsolutePath(validating: "/t3/bin"), recursive: true)
    try fs.createDirectory(try AbsolutePath(validating: "/t3/lib/sourcekitd.framework"), recursive: true)
    XCTAssertNil(Toolchain(try AbsolutePath(validating: "/t3"), fs))
    try makeToolchain(binPath: try AbsolutePath(validating: "/t3/bin"), fs, sourcekitd: true)
    XCTAssertNotNil(Toolchain(try AbsolutePath(validating: "/t3"), fs))
  }

  func testDuplicateToolchainOnlyRegisteredOnce() async throws {
    let toolchain = Toolchain(identifier: "a", displayName: "a", path: nil)
    let tr = ToolchainRegistry(toolchains: [toolchain, toolchain])
    assertEqual(await tr.toolchains.count, 1)
  }

  func testDuplicatePathOnlyRegisteredOnce() async throws {
    let path = try AbsolutePath(validating: "/foo/bar")
    let first = Toolchain(identifier: "a", displayName: "a", path: path)
    let second = Toolchain(identifier: "b", displayName: "b", path: path)

    let tr = ToolchainRegistry(toolchains: [first, second])
    assertEqual(await tr.toolchains.count, 1)
  }

  func testMultipleXcodes() async throws {
    let pathA = try AbsolutePath(validating: "/versionA")
    let xcodeA = Toolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      displayName: "a",
      path: pathA
    )
    let pathB = try AbsolutePath(validating: "/versionB")
    let xcodeB = Toolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      displayName: "b",
      path: pathB
    )
    let tr = ToolchainRegistry(toolchains: [xcodeA, xcodeB])
    await assertTrue(tr.toolchain(withPath: pathA) === xcodeA)
    await assertTrue(tr.toolchain(withPath: pathB) === xcodeB)

    let toolchains = await tr.toolchains(withIdentifier: xcodeA.identifier)
    XCTAssert(toolchains.count == 2)
    guard toolchains.count == 2 else {
      return
    }
    XCTAssert(toolchains[0] === xcodeA)
    XCTAssert(toolchains[1] === xcodeB)
  }

  func testInstallPath() async throws {
    let fs = InMemoryFileSystem()
    try makeToolchain(binPath: try AbsolutePath(validating: "/t1/bin"), fs, sourcekitd: true)

    let trEmpty = ToolchainRegistry(installPath: nil, fs)
    await assertNil(trEmpty.default)

    let tr1 = ToolchainRegistry(installPath: try AbsolutePath(validating: "/t1/bin"), fs)
    await assertEqual(tr1.default?.path, try AbsolutePath(validating: "/t1/bin"))
    await assertNotNil(tr1.default?.sourcekitd)

    let tr2 = ToolchainRegistry(installPath: try AbsolutePath(validating: "/t2/bin"), fs)
    await assertNil(tr2.default)
  }

  func testInstallPathVsEnv() async throws {
    let fs = InMemoryFileSystem()
    try makeToolchain(binPath: try AbsolutePath(validating: "/t1/bin"), fs, sourcekitd: true)
    try makeToolchain(binPath: try AbsolutePath(validating: "/t2/bin"), fs, sourcekitd: true)

    try ProcessEnv.setVar("TEST_SOURCEKIT_TOOLCHAIN_PATH_1", value: "/t2/bin")

    let tr = ToolchainRegistry(
      installPath: try AbsolutePath(validating: "/t1/bin"),
      environmentVariables: ["TEST_SOURCEKIT_TOOLCHAIN_PATH_1"],
      fs
    )
    await assertEqual(tr.toolchains.count, 2)

    // Env variable wins.
    await assertEqual(tr.default?.path, try AbsolutePath(validating: "/t2/bin"))
  }

  func testSupersetToolchains() async throws {
    let onlySwiftcToolchain = Toolchain(
      identifier: "onlySwiftc",
      displayName: "onlySwiftc",
      path: try AbsolutePath(validating: "/usr/local"),
      swiftc: try AbsolutePath(validating: "/usr/local/bin/swiftc")
    )
    let swiftcAndSourcekitdToolchain = Toolchain(
      identifier: "swiftcAndSourcekitd",
      displayName: "swiftcAndSourcekitd",
      path: try AbsolutePath(validating: "/usr"),
      swiftc: try AbsolutePath(validating: "/usr/bin/swiftc"),
      sourcekitd: try AbsolutePath(validating: "/usr/lib/sourcekitd.framework/sourcekitd")
    )

    let tr = ToolchainRegistry(toolchains: [onlySwiftcToolchain, swiftcAndSourcekitdToolchain])
    await assertEqual(tr.default?.identifier, "swiftcAndSourcekitd")
  }
}

private func makeXCToolchain(
  identifier: String,
  opensource: Bool,
  path: AbsolutePath,
  _ fs: FileSystem,
  clang: Bool = false,
  clangd: Bool = false,
  swiftc: Bool = false,
  shouldChmod: Bool = true,  // whether to mark exec
  sourcekitd: Bool = false,
  sourcekitdInProc: Bool = false,
  libIndexStore: Bool = false
) throws {
  try fs.createDirectory(path, recursive: true)
  let infoPlistPath = path.appending(component: opensource ? "Info.plist" : "ToolchainInfo.plist")
  let infoPlist = try PropertyListEncoder().encode(
    XCToolchainPlist(identifier: identifier, displayName: "name-\(identifier)")
  )
  try fs.writeFileContents(
    infoPlistPath,
    body: { stream in
      stream.write(infoPlist)
    }
  )

  try makeToolchain(
    binPath: path.appending(components: "usr", "bin"),
    fs,
    clang: clang,
    clangd: clangd,
    swiftc: swiftc,
    shouldChmod: shouldChmod,
    sourcekitd: sourcekitd,
    sourcekitdInProc: sourcekitdInProc,
    libIndexStore: libIndexStore
  )
}

private func makeToolchain(
  binPath: AbsolutePath,
  _ fs: FileSystem,
  clang: Bool = false,
  clangd: Bool = false,
  swiftc: Bool = false,
  shouldChmod: Bool = true,  // whether to mark exec
  sourcekitd: Bool = false,
  sourcekitdInProc: Bool = false,
  libIndexStore: Bool = false
) throws {
  precondition(
    !clang && !swiftc && !clangd || !shouldChmod,
    "Cannot make toolchain binaries exectuable with InMemoryFileSystem"
  )

  // tiny PE binary from: https://archive.is/w01DO
  let contents: [UInt8] = [
    0x4d, 0x5a, 0x00, 0x00, 0x50, 0x45, 0x00, 0x00, 0x4c, 0x01, 0x01, 0x00,
    0x6a, 0x2a, 0x58, 0xc3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x04, 0x00, 0x03, 0x01, 0x0b, 0x01, 0x08, 0x00, 0x04, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00,
    0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
    0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x68, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x02,
  ]

  let libPath = binPath.parentDirectory.appending(component: "lib")
  try fs.createDirectory(binPath, recursive: true)
  try fs.createDirectory(libPath)

  let makeExec = { (path: AbsolutePath) in
    try fs.writeFileContents(path, bytes: ByteString(contents))
    #if !os(Windows)
    if shouldChmod {
      XCTAssertEqual(chmod(path.pathString, S_IRUSR | S_IXUSR), 0)
    }
    #endif
  }

  let execExt = Platform.current?.executableExtension ?? ""

  if clang {
    try makeExec(binPath.appending(component: "clang\(execExt)"))
  }
  if clangd {
    try makeExec(binPath.appending(component: "clangd\(execExt)"))
  }
  if swiftc {
    try makeExec(binPath.appending(component: "swiftc\(execExt)"))
  }

  let dylibSuffix = Platform.current?.dynamicLibraryExtension ?? ".so"

  if sourcekitd {
    try fs.createDirectory(libPath.appending(component: "sourcekitd.framework"))
    try fs.writeFileContents(libPath.appending(components: "sourcekitd.framework", "sourcekitd"), bytes: "")
  }
  if sourcekitdInProc {
    #if os(Windows)
    try fs.writeFileContents(binPath.appending(component: "sourcekitdInProc\(dylibSuffix)"), bytes: "")
    #else
    try fs.writeFileContents(libPath.appending(component: "libsourcekitdInProc\(dylibSuffix)"), bytes: "")
    #endif
  }
  if libIndexStore {
    #if os(Windows)
    // Windows has a prefix of `lib` on this particular library ...
    try fs.writeFileContents(binPath.appending(component: "libIndexStore\(dylibSuffix)"), bytes: "")
    #else
    try fs.writeFileContents(libPath.appending(component: "libIndexStore\(dylibSuffix)"), bytes: "")
    #endif
  }
}
