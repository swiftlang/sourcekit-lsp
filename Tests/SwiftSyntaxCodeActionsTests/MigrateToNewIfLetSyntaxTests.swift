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

final class MigrateToNewIfLetSyntaxTests: XCTestCase {
  func testRefactoring() throws {
    let baselineSyntax: ExprSyntax = """
      if let x = x {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x {}
      """

    try assertRefactor(baselineSyntax, context: (), provider: MigrateToNewIfLetSyntax.self, expected: expectedSyntax)
  }

  func testIdempotence() throws {
    let baselineSyntax: ExprSyntax = """
      if let x = x {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x {}
      """

    try assertRefactor(baselineSyntax, context: (), provider: MigrateToNewIfLetSyntax.self, expected: expectedSyntax)
  }

  func testMultiBinding() throws {
    let baselineSyntax: ExprSyntax = """
      if let x = x, var y = y, let z = z {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x, var y, let z {}
      """

    try assertRefactor(baselineSyntax, context: (), provider: MigrateToNewIfLetSyntax.self, expected: expectedSyntax)
  }

  func testMixedBinding() throws {
    let baselineSyntax: ExprSyntax = """
      if let x = x, var y = x, let z = y.w {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x, var y = x, let z = y.w {}
      """

    try assertRefactor(baselineSyntax, context: (), provider: MigrateToNewIfLetSyntax.self, expected: expectedSyntax)
  }

  func testConditions() throws {
    let baselineSyntax: ExprSyntax = """
      if let x = x + 1, x == x, !x {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x = x + 1, x == x, !x {}
      """

    try assertRefactor(baselineSyntax, context: (), provider: MigrateToNewIfLetSyntax.self, expected: expectedSyntax)
  }

  func testWhitespaceNormalization() throws {
    let baselineSyntax: ExprSyntax = """
      if let x = x   , let y = y {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x, let y {}
      """

    try assertRefactor(baselineSyntax, context: (), provider: MigrateToNewIfLetSyntax.self, expected: expectedSyntax)
  }

  func testIfStmt() throws {
    let baselineSyntax: StmtSyntax = """
      if let x = x {}
      """

    let expectedSyntax: ExprSyntax = """
      if let x {}
      """

    let exprStmt = try XCTUnwrap(baselineSyntax.as(ExpressionStmtSyntax.self))
    try assertRefactor(
      exprStmt.expression,
      context: (),
      provider: MigrateToNewIfLetSyntax.self,
      expected: expectedSyntax
    )
  }
}
