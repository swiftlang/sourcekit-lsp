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

    let originalHashCount = lit.openingPounds?.text.count ?? 0
    let maximumCandidateHashCount = max(maximumHashes + 1, originalHashCount)

    for hashCount in 0...maximumCandidateHashCount {
      let candidate = lit.withHashDelimiterCount(hashCount)
      if candidate.isValidReplacement(for: lit) {
        return candidate
      }
    }

    return lit
  }
}

private extension StringLiteralExprSyntax {
  func withHashDelimiterCount(_ hashCount: Int) -> StringLiteralExprSyntax {
    let delimiters = String(repeating: "#", count: hashCount)
    let openingPounds = self.openingPounds
    let closingPounds = self.closingPounds
    let candidateOpeningPounds =
      hashCount == 0
      ? nil
      : TokenSyntax.rawStringPoundDelimiter(
        delimiters,
        leadingTrivia: openingPounds?.leadingTrivia ?? self.openingQuote.leadingTrivia
      )

    let candidateClosingPounds =
      hashCount == 0
      ? nil
      : TokenSyntax.rawStringPoundDelimiter(
        delimiters,
        trailingTrivia: closingPounds?.trailingTrivia ?? self.closingQuote.trailingTrivia
      )

    let candidateOpeningQuote =
      hashCount == 0
      ? self.openingQuote.with(\.leadingTrivia, openingPounds?.leadingTrivia ?? self.openingQuote.leadingTrivia)
      : self.openingQuote.with(\.leadingTrivia, [])

    let candidateClosingQuote =
      hashCount == 0
      ? self.closingQuote.with(\.trailingTrivia, closingPounds?.trailingTrivia ?? self.closingQuote.trailingTrivia)
      : self.closingQuote.with(\.trailingTrivia, [])

    let segments = StringLiteralSegmentListSyntax(
      self.segments.map { segment in
        if case let .expressionSegment(expressionSegment) = segment {
          let candidatePounds =
            hashCount == 0
            ? nil
            : TokenSyntax.rawStringPoundDelimiter(
              delimiters,
              leadingTrivia: expressionSegment.pounds?.leadingTrivia ?? [],
              trailingTrivia: expressionSegment.pounds?.trailingTrivia ?? []
            )
          return .expressionSegment(expressionSegment.with(\.pounds, candidatePounds))
        }
        return segment
      }
    )

    return
      self
      .with(\.openingPounds, candidateOpeningPounds)
      .with(\.openingQuote, candidateOpeningQuote)
      .with(\.segments, segments)
      .with(\.closingQuote, candidateClosingQuote)
      .with(\.closingPounds, candidateClosingPounds)
  }

  func isValidReplacement(for original: StringLiteralExprSyntax) -> Bool {
    let source = self.description
    var parser = Parser(source)
    let parsedExpr = ExprSyntax.parse(from: &parser)

    guard !parsedExpr.hasError, parsedExpr.description == source else {
      return false
    }

    guard let parsedLiteral = parsedExpr.as(StringLiteralExprSyntax.self) else {
      return false
    }

    return parsedLiteral.representedLiteralValue == original.representedLiteralValue
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
