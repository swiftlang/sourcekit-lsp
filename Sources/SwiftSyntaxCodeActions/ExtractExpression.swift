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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftBasicFormat
import SwiftSyntax

/// A code action that hoists the selected expression into a new `let` declaration in front of the
/// statement that contains it.
///
/// ## Before
/// ```swift
/// print(base * height / 2)
/// ```
///
/// ## After
/// ```swift
/// let extractedExpr = base * height / 2
/// print(extractedExpr)
/// ```
///
/// This supersedes sourcekitd's `source.refactoring.kind.extract.expr` refactoring. Since no type
/// information is available, the new declaration doesn't spell out the expression's type and the
/// action isn't offered in positions where hoisting the expression would change the meaning of the
/// program.
struct ExtractExpression: SyntaxCodeActionProvider {
  /// The name of the extracted declaration, matching the name that sourcekitd's refactoring used.
  private static let baseName = "extractedExpr"

  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let expression = selectedExpression(in: scope),
      isExtractable(expression),
      let insertionItem = insertionItem(for: expression),
      // Hoisting an expression that already is the entire statement only gives it a name.
      expression.trimmedRange != insertionItem.trimmedRange
    else {
      return []
    }

    let name = extractedName(in: scope.file)
    let indentation = insertionItem.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []
    let insertionPosition = insertionItem.positionAfterSkippingLeadingTrivia

    let edits = [
      SourceEdit(
        range: insertionPosition..<insertionPosition,
        replacement: "let \(name) = \(expression.trimmedDescription)\n\(indentation)"
      ),
      SourceEdit(range: expression.trimmedRange, replacement: name),
    ]

    guard let edit = edits.asWorkspaceEdit(snapshot: scope.snapshot) else {
      return []
    }
    return [CodeAction(title: "Extract expression", kind: .refactorExtract, edit: edit)]
  }

  /// The expression that the selection covers, ignoring whitespace at the selection's edges.
  ///
  /// Like sourcekitd's refactoring, which was a range refactoring, extracting an expression requires
  /// the user to select it: a cursor position on its own doesn't identify one of the expressions
  /// that contain it.
  private static func selectedExpression(in scope: SyntaxCodeActionScope) -> ExprSyntax? {
    let lowerBound = scope.snapshot.absolutePosition(of: scope.requestedRange.lowerBound)
    let upperBound = scope.snapshot.absolutePosition(of: scope.requestedRange.upperBound)
    guard lowerBound < upperBound else {
      return nil
    }

    // The first token that the selection contains in full.
    var firstToken = scope.file.token(at: lowerBound)
    while let token = firstToken, token.positionAfterSkippingLeadingTrivia < lowerBound {
      firstToken = token.nextToken(viewMode: .sourceAccurate)
    }
    guard let firstToken, firstToken.endPositionBeforeTrailingTrivia <= upperBound else {
      return nil
    }

    // The last token that the selection contains in full.
    var lastToken = firstToken
    while let token = lastToken.nextToken(viewMode: .sourceAccurate),
      token.endPositionBeforeTrailingTrivia <= upperBound
    {
      lastToken = token
    }

    // An expression is selected if the selection starts at its first token and ends at its last one.
    var node = Syntax(firstToken)
    while node.firstToken(viewMode: .sourceAccurate)?.id == firstToken.id {
      if node.lastToken(viewMode: .sourceAccurate)?.id == lastToken.id,
        let expression = node.as(ExprSyntax.self)
      {
        return expression
      }
      guard let parent = node.parent else {
        break
      }
      node = parent
    }
    return nil
  }

  /// Whether `expression` can be hoisted into a declaration of its own.
  private static func isExtractable(_ expression: ExprSyntax) -> Bool {
    // Don't offer the action for code that doesn't parse: the extracted text would be incomplete.
    if expression.hasError {
      return false
    }

    switch expression.as(ExprSyntaxEnum.self) {
    case .integerLiteralExpr, .floatLiteralExpr, .booleanLiteralExpr, .nilLiteralExpr,
      .stringLiteralExpr, .simpleStringLiteralExpr, .regexLiteralExpr, .arrayExpr, .dictionaryExpr:
      // Extracting a single literal provides little value and, without a type annotation on the new
      // declaration, can leave its type ambiguous, eg. for `[]`. sourcekitd didn't offer it either.
      return false
    case .closureExpr:
      // Extracting closures was never offered by sourcekitd's refactoring.
      return false
    case .inOutExpr:
      // `&x` is only valid as the argument of an `inout` parameter.
      return false
    default:
      break
    }

    if isAssignmentDestination(expression) {
      // Assigning to the extracted declaration isn't possible: it is a `let` and it is a copy of the
      // original value in the first place.
      return false
    }

    // Hoisting only a part of a postfix expression chain, or the operand of an effect marker, leaves
    // the remaining expression with a value it can't be applied to: the extracted declaration is
    // immutable and no longer covered by the `try`/`await`/`unsafe` that preceded it.
    switch expression.parent?.as(SyntaxEnum.self) {
    case .memberAccessExpr(let memberAccess):
      return memberAccess.base?.id != expression.id
    case .functionCallExpr(let call):
      return call.calledExpression.id != expression.id
    case .subscriptCallExpr(let subscriptCall):
      return subscriptCall.calledExpression.id != expression.id
    case .forceUnwrapExpr, .optionalChainingExpr, .postfixOperatorExpr, .inOutExpr, .tryExpr,
      .awaitExpr, .unsafeExpr:
      return false
    default:
      return true
    }
  }

  /// Whether `expression` is assigned to, eg. `x` in `x = 1` or in `x += 1`.
  private static func isAssignmentDestination(_ expression: ExprSyntax) -> Bool {
    if let infixOperator = expression.parent?.as(InfixOperatorExprSyntax.self) {
      return infixOperator.leftOperand.id == expression.id && isAssignment(infixOperator.operator)
    }
    // Code actions operate on unfolded sequence expressions, in which the operator that follows the
    // expression is a sibling of it.
    guard let elements = expression.parent?.as(ExprListSyntax.self),
      let index = elements.index(of: expression)
    else {
      return false
    }
    let operatorIndex = elements.index(after: index)
    guard operatorIndex != elements.endIndex else {
      return false
    }
    return isAssignment(elements[operatorIndex])
  }

  /// Whether `expression` is the `=` of an assignment or a compound assignment operator like `+=`.
  private static func isAssignment(_ expression: ExprSyntax) -> Bool {
    if expression.is(AssignmentExprSyntax.self) {
      return true
    }
    guard let binaryOperator = expression.as(BinaryOperatorExprSyntax.self) else {
      return false
    }
    let text = binaryOperator.operator.text
    return text.hasSuffix("=") && !["==", "!=", "===", "!==", "<=", ">=", "~="].contains(text)
  }

  /// The code block item in front of which the new declaration is inserted, or `nil` if the
  /// expression can't be hoisted to a statement.
  private static func insertionItem(for expression: ExprSyntax) -> CodeBlockItemSyntax? {
    var node = Syntax(expression)
    while let parent = node.parent {
      if let item = parent.as(CodeBlockItemSyntax.self) {
        guard let statements = item.parent?.as(CodeBlockItemListSyntax.self),
          !isImplicitResult(statements)
        else {
          return nil
        }
        return item
      }
      guard canHoist(node, through: parent) else {
        return nil
      }
      node = parent
    }
    return nil
  }

  /// Whether a declaration for `node`'s expression may be moved out of `parent`, which is the next
  /// node on the way from the expression to the statement that contains it.
  private static func canHoist(_ node: Syntax, through parent: Syntax) -> Bool {
    switch parent.as(SyntaxEnum.self) {
    case .attribute, .ifConfigClause, .macroExpansionExpr, .macroExpansionDecl:
      // These expressions are evaluated at compile time or are input to a macro, so they can't refer
      // to a local declaration.
      return false
    case .functionParameter, .closureParameter, .enumCaseParameter, .enumCaseElement,
      .memberBlockItem, .closureCapture:
      // The expression belongs to a nested declaration or to a capture list, neither of which can
      // refer to a declaration that is introduced in front of the enclosing statement.
      return false
    case .whileStmt, .repeatStmt:
      // The condition of these statements is evaluated once per iteration, so hoisting it in front
      // of the loop would change how often it is evaluated.
      return false
    case .switchCaseItem, .catchItem:
      // A `where` clause can refer to the variables that its pattern binds.
      return false
    case .forStmt(let forStmt):
      // Same as above: the `where` clause is evaluated once per iteration, while the sequence that
      // is iterated over is evaluated once.
      return forStmt.whereClause?.id != node.id
    case .conditionElementList(let conditions):
      // A condition may refer to the variables that an earlier condition binds.
      return conditions.prefix(while: { $0.id != node.id }).allSatisfy { condition in
        if case .expression = condition.condition {
          return true
        }
        return false
      }
    default:
      return true
    }
  }

  /// Whether `statements` is the body of a declaration or expression that uses its single expression
  /// as the result value, in which case inserting a declaration in front of that expression would
  /// change what the body evaluates to.
  private static func isImplicitResult(_ statements: CodeBlockItemListSyntax) -> Bool {
    guard statements.count == 1, let item = statements.first, case .expr = item.item else {
      return false
    }

    switch statements.parent?.as(SyntaxEnum.self) {
    case .closureExpr(let closure):
      // A multi-statement closure needs an explicit `return` unless it returns `Void`.
      return closure.signature?.returnClause?.type.isVoid != true
    case .accessorBlock:
      // The shorthand getter of a computed property or subscript.
      return true
    case .switchCase(let switchCase):
      // A case of a `switch` expression.
      guard let switchExpr = switchCase.parent?.parent?.as(ExprSyntax.self) else {
        return true
      }
      return !isStatement(switchExpr)
    case .codeBlock(let codeBlock):
      switch codeBlock.parent?.as(SyntaxEnum.self) {
      case .functionDecl(let functionDecl):
        return functionDecl.signature.returnClause?.type.isVoid == false
      case .accessorDecl(let accessorDecl):
        return accessorDecl.accessorSpecifier.tokenKind == .keyword(.get)
      default:
        // A branch of an `if` or `do` expression evaluates to its single expression, unless the
        // `if` or `do` is used as a statement. Anything else, like the body of a `for` statement, an
        // initializer or a deinitializer, has no implicit result.
        if let expression = codeBlock.parent?.as(ExprSyntax.self) {
          return !isStatement(expression)
        }
        return false
      }
    default:
      return false
    }
  }

  /// Whether `expression` is used as a statement, ie. whether its value is discarded.
  private static func isStatement(_ expression: ExprSyntax) -> Bool {
    var node = Syntax(expression)
    // `else if` nests the inner `if` inside the `else` body of the outer one.
    while let parent = node.parent, parent.is(IfExprSyntax.self) {
      node = parent
    }
    if let parent = node.parent, parent.is(ExpressionStmtSyntax.self) {
      node = parent
    }
    return node.parent?.is(CodeBlockItemSyntax.self) ?? false
  }

  /// A name for the extracted declaration that doesn't collide with an existing declaration.
  ///
  /// This is deliberately conservative: without semantic information we don't know which
  /// declarations are visible at the insertion point, so every identifier that occurs in the file is
  /// avoided. Like sourcekitd's refactoring, the name is `extractedExpr`, with the lowest unused
  /// number appended if that name is taken.
  private static func extractedName(in file: SourceFileSyntax) -> String {
    var identifiers: Set<String> = []
    for token in file.tokens(viewMode: .sourceAccurate) {
      if case .identifier(let identifier) = token.tokenKind {
        identifiers.insert(identifier)
      }
    }

    guard identifiers.contains(baseName) else {
      return baseName
    }
    var suffix = 1
    while identifiers.contains("\(baseName)\(suffix)") {
      suffix += 1
    }
    return "\(baseName)\(suffix)"
  }
}
