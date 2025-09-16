//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SwiftRefactor
import SwiftSyntax

/// ConvertStringConcatenationToStringInterpolation is a code action that converts a valid string concatenation into a
/// string interpolation.
struct ConvertStringConcatenationToStringInterpolation: SyntaxRefactoringProvider {
  static func refactor(syntax: SequenceExprSyntax, in context: Void) throws -> SequenceExprSyntax {
    guard let (componentsOnly, commonPounds) = preflight(exprList: syntax.elements) else {
      throw RefactoringNotApplicableError("unsupported expression")
    }

    var segments: StringLiteralSegmentListSyntax = []
    for component in componentsOnly {
      guard let stringLiteral = component.as(StringLiteralExprSyntax.self) else {
        segments.append(
          .expressionSegment(
            ExpressionSegmentSyntax(
              pounds: commonPounds,
              expressions: [
                LabeledExprSyntax(expression: component.singleLineTrivia)
              ]
            )
          )
        )
        continue
      }

      if let commonPounds, stringLiteral.openingPounds?.tokenKind != commonPounds.tokenKind {
        segments += stringLiteral.segments.map { segment in
          if case let .expressionSegment(exprSegment) = segment {
            .expressionSegment(exprSegment.with(\.pounds, commonPounds))
          } else {
            segment
          }
        }
      } else {
        segments += stringLiteral.segments
      }
    }

    return syntax.with(
      \.elements,
      [
        ExprSyntax(
          StringLiteralExprSyntax(
            leadingTrivia: syntax.leadingTrivia,
            openingPounds: commonPounds,
            openingQuote: .stringQuoteToken(),
            segments: segments,
            closingQuote: .stringQuoteToken(),
            closingPounds: commonPounds,
            trailingTrivia: componentsOnly.last?.kind == .stringLiteralExpr ? syntax.trailingTrivia : nil
          )
        )
      ]
    )
  }

  @available(*, deprecated, message: "This method is deprecated. Please use throwing version instead.")
  static func refactor(syntax: SequenceExprSyntax, in context: Void) -> SequenceExprSyntax? {
    let newRefactor: (SequenceExprSyntax, Void) throws -> SequenceExprSyntax = refactor(syntax:in:)
    return try? newRefactor(syntax, context)
  }

  /// If `exprList` is a valid string concatenation, returns 1) all elements in `exprList` with concat operators
  /// stripped and 2) the longest pounds amongst all string literals, otherwise returns nil.
  ///
  /// `exprList` as a valid string concatenation must contain n >= 3 children where n is an odd number with a concat
  /// operator `+` separating every other child, which must either be a single-line string literal or a valid
  /// expression for string interpolation. `exprList` must also contain at least one string literal child.
  ///
  /// The following is a valid string concatenation.
  /// ``` swift
  /// "Hello " + aString + "\(1)World"
  /// ```
  /// The following are invalid string concatenations.
  /// ``` swift
  /// aString + bString // no string literals
  ///
  /// "Hello " * aString - "World" // non `+` operators
  ///
  /// """
  /// Hello
  /// """
  /// + """
  /// World
  /// """ // multi-line string literals
  /// ```
  private static func preflight(
    exprList: ExprListSyntax
  ) -> (componentsOnly: [ExprListSyntax.Element], longestPounds: TokenSyntax?)? {
    var iter = exprList.makeIterator()
    guard let first = iter.next() else {
      return nil
    }

    var hasStringComponents = false
    var longestPounds: TokenSyntax?
    var componentsOnly = [ExprListSyntax.Element]()
    componentsOnly.reserveCapacity(exprList.count / 2 + 1)

    if let stringLiteral = first.as(StringLiteralExprSyntax.self) {
      guard stringLiteral.isSingleLine else {
        return nil
      }
      hasStringComponents = true
      longestPounds = stringLiteral.openingPounds
    }
    componentsOnly.append(first)

    while let concat = iter.next(), let stringComponent = iter.next() {
      guard let concat = concat.as(BinaryOperatorExprSyntax.self),
        concat.operator.tokenKind == .binaryOperator("+") && !stringComponent.is(MissingExprSyntax.self)
      else {
        return nil
      }

      if let stringLiteral = stringComponent.as(StringLiteralExprSyntax.self) {
        guard stringLiteral.isSingleLine else {
          return nil
        }
        hasStringComponents = true
        if let pounds = stringLiteral.openingPounds,
          pounds.trimmedLength > (longestPounds?.trimmedLength ?? SourceLength(utf8Length: 0))
        {
          longestPounds = pounds
        }
      }

      componentsOnly[componentsOnly.count - 1].trailingTrivia += concat.leadingTrivia
      componentsOnly.append(
        stringComponent.with(\.leadingTrivia, stringComponent.leadingTrivia + concat.trailingTrivia)
      )
    }

    guard hasStringComponents && componentsOnly.count > 1 else {
      return nil
    }

    return (componentsOnly, longestPounds)
  }
}

extension ConvertStringConcatenationToStringInterpolation: SyntaxRefactoringCodeActionProvider {
  static let title: String = "Convert String Concatenation to String Interpolation"

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> SequenceExprSyntax? {
    guard let expr = scope.innermostNodeContainingRange,
      let seqExpr = expr.findParentOfSelf(
        ofType: SequenceExprSyntax.self,
        stoppingIf: {
          $0.kind == .codeBlockItem || $0.kind == .memberBlockItem
        }
      )
    else {
      return nil
    }

    return seqExpr
  }
}

private extension String {
  var uncommented: Substring {
    trimmingPrefix { $0 == "/" }
  }
}

private extension StringLiteralExprSyntax {
  var isSingleLine: Bool {
    openingQuote.tokenKind == .stringQuote
  }
}

private extension SyntaxProtocol {
  /// Modifies the trivia to not contain any newlines. This removes whitespace trivia, replaces newlines with
  /// whitespaces in block comments and converts line comments to block comments.
  var singleLineTrivia: Self {
    with(\.leadingTrivia, leadingTrivia.withSingleLineComments.withCommentsOnly(isLeadingTrivia: true))
      .with(\.trailingTrivia, trailingTrivia.withSingleLineComments.withCommentsOnly(isLeadingTrivia: false))
  }
}

private extension Trivia {
  /// Replaces newlines with whitespaces in block comments and converts line comments to block comments.
  var withSingleLineComments: Self {
    Trivia(
      pieces: map {
        switch $0 {
        case let .lineComment(lineComment):
          .blockComment("/*\(lineComment.uncommented)*/")
        case let .docLineComment(docLineComment):
          .docBlockComment("/**\(docLineComment.uncommented)*/")
        case let .blockComment(blockComment), let .docBlockComment(blockComment):
          .blockComment(blockComment.replacing("\r\n", with: " ").replacing("\n", with: " "))
        default:
          $0
        }
      }
    )
  }

  /// Removes all non-comment trivia pieces and inserts a whitespace between each comment.
  func withCommentsOnly(isLeadingTrivia: Bool) -> Self {
    Trivia(
      pieces: flatMap { piece -> [TriviaPiece] in
        if piece.isComment {
          if isLeadingTrivia {
            [piece, .spaces(1)]
          } else {
            [.spaces(1), piece]
          }
        } else {
          []
        }
      }
    )
  }
}
