//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(PackageModel)
import BuildServerProtocol
@_spi(Testing) import BuildSystemIntegration
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import PackageModel
import SKOptions
import SKTestSupport
import SourceKitLSP
@preconcurrency import SPMBuildCore
import SwiftExtensions
import TSCBasic
import TSCExtensions
import ToolchainRegistry
import XCTest

import struct Basics.AbsolutePath
import struct Basics.Triple

private var hostTriple: Triple {
  get async throws {
    let toolchain = try await unwrap(
      ToolchainRegistry.forTesting.preferredToolchain(containing: [\.clang, \.clangd, \.sourcekitd, \.swift, \.swiftc])
    )
    let destinationToolchainBinDir = try XCTUnwrap(toolchain.swiftc?.deletingLastPathComponent())

    let hostSDK = try SwiftSDK.hostSwiftSDK(Basics.AbsolutePath(validating: destinationToolchainBinDir.filePath))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    return hostSwiftPMToolchain.targetTriple
  }
}

final class SwiftPMBuildSystemTests: XCTestCase {
  func testNoPackage() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": ""
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      XCTAssertNil(SwiftPMBuildSystem.projectRoot(for: packageRoot, options: .testDefault()))
    }
  }

  func testNoToolchain() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      await assertThrowsError(
        try await SwiftPMBuildSystem(
          projectRoot: packageRoot,
          toolchainRegistry: ToolchainRegistry(toolchains: []),
          options: SourceKitLSPOptions(),
          connectionToSourceKitLSP: LocalConnection(receiverName: "dummy"),
          testHooks: SwiftPMTestHooks()
        )
      )
    }
  }

  func testRelativeScratchPath() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      let options = SourceKitLSPOptions(
        swiftPM: .init(
          scratchPath: "non_default_relative_build_path"
        ),
        backgroundIndexing: false
      )
      let swiftpmBuildSystem = try await SwiftPMBuildSystem(
        projectRoot: packageRoot,
        toolchainRegistry: .forTesting,
        options: options,
        connectionToSourceKitLSP: LocalConnection(receiverName: "dummy"),
        testHooks: SwiftPMTestHooks()
      )

      let dataPath = await swiftpmBuildSystem.destinationBuildParameters.dataPath
      let expectedScratchPath = packageRoot.appendingPathComponent(try XCTUnwrap(options.swiftPMOrDefault.scratchPath))
      XCTAssertTrue(dataPath.asURL.isDescendant(of: expectedScratchPath))
    }
  }

  func testBasicSwiftArgs() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let build = try await buildPath(root: packageRoot, platform: hostTriple.platformBuildPathComponent)

      assertNotNil(await buildSystemManager.initializationData?.indexDatabasePath)
      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      assertArgumentsContain("-module-name", "lib", arguments: arguments)
      assertArgumentsContain("-emit-dependencies", arguments: arguments)
      assertArgumentsContain("-emit-module", arguments: arguments)
      assertArgumentsContain("-emit-module-path", arguments: arguments)
      assertArgumentsContain("-incremental", arguments: arguments)
      assertArgumentsContain("-parse-as-library", arguments: arguments)
      assertArgumentsContain("-c", arguments: arguments)

      assertArgumentsContain("-target", arguments: arguments)  // Only one!
      #if os(macOS)
      let versionString = PackageModel.Platform.macOS.oldestSupportedVersion.versionString
      assertArgumentsContain(
        "-target",
        try await hostTriple.tripleString(forPlatformVersion: versionString),
        arguments: arguments
      )
      assertArgumentsContain("-sdk", arguments: arguments)
      assertArgumentsContain("-F", arguments: arguments, allowMultiple: true)
      #else
      assertArgumentsContain("-target", try await hostTriple.tripleString, arguments: arguments)
      #endif

      assertArgumentsContain("-I", try build.appendingPathComponent("Modules").filePath, arguments: arguments)

      assertArgumentsContain(try aswift.filePath, arguments: arguments)
    }
  }

  func testCompilerArgumentsForFileThatContainsPlusCharacterURLEncoded() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Sources/lib/a+something.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aPlusSomething =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a+something.swift")

      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)
      let pathWithPlusEscaped = "\(try aPlusSomething.filePath.replacing("+", with: "%2B"))"
      #if os(Windows)
      let urlWithPlusEscaped = try XCTUnwrap(URL(string: "file:///\(pathWithPlusEscaped)"))
      #else
      let urlWithPlusEscaped = try XCTUnwrap(URL(string: "file://\(pathWithPlusEscaped)"))
      #endif
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(urlWithPlusEscaped),
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      .compilerArguments

      // Check that we have both source files in the compiler arguments, which means that we didn't compute the compiler
      // arguments for a+something.swift using substitute arguments from a.swift.
      XCTAssert(
        try arguments.contains(aPlusSomething.filePath),
        "Compiler arguments do not contain a+something.swift: \(arguments)"
      )
      XCTAssert(
        try arguments.contains(
          packageRoot.appendingPathComponent("Sources").appendingPathComponent("lib").appendingPathComponent("a.swift")
            .filePath
        ),
        "Compiler arguments do not contain a.swift: \(arguments)"
      )
    }
  }

  func testBuildSetup() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")

      let options = SourceKitLSPOptions.SwiftPMOptions(
        configuration: .release,
        scratchPath: try packageRoot.appendingPathComponent("non_default_build_path").filePath,
        cCompilerFlags: ["-m32"],
        swiftCompilerFlags: ["-typecheck"]
      )

      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(swiftPM: options),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")

      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      assertArgumentsContain("-typecheck", arguments: arguments)
      assertArgumentsContain("-Xcc", "-m32", arguments: arguments)
      assertArgumentsContain("-O", arguments: arguments)
    }
  }

  func testDefaultSDKs() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:6.0
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let tr = ToolchainRegistry.forTesting

      let options = SourceKitLSPOptions.SwiftPMOptions(
        swiftSDKsDirectory: "/tmp/non_existent_sdks_dir",
        triple: "wasm32-unknown-wasi"
      )

      let swiftpmBuildSystem = try await SwiftPMBuildSystem(
        projectRoot: tempDir.appendingPathComponent("pkg"),
        toolchainRegistry: tr,
        options: SourceKitLSPOptions(swiftPM: options),
        connectionToSourceKitLSP: LocalConnection(receiverName: "Dummy"),
        testHooks: SwiftPMTestHooks()
      )
      let path = await swiftpmBuildSystem.destinationBuildParameters.toolchain.sdkRootPath
      XCTAssertEqual(
        path?.components.suffix(3),
        ["usr", "share", "wasi-sysroot"],
        "SwiftPMBuildSystem should share default SDK derivation logic with libSwiftPM"
      )
    }
  }

  func testManifestArgs() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let source = try packageRoot.appendingPathComponent("Package.swift").realpath
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(source),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      assertArgumentsContain("-swift-version", "4.2", arguments: arguments)
      assertArgumentsContain(try source.filePath, arguments: arguments)
    }
  }

  func testMultiFileSwift() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Sources/lib/b.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let bswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("b.swift")

      let argumentsA = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(try aswift.filePath, arguments: argumentsA)
      assertArgumentsContain(try bswift.filePath, arguments: argumentsA)
      let argumentsB = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(try aswift.filePath, arguments: argumentsB)
      assertArgumentsContain(try bswift.filePath, arguments: argumentsB)
    }
  }

  func testMultiTargetSwift() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/libA/a.swift": "",
          "pkg/Sources/libB/b.swift": "",
          "pkg/Sources/libC/include/libC.h": "",
          "pkg/Sources/libC/libC.c": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [
              .target(name: "libA", dependencies: ["libB", "libC"]),
              .target(name: "libB"),
              .target(name: "libC"),
            ]
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("libA")
        .appendingPathComponent("a.swift")
      let bswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("libB")
        .appendingPathComponent("b.swift")
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(try aswift.filePath, arguments: arguments)
      assertArgumentsDoNotContain(try bswift.filePath, arguments: arguments)
      assertArgumentsContain(
        "-Xcc",
        "-I",
        "-Xcc",
        try packageRoot
          .appendingPathComponent("Sources")
          .appendingPathComponent("libC")
          .appendingPathComponent("include")
          .filePath,
        arguments: arguments
      )

      let argumentsB = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(bswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(try bswift.filePath, arguments: argumentsB)
      assertArgumentsDoNotContain(try aswift.filePath, arguments: argumentsB)
      assertArgumentsDoNotContain(
        "-I",
        try packageRoot
          .appendingPathComponent("Sources")
          .appendingPathComponent("libC")
          .appendingPathComponent("include")
          .filePath,
        arguments: argumentsB
      )
    }
  }

  func testUnknownFile() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/libA/a.swift": "",
          "pkg/Sources/libB/b.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "libA")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("libA")
        .appendingPathComponent("a.swift")
      let bswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("libB")
        .appendingPathComponent("b.swift")
      assertNotNil(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      assertEqual(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(bswift),
          language: .swift,
          fallbackAfterTimeout: false
        )?.isFallback,
        true
      )
      assertEqual(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(URL(string: "https://www.apple.com")!),
          language: .swift,
          fallbackAfterTimeout: false
        )?.isFallback,
        true
      )
    }
  }

  func testBasicCXXArgs() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.cpp": "",
          "pkg/Sources/lib/b.cpp": "",
          "pkg/Sources/lib/include/a.h": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")],
            cxxLanguageStandard: .cxx14
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let acxx =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.cpp")
      let bcxx =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("b.cpp")
      let header =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("include")
        .appendingPathComponent("a.h")
      let build = buildPath(root: packageRoot, platform: try await hostTriple.platformBuildPathComponent)

      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)

      for file in [acxx, header] {
        let args = try await unwrap(
          buildSystemManager.buildSettingsInferredFromMainFile(
            for: DocumentURI(file),
            language: .cpp,
            fallbackAfterTimeout: false
          )
        ).compilerArguments

        assertArgumentsContain("-std=c++14", arguments: args)

        assertArgumentsDoNotContain("-arch", arguments: args)
        assertArgumentsContain("-target", arguments: args)  // Only one!
        #if os(macOS)
        let versionString = PackageModel.Platform.macOS.oldestSupportedVersion.versionString
        assertArgumentsContain(
          "-target",
          try await hostTriple.tripleString(forPlatformVersion: versionString),
          arguments: args
        )
        assertArgumentsContain("-isysroot", arguments: args)
        assertArgumentsContain("-F", arguments: args, allowMultiple: true)
        #else
        assertArgumentsContain("-target", try await hostTriple.tripleString, arguments: args)
        #endif

        assertArgumentsContain(
          "-I",
          try packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("lib")
            .appendingPathComponent("include")
            .filePath,
          arguments: args
        )
        assertArgumentsDoNotContain("-I", try build.filePath, arguments: args)
        assertArgumentsDoNotContain(try bcxx.filePath, arguments: args)

        URL(fileURLWithPath: try build.appendingPathComponent("lib.build").appendingPathComponent("a.cpp.d").filePath)
          .withUnsafeFileSystemRepresentation {
            assertArgumentsContain("-MD", "-MT", "dependencies", "-MF", String(cString: $0!), arguments: args)
          }

        URL(fileURLWithPath: try file.filePath).withUnsafeFileSystemRepresentation {
          assertArgumentsContain("-c", String(cString: $0!), arguments: args)
        }

        URL(fileURLWithPath: try build.appendingPathComponent("lib.build").appendingPathComponent("a.cpp.o").filePath)
          .withUnsafeFileSystemRepresentation {
            assertArgumentsContain("-o", String(cString: $0!), arguments: args)
          }
      }
    }
  }

  func testDeploymentTargetSwift() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: try tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:5.0
          import PackageDescription
          let package = Package(name: "a",
            platforms: [.macOS(.v10_13)],
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain("-target", arguments: arguments)  // Only one!

      #if os(macOS)
      try await assertArgumentsContain(
        "-target",
        hostTriple.tripleString(forPlatformVersion: "10.13"),
        arguments: arguments
      )
      #else
      assertArgumentsContain("-target", try await hostTriple.tripleString, arguments: arguments)
      #endif
    }
  }

  func testSymlinkInWorkspaceSwift() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg_real/Sources/lib/a.swift": "",
          "pkg_real/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")

      try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: packageRoot.filePath),
        withDestinationURL: URL(fileURLWithPath: tempDir.appendingPathComponent("pkg_real").filePath)
      )

      let projectRoot = try XCTUnwrap(SwiftPMBuildSystem.projectRoot(for: packageRoot, options: .testDefault()))
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(
          kind: .swiftPM,
          projectRoot: projectRoot
        ),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswiftSymlink =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let aswiftReal = try aswiftSymlink.realpath
      let manifest = packageRoot.appendingPathComponent("Package.swift")

      let argumentsFromSymlink = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswiftSymlink),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      // We opened the project from a symlink. The realpath isn't part of the project and we should thus not receive
      // build settings for it.
      assertTrue(
        try await unwrap(
          buildSystemManager.buildSettingsInferredFromMainFile(
            for: DocumentURI(aswiftReal),
            language: .swift,
            fallbackAfterTimeout: false
          )
        ).isFallback
      )
      assertArgumentsContain(try aswiftSymlink.filePath, arguments: argumentsFromSymlink)
      assertArgumentsDoNotContain(try aswiftReal.filePath, arguments: argumentsFromSymlink)

      let argsManifest = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(manifest),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      XCTAssertNotNil(argsManifest)

      assertArgumentsContain(try manifest.filePath, arguments: argsManifest)
      assertArgumentsDoNotContain(try manifest.realpath.filePath, arguments: argsManifest)
    }
  }

  func testSymlinkInWorkspaceCXX() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg_real/Sources/lib/a.cpp": "",
          "pkg_real/Sources/lib/b.cpp": "",
          "pkg_real/Sources/lib/include/a.h": "",
          "pkg_real/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")],
            cxxLanguageStandard: .cxx14
          )
          """,
        ]
      )

      let acpp = ["Sources", "lib", "a.cpp"]
      let ah = ["Sources", "lib", "include", "a.h"]

      let realRoot = tempDir.appendingPathComponent("pkg_real")
      let symlinkRoot = tempDir.appendingPathComponent("pkg")

      try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: symlinkRoot.filePath),
        withDestinationURL: URL(fileURLWithPath: tempDir.appendingPathComponent("pkg_real").filePath)
      )

      let projectRoot = try XCTUnwrap(SwiftPMBuildSystem.projectRoot(for: symlinkRoot, options: .testDefault()))
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(
          kind: .swiftPM,
          projectRoot: projectRoot
        ),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      for file in [acpp, ah] {
        let args = try unwrap(
          await buildSystemManager.buildSettingsInferredFromMainFile(
            for: DocumentURI(symlinkRoot.appending(components: file)),
            language: .cpp,
            fallbackAfterTimeout: false
          )?
          .compilerArguments
        )
        assertArgumentsDoNotContain(try realRoot.appending(components: file).filePath, arguments: args)
        assertArgumentsContain(try symlinkRoot.appending(components: file).filePath, arguments: args)
      }
    }
  }

  func testSwiftDerivedSources() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Sources/lib/a.txt": "",
          "pkg/Package.swift": """
          // swift-tools-version:5.3
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib", resources: [.copy("a.txt")])]
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      .compilerArguments
      assertArgumentsContain(try aswift.filePath, arguments: arguments)
      XCTAssertNotNil(
        arguments.firstIndex(where: {
          $0.hasSuffix(".swift") && $0.contains("DerivedSources")
        }),
        "missing resource_bundle_accessor.swift from \(arguments)"
      )
    }
  }

  func testNestedInvalidPackageSwift() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/Package.swift": "// not a valid package",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let workspaceRoot =
        tempDir
        .appendingPathComponent("pkg")
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
      let projectRoot = SwiftPMBuildSystem.projectRoot(for: workspaceRoot, options: .testDefault())

      assertEqual(projectRoot, tempDir.appendingPathComponent("pkg", isDirectory: true))
    }
  }

  func testPluginArgs() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Plugins/MyPlugin/a.swift": "",
          "pkg/Sources/lib/lib.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:5.7
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [
              .target(name: "lib"),
              .plugin(name: "MyPlugin", capability: .buildTool)
            ]
          )
          """,
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Plugins")
        .appendingPathComponent("MyPlugin")
        .appendingPathComponent("a.swift")

      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      // Plugins get compiled with the same compiler arguments as the package manifest
      assertArgumentsContain("-package-description-version", "5.7.0", arguments: arguments)
      assertArgumentsContain(try aswift.filePath, arguments: arguments)
    }
  }

  func testPackageWithDependencyWithoutResolving() async throws {
    // This package has a dependency but we haven't run `swift package resolve`. We don't want to resolve packages from
    // SourceKit-LSP because it has side-effects to the build directory.
    // But even without the dependency checked out, we should be able to create a SwiftPMBuildSystem and retrieve the
    // existing source files.
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/PackageTests/PackageTests.swift": """
        import Testing

        1️⃣@Test func topLevelTestPassing() {}2️⃣
        """
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          dependencies: [.package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main")],
          targets: [
            .testTarget(name: "PackageTests", dependencies: [.product(name: "Testing", package: "swift-testing")]),
          ]
        )
        """
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "PackageTests.topLevelTestPassing()",
          label: "topLevelTestPassing()",
          disabled: false,
          style: "swift-testing",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "PackageTests.swift"),
          children: [],
          tags: []
        )
      ]
    )
  }

  func testPackageLoadingWorkDoneProgress() async throws {
    let didReceiveWorkDoneProgressNotification = WrappedSemaphore(name: "work done progress received")
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/Test.swift": ""
      ],
      capabilities: ClientCapabilities(window: WindowClientCapabilities(workDoneProgress: true)),
      testHooks: TestHooks(
        buildSystemTestHooks: BuildSystemTestHooks(
          swiftPMTestHooks: SwiftPMTestHooks(reloadPackageDidStart: {
            didReceiveWorkDoneProgressNotification.waitOrXCTFail()
          })
        )
      ),
      pollIndex: false,
      preInitialization: { testClient in
        testClient.handleMultipleRequests { (request: CreateWorkDoneProgressRequest) in
          return VoidResponse()
        }
      }
    )
    let begin = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self)
    XCTAssertEqual(begin.value, .begin(WorkDoneProgressBegin(title: "SourceKit-LSP: Reloading Package")))
    didReceiveWorkDoneProgressNotification.signal()

    let end = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self)
    XCTAssertEqual(end.token, begin.token)
    XCTAssertEqual(end.value, .end(WorkDoneProgressEnd()))
  }

  func testBuildSettingsForVersionSpecificPackageManifest() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
          "pkg/Package@swift-5.8.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(
            name: "a",
            targets: [.target(name: "lib")]
          )
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let versionSpecificManifestURL = packageRoot.appendingPathComponent("Package@swift-5.8.swift")
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()
      let settings = await buildSystemManager.buildSettingsInferredFromMainFile(
        for: DocumentURI(versionSpecificManifestURL),
        language: .swift,
        fallbackAfterTimeout: false
      )
      let compilerArgs = try XCTUnwrap(settings?.compilerArguments)
      XCTAssert(compilerArgs.contains("-package-description-version"))
      XCTAssert(compilerArgs.contains(try versionSpecificManifestURL.filePath))
    }
  }

  func testBuildSettingsForInvalidManifest() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:5.1
          import PackageDescription
          """,
        ]
      )
      let packageRoot = try tempDir.appendingPathComponent("pkg").realpath
      let manifestURL = packageRoot.appendingPathComponent("Package.swift")
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: BuildSystemSpec(kind: .swiftPM, projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()
      let settings = await buildSystemManager.buildSettingsInferredFromMainFile(
        for: DocumentURI(manifestURL),
        language: .swift,
        fallbackAfterTimeout: false
      )
      let compilerArgs = try XCTUnwrap(settings?.compilerArguments)
      assertArgumentsContain("-package-description-version", "5.1.0", arguments: compilerArgs)
      XCTAssert(compilerArgs.contains(try manifestURL.filePath))
    }
  }
}

private func assertArgumentsDoNotContain(
  _ pattern: String...,
  arguments: [String],
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if let index = arguments.firstRange(of: pattern)?.startIndex {
    XCTFail(
      "not-pattern \(pattern) unexpectedly found at \(index) in arguments \(arguments)",
      file: file,
      line: line
    )
    return
  }
}

private func assertArgumentsContain(
  _ pattern: String...,
  arguments: [String],
  allowMultiple: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  guard let index = arguments.firstRange(of: pattern)?.startIndex else {
    XCTFail("pattern \(pattern) not found in arguments \(arguments)", file: file, line: line)
    return
  }

  if !allowMultiple, let index2 = arguments[(index + 1)...].firstRange(of: pattern)?.startIndex {
    XCTFail(
      "pattern \(pattern) found twice (\(index), \(index2)) in \(arguments)",
      file: file,
      line: line
    )
  }
}

private func buildPath(
  root: URL,
  options: SourceKitLSPOptions.SwiftPMOptions = SourceKitLSPOptions.SwiftPMOptions(),
  platform: String
) -> URL {
  let buildPath =
    if let scratchPath = options.scratchPath {
      URL(fileURLWithPath: scratchPath)
    } else {
      root.appendingPathComponent(".build").appendingPathComponent("index-build")
    }
  return buildPath.appendingPathComponent(platform).appendingPathComponent("\(options.configuration ?? .debug)")
}

fileprivate extension URL {
  func appending(components: [String]) -> URL {
    var result = self
    for component in components {
      result.appendPathComponent(component)
    }
    return result
  }
}
#endif
