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

import SwiftBasicFormat
import SwiftOperators
import SwiftRefactor
package import SwiftSyntax
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Converts an `if` statement whose conditions all match the same value to a `switch` statement.
///
/// A condition can compare the value using `==` or `~=`, combine such comparisons using `||`, match the value against
/// a pattern using `case` or unwrap it using `let` or `var`.
///
/// ## Before
///
/// ```swift
/// if direction == .north || direction == .south {
///   print("vertical")
/// } else if direction == .east {
///   print("east")
/// } else {
///   print("west")
/// }
/// ```
///
/// ## After
///
/// ```swift
/// switch direction {
/// case .north, .south:
///   print("vertical")
/// case .east:
///   print("east")
/// default:
///   print("west")
/// }
/// ```
package struct ConvertToSwitchStmt: SyntaxRefactoringProvider {
  package typealias Input = IfExprSyntax
  package typealias Output = SwitchExprSyntax

  package static func refactor(syntax ifExpr: IfExprSyntax, in context: Void = ()) throws -> SwitchExprSyntax {
    guard !ifExpr.hasError else {
      throw RefactoringNotApplicableError("syntax has errors")
    }

    var ifExprs = [ifExpr]
    while case .ifExpr(let elseIf) = ifExprs.last?.elseBody {
      ifExprs.append(elseIf)
    }
    let branchComparisons = try ifExprs.map { chainedIf in
      guard let condition = chainedIf.conditions.only, let comparisons = comparisons(in: condition.condition) else {
        throw RefactoringNotApplicableError("condition can't be converted to a 'case'")
      }
      // The patterns of a `case` are built from parts of the condition, which would drop the comment.
      guard !hasCommentInConditions(chainedIf) else {
        throw RefactoringNotApplicableError("condition contains a comment")
      }
      return comparisons
    }

    let subject = branchComparisons[0][0].subjects.first { subject in
      isReference(subject) && branchComparisons.joined().allSatisfy { $0.pattern(matching: subject) != nil }
    }
    guard let subject else {
      throw RefactoringNotApplicableError("conditions don't match the same value")
    }

    // An unlabeled `break` or a `fallthrough` would apply to the new `switch` statement instead of the loop or
    // `switch` statement around the `if` statement.
    let controlTransferFinder = SwitchControlTransferFinder(viewMode: .sourceAccurate)
    controlTransferFinder.walk(ifExpr)
    guard !controlTransferFinder.foundControlTransfer else {
      throw RefactoringNotApplicableError("'if' statement contains an unlabeled 'break' or a 'fallthrough'")
    }

    var branches: [Branch] = []
    var triviaBeforeBranch: Trivia = []
    for (chainedIf, comparisons) in zip(ifExprs, branchComparisons) {
      branches.append(
        Branch(
          patterns: comparisons.compactMap { $0.pattern(matching: subject) },
          triviaBeforeBranch: triviaBeforeBranch,
          triviaBeforeBody: chainedIf.conditions.trailingTrivia + chainedIf.body.leftBrace.leadingTrivia,
          body: chainedIf.body
        )
      )
      triviaBeforeBranch = triviaBeforeElseBranch(of: chainedIf)
    }
    let elseBlock: CodeBlockSyntax? = if case .codeBlock(let block) = ifExprs.last?.elseBody { block } else { nil }
    branches.append(Branch(patterns: [], triviaBeforeBranch: triviaBeforeBranch, triviaBeforeBody: [], body: elseBlock))

    let indentation = ifExpr.ifKeyword.indentationOfLine
    // Statements that are added or moved to a new line are indented like the existing statements, if there are any.
    let indentedStatement = branches.lazy.compactMap { $0.body?.statements.first }.first {
      $0.leadingTrivia.contains(where: \.isNewline)
    }
    let bodyIndentation =
      indentedStatement?.firstToken(viewMode: .sourceAccurate)?.indentationOfLine
      ?? indentation + (BasicFormat.inferIndentation(of: ifExpr.root) ?? .spaces(4))

    var cases: [SwitchCaseSyntax] = []
    var triviaBeforeLabel = Trivia.newline + indentation
    for branch in branches {
      // Comments between two branches go on their own lines in front of the label.
      for comment in branch.triviaBeforeBranch where comment.isComment {
        triviaBeforeLabel += [comment, .newlines(1)] + indentation
      }
      // Comments in front of and after the `{` of the body go after the `:` of the label.
      let triviaAfterLabel =
        branch.triviaBeforeBody.droppingTrailingWhitespace + (branch.body?.leftBrace.trailingTrivia ?? [])
      cases.append(
        SwitchCaseSyntax(
          leadingTrivia: triviaBeforeLabel,
          label: label(
            for: branch.patterns,
            colon: .colonToken(trailingTrivia: triviaAfterLabel.droppingTrailingWhitespace)
          ),
          statements: statements(in: branch.body, indentation: bodyIndentation)
        )
      )
      // Keep comments in front of the `}` of the body by putting them in front of the next label.
      if let rightBrace = branch.body?.rightBrace, rightBrace.leadingTrivia.contains(where: \.isNewline) {
        triviaBeforeLabel = rightBrace.leadingTrivia
      } else {
        triviaBeforeLabel = .newline + indentation
      }
    }

    return SwitchExprSyntax(
      leadingTrivia: ifExpr.leadingTrivia,
      switchKeyword: .keyword(.switch, trailingTrivia: .space),
      subject: subject.trimmed.with(\.trailingTrivia, .space),
      cases: SwitchCaseListSyntax(cases.map { .switchCase($0) }),
      rightBrace: .rightBraceToken(leadingTrivia: triviaBeforeLabel),
      trailingTrivia: ifExpr.trailingTrivia
    )
  }

  /// A branch of the `if` statement that becomes a `case` of the `switch` statement.
  private struct Branch {
    /// The patterns of the `case`, which are empty for the `default` case.
    var patterns: [PatternSyntax]
    /// The trivia between the `}` of the previous branch and the condition or the body of this branch.
    var triviaBeforeBranch: Trivia
    /// The trivia between the condition and the `{` of the body.
    var triviaBeforeBody: Trivia
    /// The body of the branch or `nil` if the `if` statement doesn't have an `else` branch.
    var body: CodeBlockSyntax?
  }

  /// A comparison in the condition of an `if` statement that can be expressed as the pattern of a `case`.
  private enum Comparison {
    /// `lhs == rhs`, where either of the operands can be the subject of the `switch` statement.
    case equality(ExprSyntax, ExprSyntax)
    /// `pattern ~= subject`, `case pattern = subject` or `let pattern = subject`.
    case match(PatternSyntax, subject: ExprSyntax)

    /// The expressions that can be the subject of the `switch` statement.
    var subjects: [ExprSyntax] {
      switch self {
      case .equality(let lhs, let rhs):
        return [lhs, rhs]
      case .match(_, let subject):
        return [subject]
      }
    }

    /// The pattern that `subject` is compared to or `nil` if the comparison doesn't have `subject` as an operand.
    func pattern(matching subject: ExprSyntax) -> PatternSyntax? {
      func isSubject(_ expr: ExprSyntax) -> Bool {
        return expr.trimmedDescription == subject.trimmedDescription
      }

      switch self {
      case .equality(let lhs, let rhs):
        if isSubject(lhs) {
          return PatternSyntax(ExpressionPatternSyntax(expression: rhs.trimmed))
        }
        if isSubject(rhs) {
          return PatternSyntax(ExpressionPatternSyntax(expression: lhs.trimmed))
        }
        return nil
      case .match(let pattern, subject: let matched):
        return isSubject(matched) ? pattern : nil
      }
    }
  }

  private static func comparisons(in condition: ConditionElementSyntax.Condition) -> [Comparison]? {
    switch condition {
    case .expression(let expr):
      return comparisons(in: expr)
    case .matchingPattern(let matchingPattern):
      guard matchingPattern.typeAnnotation == nil else {
        return nil
      }
      return [.match(matchingPattern.pattern.trimmed, subject: matchingPattern.initializer.value)]
    case .optionalBinding(let binding):
      guard binding.typeAnnotation == nil else {
        return nil
      }
      let subject: ExprSyntax
      if let initializer = binding.initializer {
        subject = initializer.value
      } else if let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier {
        subject = ExprSyntax(DeclReferenceExprSyntax(baseName: identifier.trimmed))
      } else {
        return nil
      }
      // `let x = subject` matches the same values as `case let x? = subject`.
      let pattern = ValueBindingPatternSyntax(
        bindingSpecifier: binding.bindingSpecifier.trimmed.with(\.trailingTrivia, .space),
        pattern: ExpressionPatternSyntax(
          expression: OptionalChainingExprSyntax(expression: PatternExprSyntax(pattern: binding.pattern.trimmed))
        )
      )
      return [.match(PatternSyntax(pattern), subject: subject)]
    case .availability:
      return nil
    }
  }

  /// The comparisons that `expr` consists of, which are combined using `||`.
  private static func comparisons(in expr: ExprSyntax) -> [Comparison]? {
    // The parser doesn't apply operator precedence, so fold the expression to find the comparisons.
    if let sequence = expr.as(SequenceExprSyntax.self) {
      guard let folded = try? OperatorTable.standardOperators.foldSingle(sequence) else {
        return nil
      }
      return comparisons(in: folded)
    }
    if let tuple = expr.as(TupleExprSyntax.self), let element = tuple.elements.only, element.label == nil {
      return comparisons(in: element.expression)
    }
    guard let infixOperator = expr.as(InfixOperatorExprSyntax.self),
      let binaryOperator = infixOperator.operator.as(BinaryOperatorExprSyntax.self)
    else {
      return nil
    }
    let lhs = infixOperator.leftOperand
    let rhs = infixOperator.rightOperand
    switch binaryOperator.operator.text {
    case "||":
      guard let lhsComparisons = comparisons(in: lhs), let rhsComparisons = comparisons(in: rhs) else {
        return nil
      }
      return lhsComparisons + rhsComparisons
    case "==":
      return [.equality(lhs, rhs)]
    case "~=":
      return [.match(PatternSyntax(ExpressionPatternSyntax(expression: lhs.trimmed)), subject: rhs)]
    default:
      return nil
    }
  }

  /// Whether there is a comment between the `if` keyword of `ifExpr` and the last token of its conditions.
  private static func hasCommentInConditions(_ ifExpr: IfExprSyntax) -> Bool {
    let conditions = ifExpr.conditions.with(\.trailingTrivia, [])
    let trivia = conditions.tokens(viewMode: .sourceAccurate).reduce(ifExpr.ifKeyword.trailingTrivia) {
      $0 + $1.trivia
    }
    return trivia.contains(where: \.isComment)
  }

  /// The trivia between the `}` of the body of `ifExpr` and the `if` keyword or the `{` of its `else` branch.
  private static func triviaBeforeElseBranch(of ifExpr: IfExprSyntax) -> Trivia {
    guard let elseKeyword = ifExpr.elseKeyword, let elseBody = ifExpr.elseBody else {
      return []
    }
    return ifExpr.body.rightBrace.trailingTrivia + elseKeyword.trivia + elseBody.leadingTrivia
  }

  /// Whether `expr` refers to a variable or a property, like `x` or `x.y`.
  ///
  /// An `if` statement with more than one comparison evaluates the subject for every comparison that it checks, but the
  /// `switch` statement only evaluates it once, so it shouldn't be an expression that might have side effects.
  private static func isReference(_ expr: ExprSyntax) -> Bool {
    if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
      guard let base = memberAccess.base else {
        return false
      }
      return isReference(base)
    }
    return expr.is(DeclReferenceExprSyntax.self)
  }

  /// The label of a `case` that matches `patterns` or the `default` label if `patterns` is empty.
  private static func label(for patterns: [PatternSyntax], colon: TokenSyntax) -> SwitchCaseSyntax.Label {
    guard let lastPattern = patterns.last else {
      return .default(SwitchDefaultLabelSyntax(colon: colon))
    }
    var caseItems = patterns.dropLast().map {
      SwitchCaseItemSyntax(pattern: $0, trailingComma: .commaToken(trailingTrivia: .space))
    }
    caseItems.append(SwitchCaseItemSyntax(pattern: lastPattern))
    return .case(
      SwitchCaseLabelSyntax(
        caseKeyword: .keyword(.case, trailingTrivia: .space),
        caseItems: SwitchCaseItemListSyntax(caseItems),
        colon: colon
      )
    )
  }

  /// The statements of `body` as the statements of a `case`, or `break` if there are none.
  private static func statements(in body: CodeBlockSyntax?, indentation: Trivia) -> CodeBlockItemListSyntax {
    guard var statements = body?.statements, let firstStatement = statements.first else {
      return [CodeBlockItemSyntax(leadingTrivia: .newline + indentation, item: .stmt(StmtSyntax(BreakStmtSyntax())))]
    }
    if !firstStatement.leadingTrivia.contains(where: \.isNewline) {
      statements[statements.startIndex].leadingTrivia = .newline + indentation
    }
    statements.trailingTrivia = statements.trailingTrivia.droppingTrailingWhitespace
    return statements
  }
}

/// Finds `fallthrough` and unlabeled `break` statements that would apply to a `switch` statement around the node.
private final class SwitchControlTransferFinder: SyntaxVisitor {
  var foundControlTransfer = false

  /// The number of loops around the visited node, which are what an unlabeled `break` leaves.
  private var loopDepth = 0

  override func visit(_ node: BreakStmtSyntax) -> SyntaxVisitorContinueKind {
    if node.label == nil && loopDepth == 0 {
      foundControlTransfer = true
    }
    return .skipChildren
  }

  override func visit(_ node: FallthroughStmtSyntax) -> SyntaxVisitorContinueKind {
    foundControlTransfer = true
    return .skipChildren
  }

  override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
    loopDepth += 1
    return .visitChildren
  }

  override func visitPost(_ node: ForStmtSyntax) {
    loopDepth -= 1
  }

  override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
    loopDepth += 1
    return .visitChildren
  }

  override func visitPost(_ node: WhileStmtSyntax) {
    loopDepth -= 1
  }

  override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
    loopDepth += 1
    return .visitChildren
  }

  override func visitPost(_ node: RepeatStmtSyntax) {
    loopDepth -= 1
  }

  override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
    return .skipChildren
  }
}

extension ConvertToSwitchStmt: SyntaxRefactoringCodeActionProvider {
  package static var title: String { "Convert To Switch Statement" }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> IfExprSyntax? {
    var ifExpr = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: IfExprSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    )
    // Convert the entire `if` statement if the code action is requested on one of its `else if` branches.
    while let parent = ifExpr?.parent?.as(IfExprSyntax.self) {
      ifExpr = parent
    }
    // A `switch` statement with a single `case` isn't easier to read than the `if` statement.
    guard ifExpr?.elseBody != nil else {
      return nil
    }
    return ifExpr
  }
}
