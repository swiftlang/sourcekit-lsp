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
import SKTestSupport
import XCTest

final class SwiftPMWorkspaceTests: XCTestCase {
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
      fileSystem: fs)!

    let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")

    XCTAssertEqual(ws.buildPath, packageRoot.appending(components: ".build", "debug"))
    XCTAssertNotNil(ws.indexStorePath)
    let arguments = ws.settings(for: aswift.asURL, language: .swift)!.compilerArguments

    check(
      "-module-name", "lib", "-incremental", "-emit-dependencies",
      "-emit-module", "-emit-module-path", arguments: arguments)
    check("-parse-as-library", "-c", arguments: arguments)

    check("-target", arguments: arguments) // Only one!
#if os(macOS)
    check("-target", "x86_64-apple-macosx10.10", arguments: arguments)
    check("-sdk", arguments: arguments)
    check("-F", arguments: arguments)
#else
    check("-target", "x86_64-unknown-linux", arguments: arguments)
#endif

    check("-I", packageRoot.appending(components: ".build", "debug").asString, arguments: arguments)

    check(aswift.asString, arguments: arguments)
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
      fileSystem: fs)!

    let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
    let bswift = packageRoot.appending(components: "Sources", "lib", "b.swift")

    let argumentsA = ws.settings(for: aswift.asURL, language: .swift)!.compilerArguments
    check(aswift.asString, arguments: argumentsA)
    check(bswift.asString, arguments: argumentsA)
    let argumentsB = ws.settings(for: aswift.asURL, language: .swift)!.compilerArguments
    check(aswift.asString, arguments: argumentsB)
    check(bswift.asString, arguments: argumentsB)
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
      fileSystem: fs)!

    let aswift = packageRoot.appending(components: "Sources", "libA", "a.swift")
    let bswift = packageRoot.appending(components: "Sources", "libB", "b.swift")
    let arguments = ws.settings(for: aswift.asURL, language: .swift)!.compilerArguments
    check(aswift.asString, arguments: arguments)
    checkNot(bswift.asString, arguments: arguments)
    check("-I", packageRoot.appending(components: "Sources", "libC", "include").asString, arguments: arguments)

    let argumentsB = ws.settings(for: bswift.asURL, language: .swift)!.compilerArguments
    check(bswift.asString, arguments: argumentsB)
    checkNot(aswift.asString, arguments: argumentsB)
    checkNot("-I", packageRoot.appending(components: "Sources", "libC", "include").asString, arguments: argumentsB)
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
      fileSystem: fs)!

    let acxx = packageRoot.appending(components: "Sources", "lib", "a.cpp")
    let bcxx = packageRoot.appending(components: "Sources", "lib", "b.cpp")
    let build = packageRoot.appending(components: ".build", "debug")

    XCTAssertEqual(ws.buildPath, build)
    XCTAssertNotNil(ws.indexStorePath)
    let arguments = ws.settings(for: acxx.asURL, language: .cpp)!.compilerArguments

    check("-MD", "-MT", "dependencies",
      "-MF", build.appending(components: "lib.build", "a.cpp.d").asString,
      arguments: arguments)
    check("-std=c++14", arguments: arguments)

    checkNot("-arch", arguments: arguments)
    check("-target", arguments: arguments) // Only one!
#if os(macOS)
    check("-target", "x86_64-apple-macosx10.10", arguments: arguments)
    check("-isysroot", arguments: arguments)
    check("-F", arguments: arguments)
#else
    check("-target", "x86_64-unknown-linux", arguments: arguments)
#endif

    check("-I", packageRoot.appending(components: "Sources", "lib", "include").asString, arguments: arguments)
    checkNot("-I", build.asString, arguments: arguments)
    check("-c", acxx.asString, arguments: arguments)
    checkNot(bcxx.asString, arguments: arguments)
    check("-o", build.appending(components: "lib.build", "a.cpp.o").asString, arguments: arguments)
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
      fileSystem: fs)!

    let aswift = packageRoot.appending(components: "Sources", "lib", "a.swift")
    let arguments = ws.settings(for: aswift.asURL, language: .swift)!.compilerArguments
    check("-target", arguments: arguments) // Only one!
#if os(macOS)
    check("-target", "x86_64-apple-macosx10.13", arguments: arguments)
#else
    check("-target", "x86_64-unknown-linux", arguments: arguments)
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
