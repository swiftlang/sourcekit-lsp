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

import Build
import BuildServerProtocol
@_spi(Testing) import BuildSystemIntegration
import LanguageServerProtocol
import PackageModel
import SKOptions
import SKSupport
import SKTestSupport
import SourceKitLSP
import TSCBasic
import ToolchainRegistry
import XCTest

import struct Basics.Triple
import struct PackageModel.BuildFlags

#if canImport(SPMBuildCore)
@preconcurrency import SPMBuildCore
#endif

private var hostTriple: Triple {
  get async throws {
    let toolchain = try await unwrap(
      ToolchainRegistry.forTesting.preferredToolchain(containing: [\.clang, \.clangd, \.sourcekitd, \.swift, \.swiftc])
    )
    let destinationToolchainBinDir = try XCTUnwrap(toolchain.swiftc?.parentDirectory)

    let hostSDK = try SwiftSDK.hostSwiftSDK(.init(destinationToolchainBinDir))
    let hostSwiftPMToolchain = try UserToolchain(swiftSDK: hostSDK)

    return hostSwiftPMToolchain.targetTriple
  }
}

final class SwiftPMBuildSystemTests: XCTestCase {
  func testNoPackage() async throws {
    let fs = InMemoryFileSystem()
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": ""
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      XCTAssertNil(SwiftPMBuildSystem.projectRoot(for: packageRoot.asURL, options: .testDefault()))
    }
  }

  func testNoToolchain() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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

  func testBasicSwiftArgs() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let build = try await buildPath(root: packageRoot, platform: hostTriple.platformBuildPathComponent)

      assertNotNil(await buildSystemManager.initializationData?.indexDatabasePath)
      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
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

      assertArgumentsContain("-I", build.appending(component: "Modules").pathString, arguments: arguments)

      assertArgumentsContain(aswift.pathString, arguments: arguments)
    }
  }

  func testCompilerArgumentsForFileThatContainsPlusCharacterURLEncoded() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = try AbsolutePath(validating: tempDir.appending(component: "pkg").asURL.realpath.filePath)
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aPlusSomething = packageRoot.appending(components: "Sources", "lib", "a+something.swift")

      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)
      let pathWithPlusEscaped = "\(try aPlusSomething.asURL.filePath.replacing("+", with: "%2B"))"
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
        arguments.contains(aPlusSomething.pathString),
        "Compiler arguments do not contain a+something.swift: \(arguments)"
      )
      XCTAssert(
        arguments.contains(packageRoot.appending(components: "Sources", "lib", "a.swift").pathString),
        "Compiler arguments do not contain a.swift: \(arguments)"
      )
    }
  }

  func testBuildSetup() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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

      let options = SourceKitLSPOptions.SwiftPMOptions(
        configuration: .release,
        scratchPath: packageRoot.appending(component: "non_default_build_path").pathString,
        cCompilerFlags: ["-m32"],
        swiftCompilerFlags: ["-typecheck"]
      )

      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(swiftPM: options),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")

      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
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
      try localFileSystem.createFiles(
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
        projectRoot: tempDir.appending(component: "pkg"),
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
      try localFileSystem.createFiles(
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
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let source = try resolveSymlinks(packageRoot.appending(component: "Package.swift"))
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: source.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      assertArgumentsContain("-swift-version", "4.2", arguments: arguments)
      assertArgumentsContain(source.pathString, arguments: arguments)
    }
  }

  func testMultiFileSwift() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "lib", "b.swift")

      let argumentsA = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(aswift.pathString, arguments: argumentsA)
      assertArgumentsContain(bswift.pathString, arguments: argumentsA)
      let argumentsB = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(aswift.pathString, arguments: argumentsB)
      assertArgumentsContain(bswift.pathString, arguments: argumentsB)
    }
  }

  func testMultiTargetSwift() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(aswift.pathString, arguments: arguments)
      assertArgumentsDoNotContain(bswift.pathString, arguments: arguments)
      assertArgumentsContain(
        "-Xcc",
        "-I",
        "-Xcc",
        packageRoot.appending(components: "Sources", "libC", "include").pathString,
        arguments: arguments
      )

      let argumentsB = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: bswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      assertArgumentsContain(bswift.pathString, arguments: argumentsB)
      assertArgumentsDoNotContain(aswift.pathString, arguments: argumentsB)
      assertArgumentsDoNotContain(
        "-I",
        packageRoot.appending(components: "Sources", "libC", "include").pathString,
        arguments: argumentsB
      )
    }
  }

  func testUnknownFile() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = tempDir.appending(component: "pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
      assertNotNil(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      assertEqual(
        await buildSystemManager.buildSettingsInferredFromMainFile(
          for: bswift.asURI,
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
      try localFileSystem.createFiles(
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
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
      let bcxx = packageRoot.appending(components: "Sources", "lib", "b.cpp")
      let header = packageRoot.appending(components: "Sources", "lib", "include", "a.h")
      let build = buildPath(root: packageRoot, platform: try await hostTriple.platformBuildPathComponent)

      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)

      for file in [acxx, header] {
        let args = try await unwrap(
          buildSystemManager.buildSettingsInferredFromMainFile(
            for: file.asURI,
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
          packageRoot.appending(components: "Sources", "lib", "include").pathString,
          arguments: args
        )
        assertArgumentsDoNotContain("-I", build.pathString, arguments: args)
        assertArgumentsDoNotContain(bcxx.pathString, arguments: args)

        URL(fileURLWithPath: build.appending(components: "lib.build", "a.cpp.d").pathString)
          .withUnsafeFileSystemRepresentation {
            assertArgumentsContain("-MD", "-MT", "dependencies", "-MF", String(cString: $0!), arguments: args)
          }

        URL(fileURLWithPath: file.pathString).withUnsafeFileSystemRepresentation {
          assertArgumentsContain("-c", String(cString: $0!), arguments: args)
        }

        URL(fileURLWithPath: build.appending(components: "lib.build", "a.cpp.o").pathString)
          .withUnsafeFileSystemRepresentation {
            assertArgumentsContain("-o", String(cString: $0!), arguments: args)
          }
      }
    }
  }

  func testDeploymentTargetSwift() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = tempDir.appending(component: "pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
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
      try localFileSystem.createFiles(
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
      let packageRoot = tempDir.appending(component: "pkg")

      try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: packageRoot.pathString),
        withDestinationURL: URL(fileURLWithPath: tempDir.appending(component: "pkg_real").pathString)
      )

      let projectRoot = try XCTUnwrap(SwiftPMBuildSystem.projectRoot(for: packageRoot.asURL, options: .testDefault()))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: try AbsolutePath(validating: projectRoot.filePath)),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswiftSymlink = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let aswiftReal = try resolveSymlinks(aswiftSymlink)
      let manifest = packageRoot.appending(components: "Package.swift")

      let argumentsFromSymlink = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswiftSymlink.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      let argumentsFromReal = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswiftReal.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      // The arguments retrieved from the symlink and the real document should be the same, except that both should
      // contain they file the build settings were created.
      // FIXME: Or should the build settings always reference the main file?
      XCTAssertEqual(
        argumentsFromSymlink.filter { $0 != aswiftSymlink.pathString && $0 != aswiftReal.pathString },
        argumentsFromReal.filter { $0 != aswiftSymlink.pathString && $0 != aswiftReal.pathString }
      )

      assertArgumentsContain(aswiftSymlink.pathString, arguments: argumentsFromSymlink)
      assertArgumentsDoNotContain(aswiftReal.pathString, arguments: argumentsFromSymlink)

      assertArgumentsContain(aswiftReal.pathString, arguments: argumentsFromReal)
      assertArgumentsDoNotContain(aswiftSymlink.pathString, arguments: argumentsFromReal)

      let argsManifest = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: manifest.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments
      XCTAssertNotNil(argsManifest)

      assertArgumentsContain(manifest.pathString, arguments: argsManifest)
      assertArgumentsDoNotContain(try resolveSymlinks(manifest).pathString, arguments: argsManifest)
    }
  }

  func testSymlinkInWorkspaceCXX() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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

      let realRoot = tempDir.appending(component: "pkg_real")
      let symlinkRoot = tempDir.appending(component: "pkg")

      try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: symlinkRoot.pathString),
        withDestinationURL: URL(fileURLWithPath: tempDir.appending(component: "pkg_real").pathString)
      )

      let projectRoot = try XCTUnwrap(SwiftPMBuildSystem.projectRoot(for: symlinkRoot.asURL, options: .testDefault()))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: try AbsolutePath(validating: projectRoot.filePath)),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      for file in [acpp, ah] {
        let args = try unwrap(
          await buildSystemManager.buildSettingsInferredFromMainFile(
            for: symlinkRoot.appending(components: file).asURI,
            language: .cpp,
            fallbackAfterTimeout: false
          )?
          .compilerArguments
        )
        assertArgumentsDoNotContain(realRoot.appending(components: file).pathString, arguments: args)
        assertArgumentsContain(symlinkRoot.appending(components: file).pathString, arguments: args)
      }
    }
  }

  func testSwiftDerivedSources() async throws {
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      )
      .compilerArguments
      assertArgumentsContain(aswift.pathString, arguments: arguments)
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
      try localFileSystem.createFiles(
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
      let workspaceRoot = tempDir.appending(components: "pkg", "Sources", "lib").asURL
      let projectRoot = SwiftPMBuildSystem.projectRoot(for: workspaceRoot, options: .testDefault())

      assertEqual(projectRoot, tempDir.appending(component: "pkg").asURL)
    }
  }

  func testPluginArgs() async throws {
    #if os(Windows)
    // TODO: Enable this test once https://github.com/swiftlang/sourcekit-lsp/issues/1775 is fixed
    try XCTSkipIf(true, "https://github.com/swiftlang/sourcekit-lsp/issues/1775")
    #endif
    try await withTestScratchDir { tempDir in
      try localFileSystem.createFiles(
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
      let packageRoot = tempDir.appending(component: "pkg")
      let buildSystemManager = await BuildSystemManager(
        buildSystemKind: .swiftPM(projectRoot: packageRoot),
        toolchainRegistry: .forTesting,
        options: SourceKitLSPOptions(),
        connectionToClient: DummyBuildSystemManagerConnectionToClient(),
        buildSystemTestHooks: BuildSystemTestHooks()
      )
      await buildSystemManager.waitForUpToDateBuildGraph()

      let aswift = packageRoot.appending(components: "Plugins", "MyPlugin", "a.swift")

      assertNotNil(await buildSystemManager.initializationData?.indexStorePath)
      let arguments = try await unwrap(
        buildSystemManager.buildSettingsInferredFromMainFile(
          for: aswift.asURI,
          language: .swift,
          fallbackAfterTimeout: false
        )
      ).compilerArguments

      // Plugins get compiled with the same compiler arguments as the package manifest
      assertArgumentsContain("-package-description-version", "5.7.0", arguments: arguments)
      assertArgumentsContain(aswift.pathString, arguments: arguments)
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
  root: AbsolutePath,
  options: SourceKitLSPOptions.SwiftPMOptions = SourceKitLSPOptions.SwiftPMOptions(),
  platform: String
) -> AbsolutePath {
  let buildPath = AbsolutePath(validatingOrNil: options.scratchPath) ?? root.appending(component: ".build")
  return buildPath.appending(components: platform, "\(options.configuration ?? .debug)")
}
