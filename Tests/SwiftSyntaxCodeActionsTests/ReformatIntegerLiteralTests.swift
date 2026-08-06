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

final class ReformatIntegerLiteralTests: XCTestCase {
  func testSeparatorPlacement() throws {
    let tests: [(Int, literal: ExprSyntax, expectation: ExprSyntax)] = [
      (#line, literal: ExprSyntax("0b101010101"), expectation: ExprSyntax("0b1_0101_0101")),
      (#line, literal: ExprSyntax("0xFFFFFFFF"), expectation: ExprSyntax("0xFFFF_FFFF")),
      (#line, literal: ExprSyntax("0xFFFFF"), expectation: ExprSyntax("0xF_FFFF")),
      (#line, literal: ExprSyntax("0o777777"), expectation: ExprSyntax("0o777_777")),
      (#line, literal: ExprSyntax("424242424242"), expectation: ExprSyntax("424_242_424_242")),
      (#line, literal: ExprSyntax("100"), expectation: ExprSyntax("100")),
      (#line, literal: ExprSyntax("0xF_F_F_F_F_F_F_F"), expectation: ExprSyntax("0xFFFF_FFFF")),
      (#line, literal: ExprSyntax("0xFF_F_FF"), expectation: ExprSyntax("0xF_FFFF")),
      (#line, literal: ExprSyntax("0o7_77777"), expectation: ExprSyntax("0o777_777")),
      (#line, literal: ExprSyntax("4_24242424242"), expectation: ExprSyntax("424_242_424_242")),
    ]

    for (line, literal, expectation) in tests {
      try assertRefactor(
        literal.cast(IntegerLiteralExprSyntax.self),
        context: (),
        provider: AddSeparatorsToIntegerLiteral.self,
        expected: expectation.cast(IntegerLiteralExprSyntax.self),
        line: UInt(line)
      )
    }
  }

  func testSeparatorRemoval() throws {
    let tests: [(Int, literal: ExprSyntax, expectation: ExprSyntax)] = [
      (#line, literal: ExprSyntax("0b1_0_1_0_1_0_1_0_1"), expectation: ExprSyntax("0b101010101")),
      (#line, literal: ExprSyntax("0xFFF_F_FFFF"), expectation: ExprSyntax("0xFFFFFFFF")),
      (#line, literal: ExprSyntax("0xFF_FFF"), expectation: ExprSyntax("0xFFFFF")),
      (#line, literal: ExprSyntax("0o777_777"), expectation: ExprSyntax("0o777777")),
      (#line, literal: ExprSyntax("424_242_424_242"), expectation: ExprSyntax("424242424242")),
      (#line, literal: ExprSyntax("100"), expectation: ExprSyntax("100")),
    ]

    for (line, literal, expectation) in tests {
      try assertRefactor(
        literal.cast(IntegerLiteralExprSyntax.self),
        context: (),
        provider: RemoveSeparatorsFromIntegerLiteral.self,
        expected: expectation.cast(IntegerLiteralExprSyntax.self),
        line: UInt(line)
      )
    }
  }
}
