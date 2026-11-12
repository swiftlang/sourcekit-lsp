//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
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

final class ConvertToSwitchStmtTests: XCTestCase {
  private func assertRefactor(
    _ input: ExprSyntax,
    expected: ExprSyntax,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try SwiftSyntaxCodeActionsTests.assertRefactor(
      input,
      context: (),
      provider: ConvertToSwitchStmt.self,
      expected: expected,
      file: file,
      line: line
    )
  }

  private func assertRefactorNotApplicable(
    _ input: ExprSyntax,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try SwiftSyntaxCodeActionsTests.assertRefactor(
      input,
      context: (),
      provider: ConvertToSwitchStmt.self,
      expected: ExprSyntax?.none,
      file: file,
      line: line
    )
  }

  func testEqualityComparisons() throws {
    try assertRefactor(
      """
      if e == .first {
        print("first")
      } else if e == .second {
        print("second")
      }
      else {
        print("default")
      }
      """,
      expected: """
        switch e {
        case .first:
          print("first")
        case .second:
          print("second")
        default:
          print("default")
        }
        """
    )
  }

  func testMultipleStatementsInBody() throws {
    try assertRefactor(
      """
      if e == .first {
        print("first string")
        print("second string")
      } else {
        print("default")
      }
      """,
      expected: """
        switch e {
        case .first:
          print("first string")
          print("second string")
        default:
          print("default")
        }
        """
    )
  }

  func testWithoutElse() throws {
    try assertRefactor(
      """
      if e == .first {
        print("first")
      } else if e == .second {
        print("second")
      } else if e == .third {
        print("third")
      }
      """,
      expected: """
        switch e {
        case .first:
          print("first")
        case .second:
          print("second")
        case .third:
          print("third")
        default:
          break
        }
        """
    )
  }

  func testSubjectOnRightHandSide() throws {
    try assertRefactor(
      """
      if .first == e {
        print("first")
      } else if .second == e {
        print("second")
      } else {
        print("default")
      }
      """,
      expected: """
        switch e {
        case .first:
          print("first")
        case .second:
          print("second")
        default:
          print("default")
        }
        """
    )
  }

  func testSubjectOnDifferentSides() throws {
    try assertRefactor(
      """
      if E.first == e {
        print("first")
      } else if e == E.second {
        print("second")
      }
      """,
      expected: """
        switch e {
        case E.first:
          print("first")
        case E.second:
          print("second")
        default:
          break
        }
        """
    )
  }

  func testCasePattern() throws {
    try assertRefactor(
      """
      if case .some(let x) = someOptional {
        print(x)
      }
      """,
      expected: """
        switch someOptional {
        case .some(let x):
          print(x)
        default:
          break
        }
        """
    )
  }

  func testOptionalPattern() throws {
    try assertRefactor(
      """
      if case let x? = someOptional {
        print(x)
      }
      """,
      expected: """
        switch someOptional {
        case let x?:
          print(x)
        default:
          break
        }
        """
    )
  }

  func testOptionalBinding() throws {
    try assertRefactor(
      """
      if let unwrapped = optional {
        print(unwrapped)
      }
      """,
      expected: """
        switch optional {
        case let unwrapped?:
          print(unwrapped)
        default:
          break
        }
        """
    )
  }

  func testMutableOptionalBinding() throws {
    try assertRefactor(
      """
      if var unwrapped = optional {
        unwrapped += "!"
        print(unwrapped)
      }
      """,
      expected: """
        switch optional {
        case var unwrapped?:
          unwrapped += "!"
          print(unwrapped)
        default:
          break
        }
        """
    )
  }

  func testShorthandOptionalBinding() throws {
    try assertRefactor(
      """
      if let optional {
        print(optional)
      } else {
        print("nil")
      }
      """,
      expected: """
        switch optional {
        case let optional?:
          print(optional)
        default:
          print("nil")
        }
        """
    )
  }

  func testOrConditions() throws {
    try assertRefactor(
      """
      if e == .first || e == .second || e == .third {
        print("1-3")
      } else if e == .fourth {
        print("4")
      } else {
        print(">4")
      }
      """,
      expected: """
        switch e {
        case .first, .second, .third:
          print("1-3")
        case .fourth:
          print("4")
        default:
          print(">4")
        }
        """
    )
  }

  func testLabeledBreak() throws {
    try assertRefactor(
      """
      if e == .a {
        innerLabel: switch f {
        case .a:
          break outerLabel
        default:
          break innerLabel
        }
        print("outside switch")
      }
      """,
      expected: """
        switch e {
        case .a:
          innerLabel: switch f {
          case .a:
            break outerLabel
          default:
            break innerLabel
          }
          print("outside switch")
        default:
          break
        }
        """
    )
  }

  func testEnumWithAssociatedValues() throws {
    try assertRefactor(
      #"""
      if case .upc(let numberSystem, let manufacturer, let product, let check) = productBarcode {
        print("UPC : \(numberSystem), \(manufacturer), \(product), \(check).")
      } else if case let .qrCode(productCode) = productBarcode {
        print("QR code: \(productCode).")
      }
      """#,
      expected: #"""
        switch productBarcode {
        case .upc(let numberSystem, let manufacturer, let product, let check):
          print("UPC : \(numberSystem), \(manufacturer), \(product), \(check).")
        case let .qrCode(productCode):
          print("QR code: \(productCode).")
        default:
          break
        }
        """#
    )
  }

  func testPatternMatchOperator() throws {
    try assertRefactor(
      """
      if x == 5 {
        print("5")
      } else if x == 4 {
        print("4")
      } else if 1...3 ~= x {
        print("1...3")
      } else {
        print("default")
      }
      """,
      expected: """
        switch x {
        case 5:
          print("5")
        case 4:
          print("4")
        case 1...3:
          print("1...3")
        default:
          print("default")
        }
        """
    )
  }

  func testEquatableStruct() throws {
    try assertRefactor(
      """
      if y == MyType(v: "bye") {
        print("bye")
      } else if y == MyType(v: "tchau") {
        print("tchau")
      } else {
        print("default")
      }
      """,
      expected: """
        switch y {
        case MyType(v: "bye"):
          print("bye")
        case MyType(v: "tchau"):
          print("tchau")
        default:
          print("default")
        }
        """
    )
  }

  func testEmptyBody() throws {
    try assertRefactor(
      """
      if e == .first {}
      else if e == .second {
        print("second")
      }
      """,
      expected: """
        switch e {
        case .first:
          break
        case .second:
          print("second")
        default:
          break
        }
        """
    )
  }

  func testPropertyAsSubject() throws {
    try assertRefactor(
      """
      if self.state == .idle {
        start()
      } else if self.state == .running {
        stop()
      }
      """,
      expected: """
        switch self.state {
        case .idle:
          start()
        case .running:
          stop()
        default:
          break
        }
        """
    )
  }

  func testBodiesOnSingleLine() throws {
    try assertRefactor(
      """
      if x == 1 { one() } else if x == 2 { two() } else { other() }
      """,
      expected: """
        switch x {
        case 1:
            one()
        case 2:
            two()
        default:
            other()
        }
        """
    )
  }

  func testIndentedStatement() throws {
    let function: DeclSyntax = """
      func test(e: E) {
        if e == .first {
          print("first")
        } else if e == .second {
        }
      }
      """
    let ifExpr = try XCTUnwrap(
      function.as(FunctionDeclSyntax.self)?.body?.statements.first?.item.as(ExpressionStmtSyntax.self)?.expression
    )
    try assertRefactor(
      ifExpr,
      expected: """

          switch e {
          case .first:
            print("first")
          case .second:
            break
          default:
            break
          }
        """
    )
  }

  func testComments() throws {
    try assertRefactor(
      """
      if x == 1 { // one
        one()
        // done with one
      } else if x == 2 {
        // two
        two()
      } else { // other
        other()
      } // end
      """,
      expected: """
        switch x {
        case 1: // one
          one()
          // done with one
        case 2:
          // two
          two()
        default: // other
          other()
        } // end
        """
    )
  }

  func testBreakInNestedLoop() throws {
    try assertRefactor(
      """
      if x == 1 {
        for element in elements {
          break
        }
      }
      """,
      expected: """
        switch x {
        case 1:
          for element in elements {
            break
          }
        default:
          break
        }
        """
    )
  }

  func testUnlabeledBreak() throws {
    try assertRefactorNotApplicable(
      """
      if x == 1 {
        break
      } else if x == 2 {
        print("2")
      }
      """
    )
  }

  func testDifferentSubjects() throws {
    try assertRefactorNotApplicable(
      """
      if x == 1 {
        print("1")
      } else if y == 2 {
        print("2")
      }
      """
    )
  }

  func testDifferentSubjectsInOrCondition() throws {
    try assertRefactorNotApplicable(
      """
      if x == 1 || y == 2 {
        print("1 or 2")
      }
      """
    )
  }

  func testMultipleConditions() throws {
    try assertRefactorNotApplicable(
      """
      if x == 1, y == 2 {
        print("1 and 2")
      }
      """
    )
  }

  func testUnsupportedOperators() throws {
    try assertRefactorNotApplicable(
      """
      if x != 1 {
        print("not 1")
      }
      """
    )
    try assertRefactorNotApplicable(
      """
      if x == 1 && x == 2 {
        print("never")
      }
      """
    )
    try assertRefactorNotApplicable(
      """
      if x {
        print("true")
      }
      """
    )
  }

  func testSubjectWithSideEffects() throws {
    try assertRefactorNotApplicable(
      """
      if next() == 1 {
        print("1")
      } else if next() == 2 {
        print("2")
      }
      """
    )
    try assertRefactorNotApplicable(
      """
      if let value = compute() {
        print(value)
      }
      """
    )
  }

  func testLiteralsAreNotTheSubject() throws {
    try assertRefactorNotApplicable(
      """
      if 1 == 2 {
        print("never")
      }
      """
    )
  }

  func testAvailabilityCondition() throws {
    try assertRefactorNotApplicable(
      """
      if #available(macOS 15, *) {
        print("available")
      }
      """
    )
  }

  func testTypeAnnotation() throws {
    try assertRefactorNotApplicable(
      """
      if let value: Int = optional {
        print(value)
      }
      """
    )
  }
}
