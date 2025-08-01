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

#if !NO_SWIFTPM_DEPENDENCY
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
import Foundation
import Testing
import struct Basics.AbsolutePath
import struct Basics.Triple

private var hostTriple: Triple {
  get async throws {
    let toolchain = try #require(
      await ToolchainRegistry.forTesting.preferredToolchain(containing: [
        \.clang, \.clangd, \.sourcekitd, \.swift, \.swiftc,
      ])
    )
    let destinationToolchainBinDir = try #require(toolchain.swiftc?.deletingLastPathComponent())

    let hostSDK = try SwiftSDK.hostSwiftSDK(Basics.AbsolutePath(validating: destinationToolchainBinDir.filePath))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    return hostSwiftPMToolchain.targetTriple
  }
}

@Suite(.serialized)
struct SwiftPMBuildSystemTests {
  @Test
  func testNoPackage() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": ""
        ]
      )
      let packageRoot = tempDir.appendingPathComponent("pkg")
      let buildSystemSpec = SwiftPMBuildSystem.searchForConfig(in: packageRoot, options: try await .testDefault())
      #expect(buildSystemSpec == nil)
    }
  }

  @Test
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
      await expectThrowsError(
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

  @Test
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
      let expectedScratchPath = packageRoot.appendingPathComponent(try #require(options.swiftPMOrDefault.scratchPath))
      #expect(dataPath.asURL.isDescendant(of: expectedScratchPath))
    }
  }

  @Test
  func testBasicSwiftArgs() async throws {
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let build = try await buildPath(root: packageRoot, platform: hostTriple.platformBuildPathComponent)

      _ = try #require(await buildSystemManager.initializationData?.indexDatabasePath)
      _ = try #require(await buildSystemManager.initializationData?.indexStorePath)
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      expectArgumentsContain("-module-name", "lib", arguments: arguments)
      expectArgumentsContain("-parse-as-library", arguments: arguments)

      expectArgumentsContain("-target", arguments: arguments)  // Only one!
      #if os(macOS)
      let versionString = PackageModel.Platform.macOS.oldestSupportedVersion.versionString
      expectArgumentsContain(
        "-target",
        try await hostTriple.tripleString(forPlatformVersion: versionString),
        arguments: arguments
      )
      expectArgumentsContain("-sdk", arguments: arguments)
      expectArgumentsContain("-F", arguments: arguments, allowMultiple: true)
      #else
      expectArgumentsContain("-target", try await hostTriple.tripleString, arguments: arguments)
      #endif

      expectArgumentsContain("-I", try build.appendingPathComponent("Modules").filePath, arguments: arguments)

      expectArgumentsContain(try aswift.filePath, arguments: arguments)
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aPlusSomething =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a+something.swift")

      _ = try #require(await buildSystemManager.initializationData?.indexStorePath)
      let pathWithPlusEscaped = "\(try aPlusSomething.filePath.replacing("+", with: "%2B"))"
      #if os(Windows)
      let urlWithPlusEscaped = try #require(URL(string: "file:///\(pathWithPlusEscaped)"))
      #else
      let urlWithPlusEscaped = try #require(URL(string: "file://\(pathWithPlusEscaped)"))
      #endif
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(urlWithPlusEscaped),
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      .compilerArguments

      // Check that we have both source files in the compiler arguments, which means that we didn't compute the compiler
      // arguments for a+something.swift using substitute arguments from a.swift.
      #expect(
        try arguments.contains(aPlusSomething.filePath),
        "Compiler arguments do not contain a+something.swift: \(arguments)"
      )
      #expect(
        try arguments.contains(
          packageRoot.appendingPathComponent("Sources").appendingPathComponent("lib").appendingPathComponent("a.swift")
            .filePath
        ),
        "Compiler arguments do not contain a.swift: \(arguments)"
      )
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(swiftPM: options),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")

      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      expectArgumentsContain("-typecheck", arguments: arguments)
      expectArgumentsContain("-Xcc", "-m32", arguments: arguments)
      expectArgumentsContain("-O", arguments: arguments)
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let source = try packageRoot.appendingPathComponent("Package.swift").realpath
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(source),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      expectArgumentsContain("-swift-version", "4.2", arguments: arguments)
      expectArgumentsContain(try source.filePath, arguments: arguments)
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
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

      let argumentsA = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      expectArgumentsContain(try aswift.filePath, arguments: argumentsA)
      expectArgumentsContain(try bswift.filePath, arguments: argumentsA)
      let argumentsB = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      expectArgumentsContain(try aswift.filePath, arguments: argumentsB)
      expectArgumentsContain(try bswift.filePath, arguments: argumentsB)
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
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
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      expectArgumentsContain(try aswift.filePath, arguments: arguments)
      expectArgumentsDoNotContain(try bswift.filePath, arguments: arguments)
      expectArgumentsContain(
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

      let argumentsB = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(bswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      expectArgumentsContain(try bswift.filePath, arguments: argumentsB)
      expectArgumentsDoNotContain(try aswift.filePath, arguments: argumentsB)
      expectArgumentsDoNotContain(
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

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
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
      _ = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      #expect(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(bswift),
          language: .swift,
          fallbackAfterTimeout: false
        )?.isFallback == true
      )
      #expect(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(URL(string: "https://www.apple.com")!),
          language: .swift,
          fallbackAfterTimeout: false
        )?.isFallback == true
      )
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
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

      _ = try #require(await buildSystemManager.initializationData?.indexStorePath)

      for file in [acxx, header] {
        let args = try #require(
          await buildSystemManager.buildSettingsInferredFromMainFile(
            for: DocumentURI(file),
            language: .cpp,
            fallbackAfterTimeout: false
          )
        ).compilerArguments

        expectArgumentsContain("-std=c++14", arguments: args)

        expectArgumentsDoNotContain("-arch", arguments: args)
        expectArgumentsContain("-target", arguments: args)  // Only one!
        #if os(macOS)
        let versionString = PackageModel.Platform.macOS.oldestSupportedVersion.versionString
        expectArgumentsContain(
          "-target",
          try await hostTriple.tripleString(forPlatformVersion: versionString),
          arguments: args
        )
        expectArgumentsContain("-isysroot", arguments: args)
        expectArgumentsContain("-F", arguments: args, allowMultiple: true)
        #else
        expectArgumentsContain("-target", try await hostTriple.tripleString, arguments: args)
        #endif

        expectArgumentsContain(
          "-I",
          try packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("lib")
            .appendingPathComponent("include")
            .filePath,
          arguments: args
        )
        expectArgumentsDoNotContain("-I", try build.filePath, arguments: args)
        expectArgumentsDoNotContain(try bcxx.filePath, arguments: args)

        URL(fileURLWithPath: try build.appendingPathComponent("lib.build").appendingPathComponent("a.cpp.o").filePath)
          .withUnsafeFileSystemRepresentation {
            expectArgumentsContain("-o", String(cString: $0!), arguments: args)
          }
      }
    }
  }

  @Test
  func testDeploymentTargetSwift() async throws {
    try await withTestScratchDir { tempDir in
      try FileManager.default.createFiles(
        root: tempDir,
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      expectArgumentsContain("-target", arguments: arguments)  // Only one!

      #if os(macOS)
      try await expectArgumentsContain(
        "-target",
        hostTriple.tripleString(forPlatformVersion: "10.13"),
        arguments: arguments
      )
      #else
      expectArgumentsContain("-target", try await hostTriple.tripleString, arguments: arguments)
      #endif
    }
  }

  @Test
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

      let buildSystemSpec = try #require(
        SwiftPMBuildSystem.searchForConfig(in: packageRoot, options: await .testDefault())
      )
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: buildSystemSpec,
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswiftSymlink =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let aswiftReal = try aswiftSymlink.realpath
      let manifest = packageRoot.appendingPathComponent("Package.swift")

      let argumentsFromSymlink = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswiftSymlink),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      // We opened the project from a symlink. The realpath isn't part of the project and we should thus not receive
      // build settings for it.
      #expect(
        try await #require(
          await buildSystemManager.buildSettingsInferredFromMainFile(
            for: DocumentURI(aswiftReal),
            language: .swift,
            fallbackAfterTimeout: false
          )
        ).isFallback
      )
      expectArgumentsContain(try aswiftSymlink.filePath, arguments: argumentsFromSymlink)
      expectArgumentsDoNotContain(try aswiftReal.filePath, arguments: argumentsFromSymlink)

      let argsManifest = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(manifest),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      expectArgumentsContain(try manifest.filePath, arguments: argsManifest)
      expectArgumentsDoNotContain(try manifest.realpath.filePath, arguments: argsManifest)
    }
  }

  @Test
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

      let buildSystemSpec = try #require(
        SwiftPMBuildSystem.searchForConfig(in: symlinkRoot, options: await .testDefault())
      )
      let buildSystemManager = await BuildSystemManager(
        buildSystemSpec: buildSystemSpec,
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      for file in [acpp, ah] {
        let args = try #require(
          await buildSystemManager.buildSettingsInferredFromMainFile(
            for: DocumentURI(symlinkRoot.appending(components: file)),
            language: .cpp,
            fallbackAfterTimeout: false
          )?
          .compilerArguments
        )
        expectArgumentsDoNotContain(try realRoot.appending(components: file).filePath, arguments: args)
        expectArgumentsContain(try symlinkRoot.appending(components: file).filePath, arguments: args)
      }
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("lib")
        .appendingPathComponent("a.swift")
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      .compilerArguments
      expectArgumentsContain(try aswift.filePath, arguments: arguments)
      _ = try #require(
        arguments.firstIndex(where: {
          $0.hasSuffix(".swift") && $0.contains("DerivedSources")
        }),
        "missing resource_bundle_accessor.swift from \(arguments)"
      )
    }
  }

  @Test
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

      let buildSystemSpec = SwiftPMBuildSystem.searchForConfig(in: workspaceRoot, options: try await .testDefault())
      #expect(buildSystemSpec == nil)
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift =
        packageRoot
        .appendingPathComponent("Plugins")
        .appendingPathComponent("MyPlugin")
        .appendingPathComponent("a.swift")

      _ = try #require(await buildSystemManager.initializationData?.indexStorePath)
      let arguments = try #require(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: DocumentURI(aswift),
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      // Plugins get compiled with the same compiler arguments as the package manifest
      expectArgumentsContain("-package-description-version", "5.7.0", arguments: arguments)
      expectArgumentsContain(try aswift.filePath, arguments: arguments)
    }
  }

  @Test
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
    #expect(
      tests == [
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

  @Test
  func testPackageLoadingWorkDoneProgress() async throws {
    let didReceiveWorkDoneProgressNotification = WrappedSemaphore(name: "work done progress received")
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/Test.swift": ""
      ],
      capabilities: ClientCapabilities(window: WindowClientCapabilities(workDoneProgress: true)),
      hooks: Hooks(
        buildSystemHooks: BuildSystemHooks(
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
    #expect(begin.value == .begin(WorkDoneProgressBegin(title: "SourceKit-LSP: Reloading Package")))
    didReceiveWorkDoneProgressNotification.signal()

    let end = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self)
    #expect(end.token == begin.token)
    #expect(end.value == .end(WorkDoneProgressEnd()))
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()
      let settings = await buildSystemManager.buildSettingsInferredFromMainFile(
        for: DocumentURI(versionSpecificManifestURL),
        language: .swift,
        fallbackAfterTimeout: false
      )
      let compilerArgs = try #require(settings?.compilerArguments)
      #expect(compilerArgs.contains("-package-description-version"))
      #expect(compilerArgs.contains(try versionSpecificManifestURL.filePath))
    }
  }

  @Test
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
        buildSystemSpec: .swiftpmSpec(for: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemHooks: BuildSystemHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()
      let settings = await buildSystemManager.buildSettingsInferredFromMainFile(
        for: DocumentURI(manifestURL),
        language: .swift,
        fallbackAfterTimeout: false
      )
      let compilerArgs = try #require(settings?.compilerArguments)
      expectArgumentsContain("-package-description-version", "5.1.0", arguments: compilerArgs)
      #expect(compilerArgs.contains(try manifestURL.filePath))
    }
  }
}

private func expectArgumentsDoNotContain(
  _ pattern: String...,
  arguments: [String],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  if let index = arguments.firstRange(of: pattern)?.startIndex {
    Issue.record(
      "not-pattern \(pattern) unexpectedly found at \(index) in arguments \(arguments)",
      sourceLocation: sourceLocation
    )
    return
  }
}

private func expectArgumentsContain(
  _ pattern: String...,
  arguments: [String],
  allowMultiple: Bool = false,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  guard let index = arguments.firstRange(of: pattern)?.startIndex else {
    Issue.record("pattern \(pattern) not found in arguments \(arguments)", sourceLocation: sourceLocation)
    return
  }

  if !allowMultiple, let index2 = arguments[(index + 1)...].firstRange(of: pattern)?.startIndex {
    Issue.record(
      "pattern \(pattern) found twice (\(index), \(index2)) in \(arguments)",
      sourceLocation: sourceLocation
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

fileprivate extension BuildSystemSpec {
  static func swiftpmSpec(for packageRoot: URL) -> BuildSystemSpec {
    return BuildSystemSpec(
      kind: .swiftPM,
      projectRoot: packageRoot,
      configPath: packageRoot.appendingPathComponent("Package.swift")
    )
  }
}

#endif
