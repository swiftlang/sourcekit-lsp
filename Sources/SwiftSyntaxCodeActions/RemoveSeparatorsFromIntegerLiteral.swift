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

/// Format an integer literal by removing any existing separators.
///
/// ## Before
///
/// ```swift
/// 123_456_789
/// 0xF_FFFF_FFFF
/// ```
/// ## After
///
/// ```swift
/// 123456789
/// 0xFFFFFFFFF
/// ```
package struct RemoveSeparatorsFromIntegerLiteral: SyntaxRefactoringProvider {
  package static func refactor(syntax lit: IntegerLiteralExprSyntax, in context: Void) -> IntegerLiteralExprSyntax {
    guard lit.literal.text.contains("_") else { return lit }
    let formattedText = lit.literal.text.filter({ $0 != "_" })
    return lit.with(\.literal, lit.literal.with(\.tokenKind, .integerLiteral(formattedText)))
  }
}
