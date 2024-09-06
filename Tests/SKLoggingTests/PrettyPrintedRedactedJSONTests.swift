//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(Testing) import SKLogging
import SKTestSupport
import XCTest

class PrettyPrintedRedactedJSONTests: XCTestCase {
  func testRecursiveRedactedDescription() {
    struct Outer: Codable {
      struct Inner: Codable {
        var publicValue: Int
        var redactedValue: String
      }
      var inner: Inner
    }

    XCTAssertEqual(
      Outer(inner: Outer.Inner(publicValue: 42, redactedValue: "password")).prettyPrintedRedactedJSON,
      """
      {
        "inner" : {
          "publicValue" : 42,
          "redactedValue" : "<private 5e884898da280471>"
        }
      }
      """
    )
  }

  func testOptionalInt() {
    struct Struct: Codable {
      var value: Int?
    }

    XCTAssertEqual(
      Struct(value: 42).prettyPrintedRedactedJSON,
      """
      {
        "value" : 42
      }
      """
    )

    XCTAssertEqual(
      Struct(value: nil).prettyPrintedRedactedJSON,
      """
      {

      }
      """
    )
  }

  func testOptionalString() {
    struct Struct: Codable {
      var value: String?
    }

    XCTAssertEqual(
      Struct(value: "password").prettyPrintedRedactedJSON,
      """
      {
        "value" : "<private 5e884898da280471>"
      }
      """
    )

    XCTAssertEqual(
      Struct(value: nil).prettyPrintedRedactedJSON,
      """
      {

      }
      """
    )
  }

  func testDouble() {
    struct Struct: Codable {
      var value: Double
    }

    XCTAssertEqual(
      Struct(value: 4.5).prettyPrintedRedactedJSON,
      """
      {
        "value" : 4.5
      }
      """
    )
  }

  func testArrayOfStrings() {
    struct Struct: Codable {
      var value: [String]
    }

    XCTAssertEqual(
      Struct(value: ["password", "admin"]).prettyPrintedRedactedJSON,
      """
      {
        "value" : [
          "<private 5e884898da280471>",
          "<private 8c6976e5b5410415>"
        ]
      }
      """
    )
  }
}
