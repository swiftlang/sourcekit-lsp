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
package import SwiftSyntax

/// Format an integer literal by inserting underscores at base-appropriate
/// locations.
///
/// This pass will also clean up any errant underscores.
///
/// ## Before
///
/// ```swift
/// 123456789
/// 0xFFFFFFFFF
/// 0b1_0_1_0
/// ```
///
/// ## After
///
/// ```swift
/// 123_456_789
/// 0xF_FFFF_FFFF
/// 0b1_010
/// ```
package struct AddSeparatorsToIntegerLiteral: SyntaxRefactoringProvider {
  package static func refactor(
    syntax lit: IntegerLiteralExprSyntax,
    in context: Void
  ) throws -> IntegerLiteralExprSyntax {
    if lit.literal.text.contains("_") {
      let strippedLiteral = try RemoveSeparatorsFromIntegerLiteral.refactor(syntax: lit)
      return self.addSeparators(to: strippedLiteral)
    } else {
      return self.addSeparators(to: lit)
    }
  }

  private static func addSeparators(to lit: IntegerLiteralExprSyntax) -> IntegerLiteralExprSyntax {
    var formattedText = ""
    let (prefix, value) = lit.split()
    formattedText += prefix
    formattedText += value.byAddingGroupSeparators(at: lit.idealGroupSize)
    return
      lit
      .with(\.literal, lit.literal.with(\.tokenKind, .integerLiteral(formattedText)))
  }
}

extension Substring {
  fileprivate func byAddingGroupSeparators(at interval: Int) -> String {
    var result = ""
    result.reserveCapacity(self.count)
    for (i, char) in self.filter({ $0 != "_" }).reversed().enumerated() {
      if i > 0 && i % interval == 0 {
        result.append("_")
      }
      result.append(char)
    }
    return String(result.reversed())
  }
}
