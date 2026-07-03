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

import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxCodeActions
import XCTest

final class IntegerLiteralUtilitiesTests: XCTestCase {
  func testRadixMatching() {
    XCTAssertEqual((ExprSyntax("0b1010101").cast(IntegerLiteralExprSyntax.self)).radix, .binary)
    XCTAssertEqual((ExprSyntax("0xFF").cast(IntegerLiteralExprSyntax.self)).radix, .hex)
    XCTAssertEqual((ExprSyntax("0o777").cast(IntegerLiteralExprSyntax.self)).radix, .octal)
    XCTAssertEqual((ExprSyntax("42").cast(IntegerLiteralExprSyntax.self)).radix, .decimal)
  }

  func testSplit() {
    XCTAssertEqual((ExprSyntax("0b1010101").cast(IntegerLiteralExprSyntax.self)).split().prefix, "0b")
    XCTAssertEqual((ExprSyntax("0xFF").cast(IntegerLiteralExprSyntax.self)).split().prefix, "0x")
    XCTAssertEqual((ExprSyntax("0o777").cast(IntegerLiteralExprSyntax.self)).split().prefix, "0o")
    XCTAssertEqual((ExprSyntax("42").cast(IntegerLiteralExprSyntax.self)).split().prefix, "")
  }
}
