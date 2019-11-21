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

final class FallbackBuildSystemTests: XCTestCase {

  func testSwift() {
    let sdk =  AbsolutePath("/my/sdk")
    let source = AbsolutePath("/my/source.swift")

    let bs = FallbackBuildSystem()
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

  func testCXX() {
    let sdk =  AbsolutePath("/my/sdk")
    let source = AbsolutePath("/my/source.cpp")

    let bs = FallbackBuildSystem()
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

  func testC() {
    let source = AbsolutePath("/my/source.c")
    let bs = FallbackBuildSystem()
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .c)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testObjC() {
    let source = AbsolutePath("/my/source.m")
    let bs = FallbackBuildSystem()
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .objective_c)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testObjCXX() {
    let source = AbsolutePath("/my/source.mm")
    let bs = FallbackBuildSystem()
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURI, .objective_cpp)?.compilerArguments, [
      source.pathString,
    ])
  }

  func testUnknown() {
    let source = AbsolutePath("/my/source.mm")
    let bs = FallbackBuildSystem()
    XCTAssertNil(bs.settings(for: source.asURI, Language(rawValue: "unknown")))
  }
}
