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

#if canImport(SPMBuildCore)
import SPMBuildCore
#endif
import Build
import LanguageServerProtocol
import SKCore
import SKSwiftPMWorkspace
import SKTestSupport
import TSCBasic
import TSCUtility
import XCTest

final class SwiftPMWorkspaceTests: XCTestCase {

  func testNoPackage() {
    let fs = InMemoryFileSystem()
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = ToolchainRegistry.shared
      XCTAssertThrowsError(try SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup))
    }
  }

  func testUnparsablePackage() {
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let pack
            """
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = ToolchainRegistry.shared
      XCTAssertThrowsError(try SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup))
    }
  }

  func testNoToolchain() {
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])])
            """
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      XCTAssertThrowsError(try SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: ToolchainRegistry(),
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup))
    }
  }

  func testBasicSwiftArgs() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])])
            """
      ])
      let packageRoot = resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let hostTriple = ws.buildParameters.triple
      let build = buildPath(root: packageRoot, triple: hostTriple)

      XCTAssertEqual(ws.buildPath, build)
      XCTAssertNotNil(ws.indexStorePath)
      let arguments = ws.settings(for: aswift.asURI, .swift)!.compilerArguments

      check(
        "-module-name", "lib", "-incremental", "-emit-dependencies",
        "-emit-module", "-emit-module-path", arguments: arguments)
      check("-parse-as-library", "-c", arguments: arguments)

      check("-target", arguments: arguments) // Only one!
  #if os(macOS)
      check("-target", hostTriple.tripleString(forPlatformVersion: "10.10"), arguments: arguments)
      check("-sdk", arguments: arguments)
      check("-F", arguments: arguments)
  #else
      check("-target", hostTriple.tripleString, arguments: arguments)
  #endif

      check("-I", build.pathString, arguments: arguments)

      check(aswift.pathString, arguments: arguments)
    }
  }

  func testBuildSetup() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])])
            """
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = ToolchainRegistry.shared

      let config = BuildSetup(
          configuration: .release,
          path: packageRoot.appending(component: "non_default_build_path"),
          flags: BuildFlags(xcc: ["-m32"], xcxx: [], xswiftc: ["-typecheck"], xlinker: []))

      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: config)

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let hostTriple = ws.buildParameters.triple
      let build = buildPath(root: packageRoot, config: config, triple: hostTriple)

      XCTAssertEqual(ws.buildPath, build)
      let arguments = ws.settings(for: aswift.asURI, .swift)!.compilerArguments

      check("-typecheck", arguments: arguments)
      check("-Xcc", "-m32", arguments: arguments)
      check("-O", arguments: arguments)
    }
  }

  func testManifestArgs() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])])
            """
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let source = resolveSymlinks(packageRoot.appending(component: "Package.swift"))
      let arguments = ws.settings(for: source.asURI, .swift)!.compilerArguments

      check("-swift-version", "4.2", arguments: arguments)
      check(source.pathString, arguments: arguments)
    }
  }

  func testMultiFileSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
      try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Sources/lib/b.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])])
            """
      ])
      let packageRoot = resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "lib", "b.swift")

      let argumentsA = ws.settings(for: aswift.asURI, .swift)!.compilerArguments
      check(aswift.pathString, arguments: argumentsA)
      check(bswift.pathString, arguments: argumentsA)
      let argumentsB = ws.settings(for: aswift.asURI, .swift)!.compilerArguments
      check(aswift.pathString, arguments: argumentsB)
      check(bswift.pathString, arguments: argumentsB)
    }
  }

  func testMultiTargetSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
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
            """
      ])
      let packageRoot = resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
      let arguments = ws.settings(for: aswift.asURI, .swift)!.compilerArguments
      check(aswift.pathString, arguments: arguments)
      checkNot(bswift.pathString, arguments: arguments)
      // Temporary conditional to work around revlock between SourceKit-LSP and SwiftPM
      // as a result of fix for SR-12050.  Can be removed when that fix has been merged.
      if arguments.joined(separator: " ").contains("-Xcc -I -Xcc") {
        check(
          "-Xcc", "-I", "-Xcc", packageRoot.appending(components: "Sources", "libC", "include").pathString,
          arguments: arguments)
      }
      else {
        check(
          "-I", packageRoot.appending(components: "Sources", "libC", "include").pathString,
          arguments: arguments)
      }

      let argumentsB = ws.settings(for: bswift.asURI, .swift)!.compilerArguments
      check(bswift.pathString, arguments: argumentsB)
      checkNot(aswift.pathString, arguments: argumentsB)
      checkNot("-I", packageRoot.appending(components: "Sources", "libC", "include").pathString,
        arguments: argumentsB)
    }
  }

  func testUnknownFile() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/libA/a.swift": "",
        "pkg/Sources/libB/b.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [
                .target(name: "libA", dependencies: []),
              ])
            """
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
      let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
      XCTAssertNotNil(ws.settings(for: aswift.asURI, .swift))
      XCTAssertNil(ws.settings(for: bswift.asURI, .swift))
      XCTAssertNil(ws.settings(for: DocumentURI(URL(string: "https://www.apple.com")!), .swift))
    }
  }

  func testBasicCXXArgs() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.cpp": "",
        "pkg/Sources/lib/b.cpp": "",
        "pkg/Sources/lib/include/a.h": "",
        "pkg/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])],
              cxxLanguageStandard: .cxx14)
            """
      ])
      let packageRoot = resolveSymlinks(tempDir.appending(component: "pkg"))
      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
      let bcxx = packageRoot.appending(components: "Sources", "lib", "b.cpp")
      let hostTriple = ws.buildParameters.triple
      let build = buildPath(root: packageRoot, triple: hostTriple)

      XCTAssertEqual(ws.buildPath, build)
      XCTAssertNotNil(ws.indexStorePath)

      let checkArgsCommon = { (arguments: [String]) in
        check("-std=c++14", arguments: arguments)

        checkNot("-arch", arguments: arguments)
        check("-target", arguments: arguments) // Only one!
    #if os(macOS)
        check("-target",
          hostTriple.tripleString(forPlatformVersion: "10.10"), arguments: arguments)
        check("-isysroot", arguments: arguments)
        check("-F", arguments: arguments)
    #else
        check("-target", hostTriple.tripleString, arguments: arguments)
    #endif

        check("-I", packageRoot.appending(components: "Sources", "lib", "include").pathString,
          arguments: arguments)
        checkNot("-I", build.pathString, arguments: arguments)
        checkNot(bcxx.pathString, arguments: arguments)
      }

      let args = ws.settings(for: acxx.asURI, .cpp)!.compilerArguments
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
      let headerArgs = ws.settings(for: header.asURI, .cpp)!.compilerArguments
      checkArgsCommon(headerArgs)

      check("-c", "-x", "c++-header", URL(fileURLWithPath: header.pathString).path,
            arguments: headerArgs)
    }
  }

  func testDeploymentTargetSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg/Sources/lib/a.swift": "",
        "pkg/Package.swift": """
            // swift-tools-version:5.0
            import PackageDescription
            let package = Package(name: "a",
              platforms: [.macOS(.v10_13)],
              products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])])
            """
      ])
      let packageRoot = tempDir.appending(component: "pkg")
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: ToolchainRegistry.shared,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let arguments = ws.settings(for: aswift.asURI, .swift)!.compilerArguments
      check("-target", arguments: arguments) // Only one!
      let hostTriple = ws.buildParameters.triple

      #if os(macOS)
        check("-target",
          hostTriple.tripleString(forPlatformVersion: "10.13"), arguments: arguments)
      #else
        check("-target", hostTriple.tripleString, arguments: arguments)
      #endif
    }
  }

  func testSymlinkInWorkspaceSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg_real/Sources/lib/a.swift": "",
        "pkg_real/Package.swift": """
        // swift-tools-version:4.2
        import PackageDescription
        let package = Package(name: "a", products: [], dependencies: [],
        targets: [.target(name: "lib", dependencies: [])])
        """
      ])
      let packageRoot = tempDir.appending(component: "pkg")

      try! FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: packageRoot.pathString),
        withDestinationURL: URL(fileURLWithPath: tempDir.appending(component: "pkg_real").pathString))

      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let aswift1 = packageRoot.appending(components: "Sources", "lib", "a.swift")
      let aswift2 = tempDir
        .appending(component: "pkg_real")
        .appending(components: "Sources", "lib", "a.swift")
      let manifest = packageRoot.appending(components: "Package.swift")

      let arguments1 = ws.settings(for: aswift1.asURI, .swift)?.compilerArguments
      let arguments2 = ws.settings(for: aswift2.asURI, .swift)?.compilerArguments
      XCTAssertNotNil(arguments1)
      XCTAssertNotNil(arguments2)
      XCTAssertEqual(arguments1, arguments2)

      checkNot(aswift1.pathString, arguments: arguments1 ?? [])
      check(resolveSymlinks(aswift1).pathString, arguments: arguments1 ?? [])

      let argsManifest = ws.settings(for: manifest.asURI, .swift)?.compilerArguments
      XCTAssertNotNil(argsManifest)

      checkNot(manifest.pathString, arguments: argsManifest ?? [])
      check(resolveSymlinks(manifest).pathString, arguments: argsManifest ?? [])
    }
  }

  func testSymlinkInWorkspaceCXX() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    try! withTemporaryDirectory(removeTreeOnDeinit: true) { tempDir in
      try! fs.createFiles(root: tempDir, files: [
        "pkg_real/Sources/lib/a.cpp": "",
        "pkg_real/Sources/lib/b.cpp": "",
        "pkg_real/Sources/lib/include/a.h": "",
        "pkg_real/Package.swift": """
            // swift-tools-version:4.2
            import PackageDescription
            let package = Package(name: "a", products: [], dependencies: [],
              targets: [.target(name: "lib", dependencies: [])],
              cxxLanguageStandard: .cxx14)
            """
      ])

      let packageRoot = tempDir.appending(component: "pkg")

      try! FileManager.default.createSymbolicLink(
        at: URL(fileURLWithPath: packageRoot.pathString),
        withDestinationURL: URL(fileURLWithPath: tempDir.appending(component: "pkg_real").pathString))

      let tr = ToolchainRegistry.shared
      let ws = try! SwiftPMWorkspace(
        workspacePath: packageRoot,
        toolchainRegistry: tr,
        fileSystem: fs,
        buildSetup: TestSourceKitServer.serverOptions.buildSetup)

      let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
      let ah = packageRoot.appending(components: "Sources", "lib", "include", "a.h")

      let argsCxx = ws.settings(for: acxx.asURI, .cpp)?.compilerArguments
      XCTAssertNotNil(argsCxx)
      check(acxx.pathString, arguments: argsCxx ?? [])
      checkNot(resolveSymlinks(acxx).pathString, arguments: argsCxx ?? [])

      let argsH = ws.settings(for: ah.asURI, .cpp)?.compilerArguments
      XCTAssertNotNil(argsH)
      checkNot(ah.pathString, arguments: argsH ?? [])
      check(resolveSymlinks(ah).pathString, arguments: argsH ?? [])
    }
  }
}

private func checkNot(
  _ pattern: String...,
  arguments: [String],
  file: StaticString = #filePath,
  line: UInt = #line)
{
  if let index = arguments.firstIndex(of: pattern) {
    XCTFail(
      "not-pattern \(pattern) unexpectedly found at \(index) in arguments \(arguments)",
      file: file, line: line)
    return
  }
}

private func check(
  _ pattern: String...,
  arguments: [String],
  file: StaticString = #filePath,
  line: UInt = #line)
{
  guard let index = arguments.firstIndex(of: pattern) else {
    XCTFail("pattern \(pattern) not found in arguments \(arguments)", file: file, line: line)
    return
  }

  if let index2 = arguments[(index+1)...].firstIndex(of: pattern) {
    XCTFail(
      "pattern \(pattern) found twice (\(index), \(index2)) in \(arguments)",
      file: file, line: line)
  }
}

private func buildPath(
  root: AbsolutePath,
  config: BuildSetup = TestSourceKitServer.serverOptions.buildSetup,
  triple: Triple) -> AbsolutePath
{
  let buildPath = config.path ?? root.appending(component: ".build")
  return buildPath.appending(components: triple.tripleString, "\(config.configuration)")
}
