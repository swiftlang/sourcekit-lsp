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

import SwiftParser
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxCodeActions
import XCTest

final class FormatRawStringLiteralTests: XCTestCase {
  func testDelimiterPlacement() throws {
    let tests = [
      (#line, literal: #" "Hello World" "#, expectation: #" "Hello World" "#),
      (#line, literal: ##" #"Hello World" "##, expectation: ##" #"Hello World" "##),
      (#line, literal: ##" #"Hello World"# "##, expectation: #" "Hello World" "#),
      (#line, literal: #####" "####" "#####, expectation: #####" "####" "#####),
      (#line, literal: #####" #"####"# "#####, expectation: #####" "####" "#####),
      (#line, literal: #####" #"\####(hello)"# "#####, expectation: #####" ####"\####(hello)"#### "#####),
      (
        #line, literal: #######" #"###### \####(hello) ##"# "#######,
        expectation: #########" ####"###### \####(hello) ##"#### "#########
      ),
      (#line, literal: ########" #######"hello \(world) "####### "########, expectation: ##" #"hello \(world) "# "##),
      (#line, literal: ##" #""# "##, expectation: #" "" "#),
      (#line, literal: #####" #"#"# "#####, expectation: #####" "#" "#####),
      (#line, literal: ######" #"###"# "######, expectation: ######" "###" "######),
      (#line, literal: ####" ###"Plain"### "####, expectation: #" "Plain" "#),
      (#line, literal: ####" ###"Quote"Here"### "####, expectation: ##" #"Quote"Here"# "##),
      (#line, literal: ###"##"""##"###, expectation: ##"#"""#"##),
    ]

    for (line, literal, expectation) in tests {
      let literal = try XCTUnwrap(StringLiteralExprSyntax.parseWithoutDiagnostics(from: literal))
      let expectation = try XCTUnwrap(StringLiteralExprSyntax.parseWithoutDiagnostics(from: expectation))
      try assertRefactor(
        literal,
        context: (),
        provider: FormatRawStringLiteral.self,
        expected: expectation,
        line: UInt(line)
      )
    }
  }

  func testMinimizationPreservesParsedStringSemantics() throws {
    let tests = [
      (#line, literal: ##"#"""#"##, expectation: ##"#"""#"##),
      (#line, literal: ##"#"He says "Hi""#"##, expectation: ##"#"He says "Hi""#"##),
      (#line, literal: ##"#"C:\Users"#"##, expectation: ##"#"C:\Users"#"##),
      (#line, literal: ##"#"6 times 7 is \#(6 * 7)."#"##, expectation: #""6 times 7 is \(6 * 7).""#),
      (#line, literal: ####"###"Line1\###nLine2"###"####, expectation: ####"##"Line1\###nLine2"##"####),
      (#line, literal: ###"##"Hello"##"###, expectation: #""Hello""#),
      (#line, literal: ####"###"Hello ## world"###"####, expectation: ##""Hello ## world""##),
    ]

    for (line, literalSource, expectationSource) in tests {
      let literal = try XCTUnwrap(
        StringLiteralExprSyntax.parseWithoutDiagnostics(from: literalSource),
        line: UInt(line)
      )

      let candidate = FormatRawStringLiteral.refactor(syntax: literal, in: ())
      assertStringsEqualWithDiff(candidate.description, expectationSource, line: UInt(line))
      var parser = Parser(candidate.description)
      let parsedCandidate = ExprSyntax.parse(from: &parser)
      XCTAssertFalse(parsedCandidate.hasError, line: UInt(line))
      XCTAssertNotNil(parsedCandidate.as(StringLiteralExprSyntax.self), line: UInt(line))
      XCTAssertEqual(candidate.representedLiteralValue, literal.representedLiteralValue, line: UInt(line))
    }
  }
}

extension StringLiteralExprSyntax {
  static func parseWithoutDiagnostics(from source: String) -> StringLiteralExprSyntax? {
    var parser = Parser(source)
    return ExprSyntax.parse(from: &parser).as(StringLiteralExprSyntax.self)
  }
}
