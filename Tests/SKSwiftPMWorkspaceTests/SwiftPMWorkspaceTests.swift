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
import LSPTestSupport
import LanguageServerProtocol
import PackageModel
@_spi(Testing) import SKCore
import SKSwiftPMWorkspace
import SKTestSupport
import SourceKitLSP
import TSCBasic
import XCTest

import struct PackageModel.BuildFlags

#if canImport(SPMBuildCore)
import SPMBuildCore
#endif

final class SwiftPMWorkspaceTests: XCTestCase {

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
      let tr = await ToolchainRegistry.forTesting
      await assertThrowsError(
        try await SwiftPMWorkspace(
          workspacePath: packageRoot,
          toolchainRegistry: tr,
          fileSystem: fs,
          buildSetup: SourceKitServer.Options.testDefault.buildSetup
        )
      )
    }
  }

  func testUnparsablePackage() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let pack
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = await ToolchainRegistry.forTesting
      await assertThrowsError(
        try await SwiftPMWorkspace(
          workspacePath: packageRoot,
          toolchainRegistry: tr,
          fileSystem: fs,
          buildSetup: SourceKitServer.Options.testDefault.buildSetup
        )
      )
    }
  }

  func testNoToolchain() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      await assertThrowsError(
        try await SwiftPMWorkspace(
          workspacePath: packageRoot,
          toolchainRegistry: ToolchainRegistry.empty,
          fileSystem: fs,
          buildSetup: SourceKitServer.Options.testDefault.buildSetup
        )
      )
    }
  }

  func testBasicSwiftArgs() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let hostTriple = await ws.buildParameters.targetTriple
      let build = buildPath(root: packageRoot, platform: hostTriple.platformBuildPathComponent)

      assertEqual(await ws.buildPath, build)
      assertNotNil(await ws.indexStorePath)
      let arguments = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments

      check(
        "-module-name",
        "lib",
        "-incremental",
        "-emit-dependencies",
        "-emit-module",
        "-emit-module-path",
        arguments: arguments
      )
      check("-parse-as-library", "-c", arguments: arguments)

      check("-target", arguments: arguments)  // Only one!
      #if os(macOS)
      let versionString = PackageModel.Platform.macOS.oldestSupportedVersion.versionString
      check("-target", hostTriple.tripleString(forPlatformVersion: versionString), arguments: arguments)
      check("-sdk", arguments: arguments)
      check("-F", arguments: arguments, allowMultiple: true)
      #else
      check("-target", hostTriple.tripleString, arguments: arguments)
      #endif

      check("-I", build.appending(component: "Modules").pathString, arguments: arguments)

      check(aswift.pathString, arguments: arguments)
    }
  }

  func testBuildSetup() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = await ToolchainRegistry.forTesting

      let config = BuildSetup(
        configuration: .release,
        defaultWorkspaceType: nil,
        path: packageRoot.appending(component: "non_default_build_path"),
        flags: BuildFlags(cCompilerFlags: ["-m32"], swiftCompilerFlags: ["-typecheck"])
      )

      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: config
      )

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let hostTriple = await ws.buildParameters.targetTriple
      let build = buildPath(root: packageRoot, config: config, platform: hostTriple.platformBuildPathComponent)

      assertEqual(await ws.buildPath, build)
      let arguments = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments

      check("-typecheck", arguments: arguments)
      check("-Xcc", "-m32", arguments: arguments)
      check("-O", arguments: arguments)
    }
  }

  func testManifestArgs() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let source = try resolveSymlinks(packageRoot.appending(component: "Package.swift"))
      let arguments = try await ws.buildSettings(for: source.asURI, language: .swift)!.compilerArguments

      check("-swift-version", "4.2", arguments: arguments)
      check(source.pathString, arguments: arguments)
    }
  }

  func testMultiFileSwift() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Sources/lib/b.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "lib", "b.swift")

      let argumentsA = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments
      check(aswift.pathString, arguments: argumentsA)
      check(bswift.pathString, arguments: argumentsA)
      let argumentsB = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments
      check(aswift.pathString, arguments: argumentsB)
      check(bswift.pathString, arguments: argumentsB)
    }
  }

  func testMultiTargetSwift() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/libA/a.swift": "",
          "pkg/Sources/libB/b.swift": "",
          "pkg/Sources/libC/include/libC.h": "",
          "pkg/Sources/libC/libC.c": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [
              .target(name: "libA", dependencies: ["libB", "libC"]),
              .target(name: "libB", dependencies: []),
              .target(name: "libC", dependencies: []),
            ])
          """,
        ]
      )
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
      let arguments = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments
      check(aswift.pathString, arguments: arguments)
      checkNot(bswift.pathString, arguments: arguments)
      // Temporary conditional to work around revlock between SourceKit-LSP and SwiftPM
      // as a result of fix for SR-12050.  Can be removed when that fix has been merged.
      if arguments.joined(separator: " ").contains("-Xcc -I -Xcc") {
        check(
          "-Xcc",
          "-I",
          "-Xcc",
          packageRoot.appending(components: "Sources", "libC", "include").pathString,
          arguments: arguments
        )
      } else {
        check(
          "-I",
          packageRoot.appending(components: "Sources", "libC", "include").pathString,
          arguments: arguments
        )
      }

      let argumentsB = try await ws.buildSettings(for: bswift.asURI, language: .swift)!.compilerArguments
      check(bswift.pathString, arguments: argumentsB)
      checkNot(aswift.pathString, arguments: argumentsB)
      checkNot(
        "-I",
        packageRoot.appending(components: "Sources", "libC", "include").pathString,
        arguments: argumentsB
      )
    }
  }

  func testUnknownFile() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/libA/a.swift": "",
          "pkg/Sources/libB/b.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [
              .target(name: "libA", dependencies: []),
            ])
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
      assertNotNil(try await ws.buildSettings(for: aswift.asURI, language: .swift))
      assertNil(try await ws.buildSettings(for: bswift.asURI, language: .swift))
      assertNil(try await ws.buildSettings(for: DocumentURI(URL(string: "https://www.apple.com")!), language: .swift))
    }
  }

  func testBasicCXXArgs() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.cpp": "",
          "pkg/Sources/lib/b.cpp": "",
          "pkg/Sources/lib/include/a.h": "",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])],
            cxxLanguageStandard: .cxx14)
          """,
        ]
      )
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
      let bcxx = packageRoot.appending(components: "Sources", "lib", "b.cpp")
      let hostTriple = await ws.buildParameters.targetTriple
      let build = buildPath(root: packageRoot, platform: hostTriple.platformBuildPathComponent)

      assertEqual(await ws.buildPath, build)
      assertNotNil(await ws.indexStorePath)

      let checkArgsCommon = { (arguments: [String]) in
        check("-std=c++14", arguments: arguments)

        checkNot("-arch", arguments: arguments)
        check("-target", arguments: arguments)  // Only one!
        #if os(macOS)
        let versionString = PackageModel.Platform.macOS.oldestSupportedVersion.versionString
        check(
          "-target",
          hostTriple.tripleString(forPlatformVersion: versionString),
          arguments: arguments
        )
        check("-isysroot", arguments: arguments)
        check("-F", arguments: arguments, allowMultiple: true)
        #else
        check("-target", hostTriple.tripleString, arguments: arguments)
        #endif

        check(
          "-I",
          packageRoot.appending(components: "Sources", "lib", "include").pathString,
          arguments: arguments
        )
        checkNot("-I", build.pathString, arguments: arguments)
        checkNot(bcxx.pathString, arguments: arguments)
      }

      let args = try await ws.buildSettings(for: acxx.asURI, language: .cpp)!.compilerArguments
      checkArgsCommon(args)

      URL(fileURLWithPath: build.appending(components: "lib.build", "a.cpp.d").pathString)
        .withUnsafeFileSystemRepresentation {
          check("-MD", "-MT", "dependencies", "-MF", String(cString: $0!), arguments: args)
        }

      URL(fileURLWithPath: acxx.pathString).withUnsafeFileSystemRepresentation {
        check("-c", String(cString: $0!), arguments: args)
      }

      URL(fileURLWithPath: build.appending(components: "lib.build", "a.cpp.o").pathString)
        .withUnsafeFileSystemRepresentation {
          check("-o", String(cString: $0!), arguments: args)
        }

      let header = packageRoot.appending(components: "Sources", "lib", "include", "a.h")
      let headerArgs = try await ws.buildSettings(for: header.asURI, language: .cpp)!.compilerArguments
      checkArgsCommon(headerArgs)

      check(
        "-c",
        "-x",
        "c++-header",
        try AbsolutePath(validating: URL(fileURLWithPath: header.pathString).path).pathString,
        arguments: headerArgs
      )
    }
  }

  func testDeploymentTargetSwift() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Package.swift": """
          // swift-tools-version:5.0
          import PackageDescription
          let package = Package(name: "a",
            platforms: [.macOS(.v10_13)],
            products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: ToolchainRegistry.forTesting,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let arguments = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments
      check("-target", arguments: arguments)  // Only one!
      let hostTriple = await ws.buildParameters.targetTriple

      #if os(macOS)
      check(
        "-target",
        hostTriple.tripleString(forPlatformVersion: "10.13"),
        arguments: arguments
      )
      #else
      check("-target", hostTriple.tripleString, arguments: arguments)
      #endif
    }
  }

  func testSymlinkInWorkspaceSwift() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg_real/Sources/lib/a.swift": "",
          "pkg_real/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
          targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = tempDir.appending(component: "pkg")

      try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: packageRoot.pathString),
        withDestinationURL: URL(fileURLWithPath: tempDir.appending(component: "pkg_real").pathString)
      )

      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift1 = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let aswift2 =
        tempDir
        .appending(component: "pkg_real")
        .appending(components: "Sources", "lib", "a.swift")
      let manifest = packageRoot.appending(components: "Package.swift")

      let arguments1 = try await ws.buildSettings(for: aswift1.asURI, language: .swift)?.compilerArguments
      let arguments2 = try await ws.buildSettings(for: aswift2.asURI, language: .swift)?.compilerArguments
      XCTAssertNotNil(arguments1)
      XCTAssertNotNil(arguments2)
      XCTAssertEqual(arguments1, arguments2)

      checkNot(aswift1.pathString, arguments: arguments1 ?? [])
      check(try resolveSymlinks(aswift1).pathString, arguments: arguments1 ?? [])

      let argsManifest = try await ws.buildSettings(for: manifest.asURI, language: .swift)?.compilerArguments
      XCTAssertNotNil(argsManifest)

      checkNot(manifest.pathString, arguments: argsManifest ?? [])
      check(try resolveSymlinks(manifest).pathString, arguments: argsManifest ?? [])
    }
  }

  func testSymlinkInWorkspaceCXX() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg_real/Sources/lib/a.cpp": "",
          "pkg_real/Sources/lib/b.cpp": "",
          "pkg_real/Sources/lib/include/a.h": "",
          "pkg_real/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])],
            cxxLanguageStandard: .cxx14)
          """,
        ]
      )

      let packageRoot = tempDir.appending(component: "pkg")

      try FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: packageRoot.pathString),
        withDestinationURL: URL(fileURLWithPath: tempDir.appending(component: "pkg_real").pathString)
      )

      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
      let ah = packageRoot.appending(components: "Sources", "lib", "include", "a.h")

      let argsCxx = try await ws.buildSettings(for: acxx.asURI, language: .cpp)?.compilerArguments
      XCTAssertNotNil(argsCxx)
      check(acxx.pathString, arguments: argsCxx ?? [])
      checkNot(try resolveSymlinks(acxx).pathString, arguments: argsCxx ?? [])

      let argsH = try await ws.buildSettings(for: ah.asURI, language: .cpp)?.compilerArguments
      XCTAssertNotNil(argsH)
      checkNot(ah.pathString, arguments: argsH ?? [])
      check(try resolveSymlinks(ah).pathString, arguments: argsH ?? [])
    }
  }

  func testSwiftDerivedSources() async throws {
    let fs = localFileSystem
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/a.swift": "",
          "pkg/Sources/lib/a.txt": "",
          "pkg/Package.swift": """
          // swift-tools-version:5.3
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [
              .target(
                name: "lib",
                dependencies: [],
                resources: [.copy("a.txt")])])
          """,
        ]
      )
      let packageRoot = try resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let arguments = try await ws.buildSettings(for: aswift.asURI, language: .swift)!.compilerArguments
      check(aswift.pathString, arguments: arguments)
      XCTAssertNotNil(
        arguments.firstIndex(where: {
          $0.hasSuffix(".swift") && $0.contains("DerivedSources")
        }),
        "missing resource_bundle_accessor.swift from \(arguments)"
      )
    }
  }

  func testNestedInvalidPackageSwift() async throws {
    let fs = InMemoryFileSystem()
    try await withTestScratchDir { tempDir in
      try fs.createFiles(
        root: tempDir,
        files: [
          "pkg/Sources/lib/Package.swift": "// not a valid package",
          "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
          targets: [.target(name: "lib", dependencies: [])])
          """,
        ]
      )
      let packageRoot = try resolveSymlinks(tempDir.appending(components: "pkg", "Sources", "lib"))
      let tr = await ToolchainRegistry.forTesting
      let ws = try await SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: SourceKitServer.Options.testDefault.buildSetup
      )

      assertEqual(await ws._packageRoot, try resolveSymlinks(tempDir.appending(component: "pkg")))
    }
  }
}

private func checkNot(
  _ pattern: String...,
  arguments: [String],
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if let index = arguments.firstIndex(of: pattern) {
    XCTFail(
      "not-pattern \(pattern) unexpectedly found at \(index) in arguments \(arguments)",
      file: file,
      line: line
    )
    return
  }
}

private func check(
  _ pattern: String...,
  arguments: [String],
  allowMultiple: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  guard let index = arguments.firstIndex(of: pattern) else {
    XCTFail("pattern \(pattern) not found in arguments \(arguments)", file: file, line: line)
    return
  }

  if !allowMultiple, let index2 = arguments[(index + 1)...].firstIndex(of: pattern) {
    XCTFail(
      "pattern \(pattern) found twice (\(index), \(index2)) in \(arguments)",
      file: file,
      line: line
    )
  }
}

private func buildPath(
  root: AbsolutePath,
  config: BuildSetup = SourceKitServer.Options.testDefault.buildSetup,
  platform: String
) -> AbsolutePath {
  let buildPath = config.path ?? root.appending(component: ".build")
  return buildPath.appending(components: platform, "\(config.configuration ?? .debug)")
}
