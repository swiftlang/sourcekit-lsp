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

import LanguageServerProtocol
import SKCore
import TSCBasic
import XCTest

import struct PackageModel.BuildFlags

final class FallbackBuildSystemTests: XCTestCase {

  func testSwift() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk")
    let source = try AbsolutePath(validating: "/my/source.swift")

    let bs = FallbackBuildSystem(buildSetup: .default)
    bs.sdkpath = sdk

    XCTAssertNil(bs.indexStorePath)
    XCTAssertNil(bs.indexDatabasePath)

    let settings = bs.settings(for: source.asURI, .swift)!
    XCTAssertNil(settings.workingDirectory)

    let args = settings.compilerArguments
    XCTAssertEqual(args, [
      "-sdk",
      sdk.pathString,
      source.pathString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURI, .swift)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testSwiftWithCustomFlags() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk")
    let source = try AbsolutePath(validating: "/my/source.swift")

    let buildSetup = BuildSetup(configuration: .debug, path: nil, flags: BuildFlags(swiftCompilerFlags: [
      "-Xfrontend",
      "-debug-constraints"
    ]))
    let bs = FallbackBuildSystem(buildSetup: buildSetup)
    bs.sdkpath = sdk

    let args = bs.settings(for: source.asURI, .swift)?.compilerArguments
    XCTAssertEqual(args, [
      "-Xfrontend",
      "-debug-constraints",
      "-sdk",
      sdk.pathString,
      source.pathString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURI, .swift)?.compilerArguments, [
      "-Xfrontend",
      "-debug-constraints",
      source.pathString,
    ])
  }

  func testSwiftWithCustomSDKFlag() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk")
    let source = try AbsolutePath(validating: "/my/source.swift")

    let buildSetup = BuildSetup(configuration: .debug, path: nil, flags: BuildFlags(swiftCompilerFlags: [
      "-sdk",
      "/some/custom/sdk",
      "-Xfrontend",
      "-debug-constraints",
    ]))
    let bs = FallbackBuildSystem(buildSetup: buildSetup)
    bs.sdkpath = sdk

    XCTAssertEqual(bs.settings(for: source.asURI, .swift)!.compilerArguments, [
      "-sdk",
      "/some/custom/sdk",
      "-Xfrontend",
      "-debug-constraints",
      source.pathString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURI, .swift)!.compilerArguments, [
      "-sdk",
      "/some/custom/sdk",
      "-Xfrontend",
      "-debug-constraints",
      source.pathString,
    ])
  }

  func testCXX() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk")
    let source = try AbsolutePath(validating: "/my/source.cpp")

    let bs = FallbackBuildSystem(buildSetup: .default)
    bs.sdkpath = sdk

    let settings = bs.settings(for: source.asURI, .cpp)!
    XCTAssertNil(settings.workingDirectory)

    let args = settings.compilerArguments
    XCTAssertEqual(args, [
      "-isysroot",
      sdk.pathString,
      source.pathString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURI, .cpp)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testCXXWithCustomFlags() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk")
    let source = try AbsolutePath(validating: "/my/source.cpp")

    let buildSetup = BuildSetup(configuration: .debug, path: nil, flags: BuildFlags(cxxCompilerFlags: [
      "-v"
    ]))
    let bs = FallbackBuildSystem(buildSetup: buildSetup)
    bs.sdkpath = sdk

    XCTAssertEqual(bs.settings(for: source.asURI, .cpp)?.compilerArguments, [
      "-v",
      "-isysroot",
      sdk.pathString,
      source.pathString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURI, .cpp)?.compilerArguments, [
      "-v",
      source.pathString,
    ])
  }

  func testCXXWithCustomIsysroot() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk")
    let source = try AbsolutePath(validating: "/my/source.cpp")

    let buildSetup = BuildSetup(configuration: .debug, path: nil, flags: BuildFlags(cxxCompilerFlags: [
      "-isysroot",
      "/my/custom/sdk",
      "-v"
    ]))
    let bs = FallbackBuildSystem(buildSetup: buildSetup)
    bs.sdkpath = sdk

    XCTAssertEqual(bs.settings(for: source.asURI, .cpp)?.compilerArguments, [
      "-isysroot",
      "/my/custom/sdk",
      "-v",
      source.pathString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURI, .cpp)?.compilerArguments, [
      "-isysroot",
      "/my/custom/sdk",
      "-v",
      source.pathString,
    ])
  }

  func testC() throws {
    let source = try AbsolutePath(validating: "/my/source.c")
    let bs = FallbackBuildSystem(buildSetup: .default)
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .c)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testCWithCustomFlags() throws {
    let source = try AbsolutePath(validating: "/my/source.c")

    let buildSetup = BuildSetup(configuration: .debug, path: nil, flags: BuildFlags(cCompilerFlags: [
      "-v"
    ]))
    let bs = FallbackBuildSystem(buildSetup: buildSetup)
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .c)?.compilerArguments, [
      "-v",
      source.pathString,
    ])
  }

  func testObjC() throws {
    let source = try AbsolutePath(validating: "/my/source.m")
    let bs = FallbackBuildSystem(buildSetup: .default)
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .objective_c)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testObjCXX() throws {
    let source = try AbsolutePath(validating: "/my/source.mm")
    let bs = FallbackBuildSystem(buildSetup: .default)
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .objective_cpp)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testUnknown() throws {
    let source = try AbsolutePath(validating: "/my/source.mm")
    let bs = FallbackBuildSystem(buildSetup: .default)
    XCTAssertNil(bs.settings(for: source.asURI, Language(rawValue: "unknown")))
  }
}
