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
      (#line, literal: ##" #"Hello World" "##, expectation: #" "Hello World" "#),
      (#line, literal: ##" #"Hello World"# "##, expectation: #" "Hello World" "#),
      (#line, literal: #####" "####" "#####, expectation: #####" "####" "#####),
      (#line, literal: #####" #"####"# "#####, expectation: ######" #####"####"##### "######),
      (#line, literal: #####" #"\####(hello)"# "#####, expectation: ######" #####"\####(hello)"##### "######),
      (
        #line, literal: #######" #"###### \####(hello) ##"# "#######,
        expectation: ########" #######"###### \####(hello) ##"####### "########
      ),
      // `\(world)` is literal text here, not an interpolation: a literal with
      // seven delimiters would spell an interpolation `\#######(world)`.
      // Dropping every delimiter would turn it into a real interpolation of
      // `world`, so one delimiter has to be kept.
      (
        #line, literal: ########" #######"hello \(world) "####### "########,
        expectation: ##" #"hello \(world) "# "##
      ),
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

  /// A literal whose content only stays literal because the literal is raw must
  /// keep at least one delimiter.
  func testDelimiterIsKeptWhenContentDependsOnBeingRaw() throws {
    let tests = [
      // #"""# used to become """, which opens a multiline literal.
      (#line, literal: ##" #"""# "##, expectation: ##" #"""# "##),
      // #"say "hi""# used to become "say "hi"", which does not parse.
      (#line, literal: ##" #"say "hi""# "##, expectation: ##" #"say "hi""# "##),
      // #"\"# used to become "\", which does not parse.
      (#line, literal: ##" #"\"# "##, expectation: ##" #"\"# "##),
      // #"a\nb"# used to become "a\nb", which still compiles but contains a
      // newline instead of a backslash followed by an `n`.
      (#line, literal: ##" #"a\nb"# "##, expectation: ##" #"a\nb"# "##),
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
}

extension StringLiteralExprSyntax {
  static func parseWithoutDiagnostics(from source: String) -> StringLiteralExprSyntax? {
    var parser = Parser(source)
    return ExprSyntax.parse(from: &parser).as(StringLiteralExprSyntax.self)
  }
}
