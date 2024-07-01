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
import SwiftOperators
import SwiftRefactor
import SwiftSyntax

struct ApplyDeMorganLaw: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let token = scope.innermostNodeContainingRange else {
      return []
    }

    guard
      let (sourceExpr, sourceRange, deMorganExpr): (ExprSyntax, Range<Position>, ExprSyntax) =
        (token.greedilyWalkUp { parentExpr in
          let (sourceExpr, sourceRange) = parentExpr.preflight(scope: scope)
          guard
            let deMorganExpr =
              (sourceExpr.untuplifyWithNegationHoisted { singleChild in
                OperatorTable.standardOperators.foldAll(
                  singleChild,
                  errorHandler: { _ in
                  }
                ).appliedDeMorgan()
              })
          else {
            return nil
          }
          return (sourceExpr, sourceRange, deMorganExpr)
        })
    else {
      return []
    }

    let deMorganExprText = "\(deMorganExpr)"
    return [
      CodeAction(
        title: "Convert \(sourceExpr) to \(deMorganExprText)",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: sourceRange,
                newText: deMorganExprText
              )
            ]
          ]
        )
      )
    ]
  }
}

fileprivate extension SyntaxProtocol {
  /// performs a reverse DFS walking up the syntax tree to search for the outermost expression.
  func greedilyWalkUp<T>(transform: (ExprSyntax) -> T?) -> T? {
    parent?.findParentOfSelf(
      ofType: ExprSyntax.self,
      stoppingIf: { syntax in
        syntax.kind == .codeBlockItem || syntax.kind == .memberBlockItem || syntax.kind == .conditionElement
      }
    )?.greedilyWalkUp(transform: transform) ?? ExprSyntax(self).flatMap(transform)
  }

  func appliedDeMorgan() -> (expr: ExprSyntax, negationPrefix: String?)? {
    untuplifyWithNegationSeperated { expr in
      if let infixBinaryExpr = InfixOperatorExprSyntax(expr) {
        infixBinaryExpr.reducedDeMorgan().map {
          (ExprSyntax($0.negated), $0.negationPrefix)
        }
      } else if let negatedExpr = PrefixOperatorExprSyntax(expr) {
        ExprSyntax(negatedExpr.appliedDeMorgan()).map {
          ($0, nil)
        }
      } else {
        nil
      }
    }
  }

  /// Recursively walks down its syntax tree if this is a tuple and has a tuple as its single child.
  ///
  /// For example, exposes `a` from `((((a))))` for manipulation and returns `((((b))))`if `a` is transformed to `b`.
  func untuplify(transform: (ExprSyntax) throws -> (some ExprSyntaxProtocol)?) rethrows -> ExprSyntax? {
    if var tupleExpr = TupleExprSyntax(self),
      tupleExpr.elements.count == 1,
      var singleChild = tupleExpr.elements.first
    {
      guard let transformedChild = try singleChild.expression.untuplify(transform: transform) else {
        return nil
      }
      singleChild.expression = transformedChild
      tupleExpr.elements = [singleChild]

      return ExprSyntax(tupleExpr)
    } else {
      guard let expr = `as`(ExprSyntax.self), let transformed = try transform(expr) else {
        return nil
      }
      return ExprSyntax(transformed)
    }
  }

  /// Recursively walks down its syntax tree if this is a tuple and has a tuple as its single child.
  /// Any negation of the transformed expression shall be denoted by returning a non-null negationPrefix,
  /// the negation prefix will be hoisted to the top expression.
  ///
  /// For example, exposes `a` from `((((a))))` for manipulation and returns `!((((b))))`if `a` is transformed to `!b`.
  func untuplifyWithNegationHoisted(
    transform: (ExprSyntax) throws -> (expr: some ExprSyntaxProtocol, negationPrefix: String?)?
  )
    rethrows -> ExprSyntax?
  {
    let prefixOptrExpr: (expr: ExprSyntax, negationPrefix: String)

    if var tupleExpr = TupleExprSyntax(self),
      tupleExpr.elements.count == 1,
      var singleChild = tupleExpr.elements.first
    {
      guard
        let (singleChildExpr, negationPrefix) = try singleChild.expression.untuplifyWithNegationSeperated(
          transform: transform
        )
      else {
        return nil
      }
      singleChild.expression = singleChildExpr
      tupleExpr.elements = [singleChild]

      guard let negationPrefix else {
        return ExprSyntax(tupleExpr)
      }

      prefixOptrExpr = (ExprSyntax(tupleExpr), negationPrefix)
    } else {
      guard let expr = `as`(ExprSyntax.self), let (transformedExpr, negationPrefix) = try transform(expr) else {
        return nil
      }
      guard let negationPrefix else {
        return ExprSyntax(transformedExpr)
      }

      let prefixOptrChildExpr: ExprSyntax
      if var infixOptrExpr = InfixOperatorExprSyntax(transformedExpr) {
        let trailingTrivia = infixOptrExpr.trailingTrivia
        infixOptrExpr.trailingTrivia = []

        prefixOptrChildExpr = ExprSyntax(
          TupleExprSyntax(
            elements: [
              LabeledExprSyntax(expression: infixOptrExpr)
            ],
            trailingTrivia: trailingTrivia
          )
        )
      } else {
        prefixOptrChildExpr = ExprSyntax(transformedExpr)
      }

      prefixOptrExpr = (prefixOptrChildExpr, negationPrefix)
    }

    return ExprSyntax(
      PrefixOperatorExprSyntax(
        operator: .prefixOperator(prefixOptrExpr.negationPrefix),
        expression: prefixOptrExpr.expr
      )
    )
  }

  func untuplifyWithNegationSeperated(
    transform: (ExprSyntax) throws -> (expr: some ExprSyntaxProtocol, negationPrefix: String?)?
  )
    rethrows -> (expr: ExprSyntax, negationPrefix: String?)?
  {
    if var tupleExpr = TupleExprSyntax(self),
      tupleExpr.elements.count == 1,
      var singleChild = tupleExpr.elements.first
    {
      guard let (expr, negationPrefix) = try singleChild.expression.untuplifyWithNegationSeperated(transform: transform)
      else {
        return nil
      }
      singleChild.expression = expr
      tupleExpr.elements = [singleChild]

      return (ExprSyntax(tupleExpr), negationPrefix)
    } else {
      guard let expr = `as`(ExprSyntax.self), let (expr, negationPrefix) = try transform(expr) else {
        return nil
      }
      return (ExprSyntax(expr), negationPrefix)
    }
  }
}

fileprivate extension InfixOperatorExprSyntax {
  var tokenKindText: String {
    get {
      if let binaryOptrExpr = BinaryOperatorExprSyntax(`operator`) {
        binaryOptrExpr.tokenKindText
      } else {
        ""
      }
    }
    _modify {
      if var binaryOptrExpr = BinaryOperatorExprSyntax(`operator`) {
        yield &binaryOptrExpr.tokenKindText
        `operator` = ExprSyntax(binaryOptrExpr)
      } else {
        var dummy = ""
        yield &dummy
      }
    }
  }

  /// e.g. !(a && b && c == d) -> (!a || !b || c != d)
  func spreadDeMorgan(negationPrefix: String) -> ExprSyntax? {
    guard var binaryOptrExpr = BinaryOperatorExprSyntax(`operator`) else {
      return nil
    }

    let binaryOptrExprText = binaryOptrExpr.tokenKindText
    guard let reversedOptrText = binaryOptrExprText.reversedBinaryOperatorText(negationPrefix: negationPrefix),
      let falsyLeftOperand = leftOperand.negatedToFalsy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedOptrText
      ),
      let falsyRightOperand = rightOperand.negatedToFalsy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedOptrText
      )
    else {
      return nil
    }

    binaryOptrExpr.tokenKindText = reversedOptrText

    var infixOptrExpr = self
    infixOptrExpr.leftOperand = falsyLeftOperand
    infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)
    infixOptrExpr.rightOperand = falsyRightOperand

    return ExprSyntax(infixOptrExpr)
  }

  /// e.g. !a || !b || c != d -> !(a && b && c == d)
  func reducedDeMorgan() -> (negated: Self, negationPrefix: String)? {
    guard var binaryOptrExpr = BinaryOperatorExprSyntax(`operator`) else {
      return nil
    }

    let binaryOptrExprText = binaryOptrExpr.tokenKindText
    let negationPrefix: String
    switch binaryOptrExprText {
    case "||", "&&":
      negationPrefix = "!"
    case "|", "&":
      negationPrefix = "~"
    case _:
      return nil
    }

    guard let reversedBinaryOptrText = binaryOptrExprText.reversedBinaryOperatorText(negationPrefix: negationPrefix),
      let truthyLeftOperand = leftOperand.negatedToTruthy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedBinaryOptrText
      ),
      let truthyRightOperand = rightOperand.negatedToTruthy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedBinaryOptrText
      )
    else {
      return nil
    }

    binaryOptrExpr.tokenKindText = reversedBinaryOptrText

    var infixOptrExpr = self
    infixOptrExpr.leftOperand = truthyLeftOperand
    infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)
    infixOptrExpr.rightOperand = truthyRightOperand

    return (infixOptrExpr, negationPrefix)
  }
}

fileprivate extension BinaryOperatorExprSyntax {
  var tokenKindText: String {
    get {
      if case let .binaryOperator(text) = `operator`.tokenKind {
        text
      } else {
        ""
      }
    }
    set(value) {
      `operator`.tokenKind = .binaryOperator(value)
    }
  }
}

fileprivate extension ExprSyntaxProtocol {
  /// if this node is SequenceExprSyntax and its elements contain an AssignmentExpr,
  /// extracts all elements right to the AssignmentExpr and computes the extracted range,
  /// otherwise it is a no-op.
  ///
  ///  For example, we extract
  ///
  ///     b && c
  ///
  ///  from
  ///
  ///     a = b && c
  func preflight(scope: SyntaxCodeActionScope) -> (Self, Range<Position>) {
    let range = scope.snapshot.range(of: self)

    guard let seqExpr = SequenceExprSyntax(self) else {
      return (self, range)
    }

    let seqElements = seqExpr.elements
    guard
      let assignmentExprIdx = seqElements.firstIndex(where: { childExpr in
        childExpr.is(AssignmentExprSyntax.self)
      })
    else {
      return (self, range)
    }

    let slicingIndex = seqElements.index(after: assignmentExprIdx)
    guard slicingIndex < seqElements.endIndex else {
      return (self, range)
    }

    return (
      Self(
        SequenceExprSyntax(
          elements: ExprListSyntax(seqElements[slicingIndex...]),
          seqExpr.unexpectedAfterElements,
          trailingTrivia: seqExpr.trailingTrivia
        )
      )!, scope.snapshot.range(of: seqElements[slicingIndex]).lowerBound..<range.upperBound
    )
  }

  func negatedToTruthy(
    negationPrefix: String,
    binaryOptrExprText: String,
    reversedBinaryOptrExprText: String
  )
    -> ExprSyntax?
  {
    guard var infixOptrExpr = InfixOperatorExprSyntax(self),
      var binaryOptrExpr = BinaryOperatorExprSyntax(infixOptrExpr.operator),
      binaryOptrExpr.tokenKindText == binaryOptrExprText
    else {
      return untuplify { expr in
        if let falsyExpr = PrefixOperatorExprSyntax(expr), falsyExpr.tokenKindText == negationPrefix {
          return falsyExpr.expression
        } else if var infixOptrExpr = InfixOperatorExprSyntax(expr),
          var binaryOptrExpr = BinaryOperatorExprSyntax(infixOptrExpr.operator)
        {
          switch binaryOptrExpr.tokenKindText {
          case "!=":
            binaryOptrExpr.tokenKindText = "=="
          case "!==":
            binaryOptrExpr.tokenKindText = "==="
          case _:
            return nil
          }

          infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)
          return ExprSyntax(infixOptrExpr)
        } else {
          return nil
        }
      }
    }

    guard
      let truthyLeftOperand = infixOptrExpr.leftOperand.negatedToTruthy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedBinaryOptrExprText
      ),
      let truthyRightOperand = infixOptrExpr.rightOperand.negatedToTruthy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedBinaryOptrExprText
      )
    else {
      return nil
    }

    binaryOptrExpr.tokenKindText = reversedBinaryOptrExprText
    infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)
    infixOptrExpr.leftOperand = truthyLeftOperand
    infixOptrExpr.rightOperand = truthyRightOperand

    return ExprSyntax(infixOptrExpr)
  }

  func negatedToFalsy(
    negationPrefix: String,
    binaryOptrExprText: String,
    reversedBinaryOptrExprText: String
  )
    -> ExprSyntax?
  {
    guard var infixOptrExpr = InfixOperatorExprSyntax(self),
      var binaryOptrExpr = BinaryOperatorExprSyntax(infixOptrExpr.operator),
      binaryOptrExpr.tokenKindText == binaryOptrExprText
    else {
      return untuplifyWithNegationHoisted { singleChild in
        if var infixOptrExpr = InfixOperatorExprSyntax(singleChild),
          var binaryOptrExpr = BinaryOperatorExprSyntax(infixOptrExpr.operator)
        {
          let reversedBinaryOptrExprText: String
          switch binaryOptrExpr.tokenKindText {
          case "==":
            reversedBinaryOptrExprText = "!="
          case "===":
            reversedBinaryOptrExprText = "!=="
          case _:
            return (singleChild, negationPrefix)
          }

          binaryOptrExpr.tokenKindText = reversedBinaryOptrExprText
          infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)
          return (ExprSyntax(infixOptrExpr), nil)
        } else if let prefixOptrExpr = PrefixOperatorExprSyntax(singleChild),
          prefixOptrExpr.tokenKindText == negationPrefix
        {
          return nil
        } else {
          return (singleChild, negationPrefix)
        }
      }
    }

    guard
      let falsyLeftOperand = infixOptrExpr.leftOperand.negatedToFalsy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedBinaryOptrExprText
      ),
      let falsyRightOperand = infixOptrExpr.rightOperand.negatedToFalsy(
        negationPrefix: negationPrefix,
        binaryOptrExprText: binaryOptrExprText,
        reversedBinaryOptrExprText: reversedBinaryOptrExprText
      )
    else {
      return nil
    }

    binaryOptrExpr.tokenKindText = reversedBinaryOptrExprText
    infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)
    infixOptrExpr.leftOperand = falsyLeftOperand
    infixOptrExpr.rightOperand = falsyRightOperand

    return ExprSyntax(infixOptrExpr)
  }
}

fileprivate extension PrefixOperatorExprSyntax {
  var tokenKindText: String {
    get {
      if case let .prefixOperator(prefix) = `operator`.tokenKind {
        prefix
      } else {
        ""
      }
    }
    set(value) {
      `operator`.tokenKind = .binaryOperator(value)
    }
  }

  func appliedDeMorgan() -> ExprSyntax? {
    let negationPrefix = tokenKindText
    guard negationPrefix == "!" || negationPrefix == "~" else {
      return nil
    }

    return expression.untuplify { singleChild -> InfixOperatorExprSyntax? in
      guard var infixOptrExpr = InfixOperatorExprSyntax(singleChild),
        var binaryOptrExpr = BinaryOperatorExprSyntax(infixOptrExpr.operator)
      else {
        return nil
      }

      let binaryOptrExprText = binaryOptrExpr.tokenKindText
      guard
        let reversedBinaryOptrExprText = binaryOptrExprText.reversedBinaryOperatorText(negationPrefix: negationPrefix),
        let leftOperand = infixOptrExpr.leftOperand.negatedToFalsy(
          negationPrefix: negationPrefix,
          binaryOptrExprText: binaryOptrExprText,
          reversedBinaryOptrExprText: reversedBinaryOptrExprText
        ),
        let rightOperand = infixOptrExpr.rightOperand.negatedToFalsy(
          negationPrefix: negationPrefix,
          binaryOptrExprText: binaryOptrExprText,
          reversedBinaryOptrExprText: reversedBinaryOptrExprText
        )
      else {
        return nil
      }

      binaryOptrExpr.tokenKindText = reversedBinaryOptrExprText
      infixOptrExpr.leftOperand = leftOperand
      infixOptrExpr.rightOperand = rightOperand
      infixOptrExpr.operator = ExprSyntax(binaryOptrExpr)

      return infixOptrExpr
    }
  }
}

extension String {
  func reversedBinaryOperatorText(negationPrefix: String) -> Self? {
    switch (negationPrefix, self) {
    case ("!", "&&"):
      "||"
    case ("!", "||"):
      "&&"
    case ("~", "&"):
      "|"
    case ("~", "|"):
      "&"
    case _:
      nil
    }
  }
}
