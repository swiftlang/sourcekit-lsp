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

import SKSwiftPMWorkspace
import SKCore
import PackageModel
import Basic
import SPMUtility
import SKTestSupport
import XCTest

final class SwiftPMWorkspaceTests: XCTestCase {

  func testNoPackage() {
    let fs = InMemoryFileSystem()
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    XCTAssertThrowsError(try SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)
    )
  }

  func testUnparsablePackage() {
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
      "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let pack
          """
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    XCTAssertThrowsError(try SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup))
  }

  func testNoToolchain() {
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
      "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
    XCTAssertThrowsError(try SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: ToolchainRegistry(),
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup))
  }

  func testBasicSwiftArgs() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
      "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
    let build = buildPath(root: packageRoot)

    XCTAssertEqual(ws.buildPath, build)
    XCTAssertNotNil(ws.indexStorePath)
    let arguments = ws.settings(for: aswift.asURL, .swift)!.compilerArguments

    check(
      "-module-name", "lib", "-incremental", "-emit-dependencies",
      "-emit-module", "-emit-module-path", arguments: arguments)
    check("-parse-as-library", "-c", arguments: arguments)

    check("-target", arguments: arguments) // Only one!
#if os(macOS)
    check("-target", "x86_64-apple-macosx10.10", arguments: arguments)
    check("-sdk", arguments: arguments)
    check("-F", arguments: arguments)
#elseif os(Linux)
    #if arch(powerpc64le)
      check("-target", "powerpc64le-unknown-linux", arguments: arguments)
    #else
      check("-target", "x86_64-unknown-linux", arguments: arguments)
    #endif
#endif

    check("-I", build.pathString, arguments: arguments)

    check(aswift.pathString, arguments: arguments)
  }

  func testBuildSetup() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
      "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
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
    let build = buildPath(root: packageRoot, config: config)

    XCTAssertEqual(ws.buildPath, build)
    let arguments = ws.settings(for: aswift.asURL, .swift)!.compilerArguments

    check("-typecheck", arguments: arguments)
    check("-Xcc", "-m32", arguments: arguments)
    check("-O", arguments: arguments)
  }

  func testManifestArgs() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
      "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let source = packageRoot.appending(component: "Package.swift")
    let arguments = ws.settings(for: source.asURL, .swift)!.compilerArguments

    check("-swift-version", "4.2", arguments: arguments)
    check(source.pathString, arguments: arguments)
  }

  func testMultiFileSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
      "pkg/Sources/lib/a.swift": "",
      "pkg/Sources/lib/b.swift": "",
      "pkg/Package.swift": """
          // swift-tools-version:4.2
          import PackageDescription
          let package = Package(name: "a", products: [], dependencies: [],
            targets: [.target(name: "lib", dependencies: [])])
          """
    ])
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
    let bswift = packageRoot.appending(components: "Sources", "lib", "b.swift")

    let argumentsA = ws.settings(for: aswift.asURL, .swift)!.compilerArguments
    check(aswift.pathString, arguments: argumentsA)
    check(bswift.pathString, arguments: argumentsA)
    let argumentsB = ws.settings(for: aswift.asURL, .swift)!.compilerArguments
    check(aswift.pathString, arguments: argumentsB)
    check(bswift.pathString, arguments: argumentsB)
  }

  func testMultiTargetSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
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
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
    let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
    let arguments = ws.settings(for: aswift.asURL, .swift)!.compilerArguments
    check(aswift.pathString, arguments: arguments)
    checkNot(bswift.pathString, arguments: arguments)
    check(
      "-I", packageRoot.appending(components: "Sources", "libC", "include").pathString,
      arguments: arguments)

    let argumentsB = ws.settings(for: bswift.asURL, .swift)!.compilerArguments
    check(bswift.pathString, arguments: argumentsB)
    checkNot(aswift.pathString, arguments: argumentsB)
    checkNot("-I", packageRoot.appending(components: "Sources", "libC", "include").pathString,
      arguments: argumentsB)
  }

  func testUnknownFile() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
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
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
    let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
    XCTAssertNotNil(ws.settings(for: aswift.asURL, .swift))
    XCTAssertNil(ws.settings(for: bswift.asURL, .swift))
    XCTAssertNil(ws.settings(for: URL(string: "https://www.apple.com")!, .swift))
  }

  func testBasicCXXArgs() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
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
    let packageRoot = tempDir.path.appending(component: "pkg")
    let tr = ToolchainRegistry.shared
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: tr,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
    let bcxx = packageRoot.appending(components: "Sources", "lib", "b.cpp")
    let build = buildPath(root: packageRoot)

    XCTAssertEqual(ws.buildPath, build)
    XCTAssertNotNil(ws.indexStorePath)

    let checkArgsCommon = { (arguments: [String]) in
      check("-std=c++14", arguments: arguments)

      checkNot("-arch", arguments: arguments)
      check("-target", arguments: arguments) // Only one!
  #if os(macOS)
      check("-target", "x86_64-apple-macosx10.10", arguments: arguments)
      check("-isysroot", arguments: arguments)
      check("-F", arguments: arguments)
  #elseif os(Linux)
      #if arch(powerpc64le)
        check("-target", "powerpc64le-unknown-linux", arguments: arguments)
      #else
        check("-target", "x86_64-unknown-linux", arguments: arguments)
      #endif
  #endif

      check("-I", packageRoot.appending(components: "Sources", "lib", "include").pathString,
        arguments: arguments)
      checkNot("-I", build.pathString, arguments: arguments)
      checkNot(bcxx.pathString, arguments: arguments)
    }

    let args = ws.settings(for: acxx.asURL, .cpp)!.compilerArguments
    checkArgsCommon(args)
    check("-MD", "-MT", "dependencies",
        "-MF", build.appending(components: "lib.build", "a.cpp.d").pathString,
        arguments: args)
    check("-c", acxx.pathString, arguments: args)
    check("-o", build.appending(components: "lib.build", "a.cpp.o").pathString, arguments: args)

    let header = packageRoot.appending(components: "Sources", "lib", "include", "a.h")
    let headerArgs = ws.settings(for: header.asURL, .cpp)!.compilerArguments
    checkArgsCommon(headerArgs)
    check("-c", "-x", "c++-header", header.pathString, arguments: headerArgs)
  }

  func testDeploymentTargetSwift() {
    // FIXME: should be possible to use InMemoryFileSystem.
    let fs = localFileSystem
    let tempDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
    try! fs.createFiles(root: tempDir.path, files: [
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
    let packageRoot = tempDir.path.appending(component: "pkg")
    let ws = try! SwiftPMWorkspace(
      workspacePath: packageRoot,
      toolchainRegistry: ToolchainRegistry.shared,
      fileSystem: fs,
      buildSetup: TestSourceKitServer.buildSetup)

    let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
    let arguments = ws.settings(for: aswift.asURL, .swift)!.compilerArguments
    check("-target", arguments: arguments) // Only one!
#if os(macOS)
    check("-target", "x86_64-apple-macosx10.13", arguments: arguments)
#elseif os(Linux)
    #if arch(powerpc64le)
      check("-target", "powerpc64le-unknown-linux", arguments: arguments)
    #else
      check("-target", "x86_64-unknown-linux", arguments: arguments)
    #endif
#endif

  }
}

private func checkNot(
  _ pattern: String...,
  arguments: [String],
  file: StaticString = #file,
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
  file: StaticString = #file,
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
  config: BuildSetup = TestSourceKitServer.buildSetup) -> AbsolutePath
{
  let buildConfig = "\(config.configuration)"
  if let absoluteBuildPath = config.path {
    #if os(macOS)
      return absoluteBuildPath.appending(components: "x86_64-apple-macosx", buildConfig)
    #elseif os(Linux)
      #if arch(powerpc64le)
        return absoluteBuildPath.appending(components: "powerpc64le-unknown-linux", buildConfig)
      #else
        return absoluteBuildPath.appending(components: "x86_64-unknown-linux", buildConfig)
      #endif
    #endif
  } else {
    #if os(macOS)
      return root.appending(components: ".build", "x86_64-apple-macosx", buildConfig)
    #elseif os(Linux)
        #if arch(powerpc64le)
          return root.appending(components: ".build", "powerpc64le-unknown-linux", buildConfig)
        #else
          return root.appending(components: ".build", "x86_64-unknown-linux", buildConfig)
        #endif
    #endif
  }
}
