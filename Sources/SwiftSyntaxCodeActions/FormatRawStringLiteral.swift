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

/// Format a string literal by inserting or removing the appropriate number of
/// raw string `#` delimiters.
///
/// ## Before
///
/// ```swift
/// "The # of values is \(count)"
/// "Hello \#(world)"
/// ###"Hello World"###
/// ```
///
/// ## After
///
/// ```swift
/// ##"The # of values is \(count)"##
/// ##"Hello \#(world)"##
/// "Hello World"
/// ```
package struct FormatRawStringLiteral: SyntaxRefactoringProvider {
  package static func refactor(syntax lit: StringLiteralExprSyntax, in context: Void) -> StringLiteralExprSyntax {
    var maximumHashes = 0
    for segment in lit.segments {
      switch segment {
      case .expressionSegment(let expr):
        if let rawStringDelimiter = expr.pounds {
          // Pick up any delimiters in interpolation segments \#...#(...)
          maximumHashes = max(maximumHashes, rawStringDelimiter.text.longestRun(of: "#"))
        }
      case .stringSegment(let string):
        // Find the longest run of # characters in the content of the literal.
        maximumHashes = max(maximumHashes, string.content.text.longestRun(of: "#"))
      #if RESILIENT_LIBRARIES
      @unknown default:
        fatalError()
      #endif
      }
    }

    guard maximumHashes > 0 else {
      return
        lit
        .with(\.openingPounds, lit.openingPounds?.with(\.tokenKind, .rawStringPoundDelimiter("")))
        .with(\.closingPounds, lit.closingPounds?.with(\.tokenKind, .rawStringPoundDelimiter("")))
    }

    let delimiters = String(repeating: "#", count: maximumHashes + 1)
    return
      lit
      .with(\.openingPounds, lit.openingPounds?.with(\.tokenKind, .rawStringPoundDelimiter(delimiters)))
      .with(\.closingPounds, lit.closingPounds?.with(\.tokenKind, .rawStringPoundDelimiter(delimiters)))
  }
}

extension String {
  fileprivate func longestRun(of needle: Character) -> Int {
    var longest = 0
    var it = self.makeIterator()
    while let c = it.next() {
      guard c == needle else {
        continue
      }

      var localLongest = 1
      while let c = it.next(), c == needle {
        localLongest += 1
        continue
      }

      longest = max(localLongest, longest)
    }
    return longest
  }
}
