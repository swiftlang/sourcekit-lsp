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
import SKUtilities
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
import XCTest

#if canImport(Android)
import Android
#endif

final class ToolchainRegistryTests: XCTestCase {
  func testDefaultSingleToolchain() async throws {
    let tr = ToolchainRegistry(toolchains: [
      Toolchain(identifier: "a", displayName: "a", path: URL(fileURLWithPath: "/dummy"))
    ])
    await assertEqual(tr.default?.identifier, "a")
  }

  func testDefaultTwoToolchains() async throws {
    let tr = ToolchainRegistry(
      toolchains: [
        Toolchain(identifier: "a", displayName: "a", path: URL(fileURLWithPath: "/dummy")),
        Toolchain(identifier: "b", displayName: "b", path: URL(fileURLWithPath: "/dummy")),
      ]
    )
    await assertEqual(tr.default?.identifier, "a")
    await assertTrue(tr.default === tr.toolchains(withIdentifier: "a").only)
  }

  func testFindXcodeDefaultToolchain() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")
      let toolchains = xcodeDeveloper.appending(component: "Toolchains")
      try makeXCToolchain(
        identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
        opensource: false,
        path: toolchains.appending(component: "XcodeDefault.xctoolchain"),
        sourcekitd: true
      )

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [xcodeDeveloper],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      assertEqual(await tr.toolchains.count, 1)
      assertEqual(await tr.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)
      assertEqual(
        await tr.default?.path,
        toolchains.appending(component: "XcodeDefault.xctoolchain", directoryHint: .isDirectory)
      )
      assertNotNil(await tr.default?.sourcekitd)

      assertTrue(await tr.toolchains.first === tr.default)
    }
  }

  func testFindNonXcodeDefaultToolchains() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")
      let toolchains = xcodeDeveloper.appending(component: "Toolchains")

      try makeXCToolchain(
        identifier: "com.apple.fake.A",
        opensource: false,
        path: toolchains.appending(component: "A.xctoolchain"),
        sourcekitd: true
      )
      try makeXCToolchain(
        identifier: "com.apple.fake.B",
        opensource: false,
        path: toolchains.appending(component: "B.xctoolchain"),
        sourcekitd: true
      )

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [xcodeDeveloper],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      assertEqual(await tr.toolchains.map(\.identifier).sorted(), ["com.apple.fake.A", "com.apple.fake.B"])
    }
  }

  func testIgnoreToolchainsWithWrongExtensions() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")
      let toolchains = xcodeDeveloper.appending(component: "Toolchains")

      try makeXCToolchain(
        identifier: "com.apple.fake.C",
        opensource: false,
        path: toolchains.appending(component: "C.wrong_extension"),
        sourcekitd: true
      )
      try makeXCToolchain(
        identifier: "com.apple.fake.D",
        opensource: false,
        path: toolchains.appending(component: "D_no_extension"),
        sourcekitd: true
      )

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [xcodeDeveloper],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      assertEqual(await tr.toolchains.map(\.path), [])
    }
  }

  func testTwoToolchainsWithSameIdentifier() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")

      let toolchains = xcodeDeveloper.appending(component: "Toolchains")
      try makeXCToolchain(
        identifier: "com.apple.fake.A",
        opensource: false,
        path: toolchains.appending(component: "A.xctoolchain"),
        sourcekitd: true
      )

      try makeXCToolchain(
        identifier: "com.apple.fake.A",
        opensource: false,
        path: toolchains.appending(component: "E.xctoolchain"),
        sourcekitd: true
      )

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [xcodeDeveloper],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      assertEqual(await tr.toolchains.count, 1)
    }
  }

  func testGloballyInstalledToolchains() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")
    try await withTestScratchDir { tempDir in
      let libraryDir = tempDir.appending(component: "Library")
      try makeXCToolchain(
        identifier: "org.fake.global.A",
        opensource: true,
        path:
          libraryDir
          .appending(components: "Developer", "Toolchains", "A.xctoolchain"),
        sourcekitd: true
      )

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [],
        libraryDirectories: [libraryDir],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )
      assertEqual(await tr.toolchains.map(\.identifier), ["org.fake.global.A"])
    }
  }

  func testFindToolchainBasedOnInstallPath() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")

      let toolchains = xcodeDeveloper.appending(component: "Toolchains")

      let path = toolchains.appending(component: "Explicit.xctoolchain", directoryHint: .isDirectory)
      try makeXCToolchain(
        identifier: "org.fake.explicit",
        opensource: false,
        path: path,
        sourcekitd: true
      )

      let trInstall = ToolchainRegistry(
        installPath: path.appending(components: "usr", "bin"),
        environmentVariables: [],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )
      await assertEqual(trInstall.default?.identifier, "org.fake.explicit")
      await assertEqual(trInstall.default?.path, path)
    }
  }

  func testDarwinToolchainOverride() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")

      let toolchains = xcodeDeveloper.appending(component: "Toolchains")
      try makeXCToolchain(
        identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
        opensource: false,
        path: toolchains.appending(component: "XcodeDefault.xctoolchain"),
        sourcekitd: true
      )

      try makeXCToolchain(
        identifier: "org.fake.global.A",
        opensource: false,
        path: toolchains.appending(component: "A.xctoolchain"),
        sourcekitd: true
      )

      let toolchainRegistry = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [xcodeDeveloper],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      await assertEqual(toolchainRegistry.default?.identifier, ToolchainRegistry.darwinDefaultToolchainIdentifier)

      let darwinToolchainOverrideRegistry = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [xcodeDeveloper],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: "org.fake.global.A"
      )
      await assertEqual(darwinToolchainOverrideRegistry.darwinToolchainIdentifier, "org.fake.global.A")
      await assertEqual(darwinToolchainOverrideRegistry.default?.identifier, "org.fake.global.A")
    }
  }

  func testCreateToolchainFromBinPath() async throws {
    try SkipUnless.platformIsDarwin("Finding toolchains in Xcode is only supported on macOS")

    try await withTestScratchDir { tempDir in
      let xcodeDeveloper =
        tempDir
        .appending(components: "Xcode.app", "Developer")
      let toolchains = xcodeDeveloper.appending(component: "Toolchains")

      let path = toolchains.appending(component: "Explicit.xctoolchain", directoryHint: .isDirectory)
      try makeXCToolchain(
        identifier: "org.fake.explicit",
        opensource: false,
        path: path,
        sourcekitd: true
      )

      let tc = Toolchain(path)
      XCTAssertNotNil(tc)
      XCTAssertEqual(tc?.identifier, "org.fake.explicit")

      let tcBin = Toolchain(path.appending(components: "usr", "bin"))
      XCTAssertNotNil(tcBin)
      XCTAssertEqual(tc?.identifier, tcBin?.identifier)
      XCTAssertEqual(tc?.path, tcBin?.path)
      XCTAssertEqual(tc?.displayName, tcBin?.displayName)
    }
  }

  func testSearchPATH() async throws {
    try await withTestScratchDir { tempDir in
      let binPath = tempDir.appending(component: "bin", directoryHint: .isDirectory)
      try makeToolchain(binPath: binPath, clang: true, sourcekitd: true)

      let compilerPath = binPath.appending(component: "clang" + (Platform.current?.executableExtension ?? ""))
      let linkPath = tempDir.appending(component: "link")
      try FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: compilerPath)

      #if os(Windows)
      let separator: String = ";"
      #else
      let separator: String = ":"
      #endif

      try ProcessEnv.setVar(
        "SOURCEKIT_PATH_FOR_TEST",
        value: [
          "/bogus/../parent",
          "/bogus",
          binPath.appending(components: "..", "bin", directoryHint: .isDirectory).filePath,
          "/bogus2",
        ].joined(separator: separator)
      )
      defer { try! ProcessEnv.setVar("SOURCEKIT_PATH_FOR_TEST", value: "") }

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: ["SOURCEKIT_PATH_FOR_TEST"],
        darwinToolchainOverride: nil
      )

      let pathTC = try unwrap(await tr.toolchain(withPath: binPath))

      await assertEqual(tr.default?.identifier, pathTC.identifier)
      XCTAssertEqual(pathTC.identifier, try binPath.filePath)
      XCTAssertNotNil(pathTC.clang)
      XCTAssertNil(pathTC.clangd)
      XCTAssertNil(pathTC.swiftc)
      XCTAssertNotNil(pathTC.sourcekitd)
      XCTAssertNil(pathTC.libIndexStore)

      let compilerTC = try unwrap(await tr.toolchain(withCompiler: compilerPath))
      XCTAssertEqual(compilerTC.identifier, try binPath.filePath)

      let linkTC = await tr.toolchain(withCompiler: linkPath)
      XCTAssertNil(linkTC)
    }
  }

  func testSearchExplicitEnvBuiltin() async throws {
    try await withTestScratchDir { tempDir in
      let binPath = tempDir.appending(component: "bin", directoryHint: .isDirectory)
      try makeToolchain(binPath: binPath, sourcekitd: true)

      try ProcessEnv.setVar("TEST_SOURCEKIT_TOOLCHAIN_PATH_1", value: binPath.deletingLastPathComponent().filePath)

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: ["TEST_SOURCEKIT_TOOLCHAIN_PATH_1"],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      guard let tc = await tr.toolchains.first(where: { tc in tc.path == binPath.deletingLastPathComponent() }) else {
        XCTFail("couldn't find expected toolchain")
        return
      }

      await assertEqual(tr.default?.identifier, tc.identifier)
      XCTAssertEqual(tc.identifier, try binPath.deletingLastPathComponent().filePath)
      XCTAssertNil(tc.clang)
      XCTAssertNil(tc.clangd)
      XCTAssertNil(tc.swiftc)
      XCTAssertNotNil(tc.sourcekitd)
      XCTAssertNil(tc.libIndexStore)
    }
  }

  func testSearchExplicitEnv() async throws {
    try await withTestScratchDir { tempDir in
      let binPath = tempDir.appending(component: "bin", directoryHint: .isDirectory)
      try makeToolchain(binPath: binPath, sourcekitd: true)

      try ProcessEnv.setVar("TEST_ENV_SOURCEKIT_TOOLCHAIN_PATH_2", value: binPath.deletingLastPathComponent().filePath)

      let tr = ToolchainRegistry(
        installPath: nil,
        environmentVariables: ["TEST_ENV_SOURCEKIT_TOOLCHAIN_PATH_2"],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )

      guard let tc = await tr.toolchains.first(where: { tc in tc.path == binPath.deletingLastPathComponent() }) else {
        XCTFail("couldn't find expected toolchain")
        return
      }

      XCTAssertEqual(tc.identifier, try binPath.deletingLastPathComponent().filePath)
      XCTAssertNil(tc.clang)
      XCTAssertNil(tc.clangd)
      XCTAssertNil(tc.swiftc)
      XCTAssertNotNil(tc.sourcekitd)
      XCTAssertNil(tc.libIndexStore)
    }
  }

  func testFromDirectory() async throws {
    try await withTestScratchDir { tempDir in
      let path = tempDir.appending(components: "A.xctoolchain", "usr")
      try makeToolchain(
        binPath: path.appending(component: "bin"),
        clang: true,
        clangd: true,
        swiftc: true,
        shouldChmod: false,
        sourcekitd: true
      )

      try Data().write(to: path.appending(components: "bin", "other"))

      let t1 = try XCTUnwrap(Toolchain(path.deletingLastPathComponent()))
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
      func chmodRX(_ path: URL) throws {
        XCTAssertEqual(chmod(try path.filePath, S_IRUSR | S_IXUSR), 0)
      }

      try chmodRX(path.appending(components: "bin", "clang"))
      try chmodRX(path.appending(components: "bin", "clangd"))
      try chmodRX(path.appending(components: "bin", "swiftc"))
      try chmodRX(path.appending(components: "bin", "other"))
      #endif

      let t2 = try XCTUnwrap(Toolchain(path.deletingLastPathComponent()))
      XCTAssertNotNil(t2.sourcekitd)
      XCTAssertNotNil(t2.clang)
      XCTAssertNotNil(t2.clangd)
      XCTAssertNotNil(t2.swiftc)

      let tr = ToolchainRegistry(toolchains: [try XCTUnwrap(Toolchain(path.deletingLastPathComponent()))])
      let t3 = try await unwrap(tr.toolchains(withIdentifier: t2.identifier).only)
      XCTAssertEqual(t3.sourcekitd, t2.sourcekitd)
      XCTAssertEqual(t3.clang, t2.clang)
      XCTAssertEqual(t3.clangd, t2.clangd)
      XCTAssertEqual(t3.swiftc, t2.swiftc)
    }
  }

  func testDylibNames() async throws {
    try await withTestScratchDir { tempDir in
      let binPath = tempDir.appending(component: "bin", directoryHint: .isDirectory)
      try makeToolchain(binPath: binPath, sourcekitdInProc: true, libIndexStore: true)
      guard let t = Toolchain(binPath) else {
        XCTFail("could not find any tools")
        return
      }
      XCTAssertNotNil(t.sourcekitd)
      XCTAssertNotNil(t.libIndexStore)
    }
  }

  func testSubDirs() async throws {
    try await withTestScratchDir { tempDir in
      try makeToolchain(binPath: tempDir.appending(components: "t1", "bin"), sourcekitd: true)
      try makeToolchain(
        binPath: tempDir.appending(components: "t2", "usr", "bin"),
        sourcekitd: true
      )

      XCTAssertNotNil(Toolchain(tempDir.appending(component: "t1")))
      XCTAssertNotNil(Toolchain(tempDir.appending(components: "t1", "bin")))
      XCTAssertNotNil(Toolchain(tempDir.appending(component: "t2")))

      XCTAssertNil(Toolchain(tempDir.appending(component: "t3")))
      try FileManager.default.createDirectory(
        at: tempDir.appending(components: "t3", "bin"),
        withIntermediateDirectories: true
      )
      try FileManager.default.createDirectory(
        at: tempDir.appending(components: "t3", "lib", "sourcekitd.framework"),
        withIntermediateDirectories: true
      )
      XCTAssertNil(Toolchain(tempDir.appending(component: "t3")))
      try makeToolchain(binPath: tempDir.appending(components: "t3", "bin"), sourcekitd: true)
      XCTAssertNotNil(Toolchain(tempDir.appending(component: "t3")))
    }
  }

  func testDuplicateToolchainOnlyRegisteredOnce() async throws {
    let toolchain = Toolchain(identifier: "a", displayName: "a", path: URL(fileURLWithPath: "/dummy"))
    let tr = ToolchainRegistry(toolchains: [toolchain, toolchain])
    assertEqual(await tr.toolchains.count, 1)
  }

  func testDuplicatePathOnlyRegisteredOnce() async throws {
    let path = URL(fileURLWithPath: "/foo/bar")
    let first = Toolchain(identifier: "a", displayName: "a", path: path)
    let second = Toolchain(identifier: "b", displayName: "b", path: path)

    let tr = ToolchainRegistry(toolchains: [first, second])
    assertEqual(await tr.toolchains.count, 1)
  }

  func testMultipleXcodes() async throws {
    let pathA = URL(fileURLWithPath: "/versionA")
    let xcodeA = Toolchain(
      identifier: ToolchainRegistry.darwinDefaultToolchainIdentifier,
      displayName: "a",
      path: pathA
    )
    let pathB = URL(fileURLWithPath: "/versionB")
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
    try await withTestScratchDir { tempDir in
      let binPath = tempDir.appending(components: "t1", "bin", directoryHint: .isDirectory)
      try makeToolchain(binPath: binPath, sourcekitd: true)

      let trEmpty = ToolchainRegistry(
        installPath: nil,
        environmentVariables: [],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )
      await assertNil(trEmpty.default)

      let tr1 = ToolchainRegistry(
        installPath: binPath,
        environmentVariables: [],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )
      await assertEqual(tr1.default?.path, binPath)
      await assertNotNil(tr1.default?.sourcekitd)

      let tr2 = ToolchainRegistry(
        installPath: tempDir.appending(components: "t2", "bin", directoryHint: .isDirectory),
        environmentVariables: [],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )
      await assertNil(tr2.default)
    }
  }

  func testInstallPathVsEnv() async throws {
    try await withTestScratchDir { tempDir in
      let t1Bin = tempDir.appending(components: "t1", "bin", directoryHint: .isDirectory)
      let t2Bin = tempDir.appending(components: "t2", "bin", directoryHint: .isDirectory)
      try makeToolchain(binPath: t1Bin, sourcekitd: true)
      try makeToolchain(binPath: t2Bin, sourcekitd: true)

      try ProcessEnv.setVar("TEST_SOURCEKIT_TOOLCHAIN_PATH_1", value: t2Bin.filePath)

      let tr = ToolchainRegistry(
        installPath: t1Bin,
        environmentVariables: ["TEST_SOURCEKIT_TOOLCHAIN_PATH_1"],
        xcodes: [],
        libraryDirectories: [],
        pathEnvironmentVariables: [],
        darwinToolchainOverride: nil
      )
      await assertEqual(tr.toolchains.count, 2)

      // Env variable wins.
      await assertEqual(tr.default?.path, t2Bin)
    }
  }

  func testSupersetToolchains() async throws {
    try await withTestScratchDir { tempDir in
      let usrLocal = tempDir.appending(components: "usr", "local")
      let usr = tempDir.appending(component: "usr")

      let onlySwiftcToolchain = Toolchain(
        identifier: "onlySwiftc",
        displayName: "onlySwiftc",
        path: usrLocal,
        swiftc: usrLocal.appending(components: "bin", "swiftc")
      )
      let swiftcAndSourcekitdToolchain = Toolchain(
        identifier: "swiftcAndSourcekitd",
        displayName: "swiftcAndSourcekitd",
        path: usr,
        swiftc: usr.appending(components: "bin", "swiftc"),
        sourcekitd: usrLocal.appending(components: "lib", "sourcekitd.framework", "sourcekitd")
      )

      let tr = ToolchainRegistry(toolchains: [onlySwiftcToolchain, swiftcAndSourcekitdToolchain])
      await assertEqual(tr.default?.identifier, "swiftcAndSourcekitd")
    }
  }
}

private func makeXCToolchain(
  identifier: String,
  opensource: Bool,
  path: URL,
  clang: Bool = false,
  clangd: Bool = false,
  swiftc: Bool = false,
  shouldChmod: Bool = true,  // whether to mark exec
  sourcekitd: Bool = false,
  sourcekitdInProc: Bool = false,
  libIndexStore: Bool = false
) throws {
  try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  let infoPlistPath = path.appending(component: opensource ? "Info.plist" : "ToolchainInfo.plist")
  let infoPlist = try PropertyListEncoder().encode(
    XCToolchainPlist(identifier: identifier, displayName: "name-\(identifier)")
  )
  try infoPlist.write(to: infoPlistPath)

  try makeToolchain(
    binPath: path.appending(components: "usr", "bin"),
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
  binPath: URL,
  clang: Bool = false,
  clangd: Bool = false,
  swiftc: Bool = false,
  shouldChmod: Bool = true,  // whether to mark exec
  sourcekitd: Bool = false,
  sourcekitdInProc: Bool = false,
  libIndexStore: Bool = false
) throws {
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

  let libPath = binPath.deletingLastPathComponent().appending(component: "lib")
  try FileManager.default.createDirectory(at: binPath, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: libPath, withIntermediateDirectories: true)

  let makeExec = { (path: URL) in
    try Data(contents).write(to: path)
    #if !os(Windows)
    if shouldChmod {
      XCTAssertEqual(chmod(try path.filePath, S_IRUSR | S_IXUSR), 0)
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
    try FileManager.default.createDirectory(
      at: libPath.appending(component: "sourcekitd.framework"),
      withIntermediateDirectories: true
    )
    try Data().write(to: libPath.appending(components: "sourcekitd.framework", "sourcekitd"))
  }
  if sourcekitdInProc {
    #if os(Windows)
    try Data().write(to: binPath.appending(component: "sourcekitdInProc\(dylibSuffix)"))
    #else
    try Data().write(to: libPath.appending(component: "libsourcekitdInProc\(dylibSuffix)"))
    #endif
  }
  if libIndexStore {
    #if os(Windows)
    // Windows has a prefix of `lib` on this particular library ...
    try Data().write(to: binPath.appending(component: "libIndexStore\(dylibSuffix)"))
    #else
    try Data().write(to: libPath.appending(component: "libIndexStore\(dylibSuffix)"))
    #endif
  }
}
