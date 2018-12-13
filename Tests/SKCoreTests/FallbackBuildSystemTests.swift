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

@testable import SKCore

import Basic
import XCTest

final class FallbackBuildSystemTests: XCTestCase {

  func testSwift() {
    let sdk =  AbsolutePath("/my/sdk")
    let source = AbsolutePath("/my/source.swift")

    let bs = FallbackBuildSystem()
    bs.sdkpath = sdk

    XCTAssertNil(bs.indexStorePath)
    XCTAssertNil(bs.indexDatabasePath)

    let settings = bs.settings(for: source.asURL, .swift)!
    XCTAssertNil(settings.preferredToolchain)
    XCTAssertNil(settings.workingDirectory)

    let args = settings.compilerArguments
    XCTAssertEqual(args, [
      "-sdk",
      sdk.asString,
      source.asString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURL, .swift)?.compilerArguments, [
      source.asString,
    ])
  }

  func testCXX() {
    let sdk =  AbsolutePath("/my/sdk")
    let source = AbsolutePath("/my/source.cpp")

    let bs = FallbackBuildSystem()
    bs.sdkpath = sdk

    let settings = bs.settings(for: source.asURL, .cpp)!
    XCTAssertNil(settings.preferredToolchain)
    XCTAssertNil(settings.workingDirectory)

    let args = settings.compilerArguments
    XCTAssertEqual(args, [
      "-isysroot",
      sdk.asString,
      source.asString,
    ])

    bs.sdkpath = nil

    XCTAssertEqual(bs.settings(for: source.asURL, .cpp)?.compilerArguments, [
      source.asString,
    ])
  }

  func testC() {
    let source = AbsolutePath("/my/source.c")
    let bs = FallbackBuildSystem()
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURL, .c)?.compilerArguments, [
      source.asString,
    ])
  }

  func testObjC() {
    let source = AbsolutePath("/my/source.m")
    let bs = FallbackBuildSystem()
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURL, .objective_c)?.compilerArguments, [
      source.asString,
    ])
  }

  func testObjCXX() {
    let source = AbsolutePath("/my/source.mm")
    let bs = FallbackBuildSystem()
    bs.sdkpath = nil
    XCTAssertEqual(bs.settings(for: source.asURL, .objective_cpp)?.compilerArguments, [
      source.asString,
    ])
  }

  func testUnknown() {
    let source = AbsolutePath("/my/source.mm")
    let bs = FallbackBuildSystem()
    XCTAssertNil(bs.settings(for: source.asURL, .unknown))
  }
}
