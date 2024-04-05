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

import SwiftSyntax
import LanguageServerProtocol
import SwiftRefactor

///
///
/// ## Before
/// ```swift
///
/// ```
///
/// ## After
/// ```swift
///
/// ```
struct Demorgan: CodeActionProvider {
  static var kind: CodeActionKind { .refactorRewrite }

  static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let op = token.parent?.as(InfixOperatorExprSyntax.self),
      token.totalByteRange.intersectsOrTouches(scope.range)
    else {
      return []
    }

    guard
      let opOp = op.operator.as(BinaryOperatorExprSyntax.self),
      let logicalOp = InfixOperatorExprSyntax.Logical(rawValue: opOp.operator.text)
    else {
      return []
    }

    var workList = [ op ]
    var terms = [ExprSyntax]()
    var operatorRanges = [ByteSourceRange]()

    // Find all the children with the same binary operator
    while let expr = workList.popLast() {
      func addTerm(_ expr: ExprSyntax) {
        guard let binOp = expr.as(InfixOperatorExprSyntax.self) else {
          terms.append(expr)
          return
        }

        guard
          let opOp = binOp.operator.as(BinaryOperatorExprSyntax.self),
          let childLogicalOp = InfixOperatorExprSyntax.Logical(rawValue: opOp.operator.text)
        else {
          terms.append(expr)
          return
        }


        if logicalOp == childLogicalOp {
          workList.append(binOp)
        } else {
          terms.append(ExprSyntax(binOp))
        }
      }

      operatorRanges.append(expr.operator.totalByteRange)

      addTerm(expr.leftOperand)
      addTerm(expr.rightOperand)
    }

    terms.sort(by: { $0.totalByteRange.offset < $1.totalByteRange.offset })
    var edits = [BuildableWorkspaceEdit]()
    if !terms.isEmpty {
      let lhs = terms.removeFirst()
      edits.append(Replace(lhs, with: lhs.inverted()))
    }

    if !terms.isEmpty {
      let rhs = terms.removeFirst()
      edits.append(Replace(rhs, with: rhs.inverted()))
    }

    for term in terms {
      edits.append(Replace(term, with: term.inverted()))
    }

    return [
      ProvidedAction(title: "Apply De Morgan's Law", edits: edits)
    ]
  }
}

extension ExprSyntax {
  func inverted() -> ExprSyntax {
    if let booleanLit = self.as(BooleanLiteralExprSyntax.self) {
      switch booleanLit.literal.text {
      case "true":
        return ExprSyntax(booleanLit.with(\.literal, .keyword(.false)))
      case "false":
        return ExprSyntax(booleanLit.with(\.literal, .keyword(.true)))
      default:
        return self
      }
    } else if let prefixOp = self.as(PrefixOperatorExprSyntax.self) {
      if prefixOp.operator.text == "!" {
        if
          let parens = prefixOp.expression.as(TupleExprSyntax.self),
          parens.elements.count == 1,
          let first = parens.elements.first,
          first.label == nil
        {
          // Unwrap !(...) to ...
          return first.expression
        } else {
          // Unwrap !... to ...
          return prefixOp.expression
        }
      } else {
        // Don't know what this is, leave it alone
        return self
      }
    } else if
      let infixOp = self.as(InfixOperatorExprSyntax.self),
      let binaryOp = infixOp.operator.as(BinaryOperatorExprSyntax.self)
    {
      if let comparison = InfixOperatorExprSyntax.Comparison(rawValue: binaryOp.operator.text) {
        // Replace x < y with x >= y
        return ExprSyntax(infixOp
          .with(\.operator, ExprSyntax(
            binaryOp
              .with(\.operator, .identifier(comparison.inverted.rawValue)))))
      } else {
        // Replace x <foo> y with !(x <foo> y)
        return ExprSyntax(PrefixOperatorExprSyntax(
          operator: .exclamationMarkToken(),
          expression: TupleExprSyntax(
            leftParen: .leftParenToken(),
            elementList: LabeledExprListSyntax([
              .init(expression: infixOp)
            ]),
            rightParen: .rightParenToken())))
      }
    } else {
      // Fallback
      return self
    }
  }
}

extension InfixOperatorExprSyntax {
  enum Logical: String {
    case and = "&&"
    case or = "||"

    var inverted: Logical {
      switch self {
      case .and:
        return .or
      case .or:
        return .and
      }
    }
  }

  enum Comparison: String {
    case equal = "=="
    case unequal = "!="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="

    var inverted: Comparison {
      switch self {
      case .equal:
        return .unequal
      case .unequal:
        return .equal
      case .lessThan:
        return .greaterThanOrEqual
      case .lessThanOrEqual:
        return .greaterThan
      case .greaterThan:
        return .lessThanOrEqual
      case .greaterThanOrEqual:
        return .lessThan
      }
    }
  }
}
