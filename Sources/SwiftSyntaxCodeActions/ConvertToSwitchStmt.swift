//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project.
//
// Copyright 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception.
//
// See https://swift.org/LICENSE.txt for license information.
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors.
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SourceKitLSP
import SwiftBasicFormat
import SwiftExtensions
import SwiftSyntax
import SwiftSyntaxBuilder

/// Syntactic code action provider to convert an `if` / `else if` chain whose
/// conditions all test the same value into a `switch` statement.
///
/// ## Before
/// ```swift
/// if status == .loading {
///   showSpinner()
/// } else if status == .done {
///   showContent()
/// } else {
///   showError()
/// }
/// ```
///
/// ## After
/// ```swift
/// switch status {
/// case .loading:
///   showSpinner()
/// case .done:
///   showContent()
/// default:
///   showError()
/// }
/// ```
@_spi(Testing) public struct ConvertToSwitchStmt: SyntaxCodeActionProvider {
  package static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let chain = findConvertibleIfChain(in: scope), let converted = convert(chain) else {
      return []
    }

    let edit = TextEdit(
      range: scope.snapshot.positionRange(
        of: chain.root.positionAfterSkippingLeadingTrivia..<chain.root.endPosition
      ),
      newText: converted
    )

    return [
      CodeAction(
        title: "Convert to switch statement",
        kind: .refactorInline,
        edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
      )
    ]
  }

  /// A linked list describing the `else if` chain: the root `if` and every
  /// `else if` nested in it, in source order.
  struct SwitchChain {
    let root: IfExprSyntax
    /// `(ifStmt, elseIfParent)` pairs in source order.
    let branches: [(ifStmt: IfExprSyntax, elseIf: CodeBlockSyntax?)]

    init(root: IfExprSyntax) {
      self.root = root
      var branches: [(IfExprSyntax, CodeBlockSyntax?)] = [(root, nil)]
      var current = root
      while let elseBody = current.elseBody, case .ifExpr(let elseIf) = elseBody {
        branches.append((elseIf, elseBody.as(CodeBlockSyntax.self) ?? CodeBlockSyntax(statements: [])))
        current = elseIf
      }
      self.branches = branches.map { (ifStmt: $0.0, elseIf: $0.1) }
    }

    /// The final `else` block, if the chain is terminated by one.
    var elseBlock: CodeBlockSyntax? {
      guard let elseBody = branches.last?.ifStmt.elseBody, case .codeBlock(let block) = elseBody else {
        return nil
      }
      return block
    }
  }

  /// Walks up from the cursor to find an if chain convertible to a switch.
  static func findConvertibleIfChain(in scope: SyntaxCodeActionScope) -> SwitchChain? {
    guard let innermost = scope.innermostNodeContainingRange else {
      return nil
    }

    var node: Syntax? = Syntax(innermost)
    while let current = node {
      if let ifStmt = current.as(IfExprSyntax.self) {
        // If this if is an `else if` of an outer if, climb to the chain's
        // root so the whole chain gets converted.
        var root = ifStmt
        while let parent = root.parent, let outerIf = parent.as(IfExprSyntax.self),
          outerIf.elseBody != nil, outerIf.elseBody?.is(IfExprSyntax.self) == true
        {
          root = outerIf
        }
        let chain = SwitchChain(root: root)
        if isConvertible(chain) {
          return chain
        }
        // Not convertible here; don't walk further up from an if.
        return nil
      }
      node = current.parent
    }
    return nil
  }

  /// Whether every branch's first condition tests the same control value and
  /// is convertible to a `case` pattern.
  static func isConvertible(_ chain: SwitchChain) -> Bool {
    guard chain.branches.count > 1 || chain.elseBlock != nil else {
      return false
    }
    var controlVariable: String? = nil
    for branch in chain.branches {
      guard let branchInfo = branchPattern(branch.ifStmt, expectedControl: controlVariable) else {
        return false
      }
      if controlVariable == nil {
        controlVariable = branchInfo.control
      }
    }
    return true
  }

  struct BranchPattern {
    let control: String
    let pattern: String
  }

  /// Extracts the `case` pattern for the first condition of `ifStmt`,
  /// enforcing that the control value is always `expectedControl`.
  static func branchPattern(_ ifStmt: IfExprSyntax, expectedControl: String?) -> BranchPattern? {
    guard let condition = ifStmt.conditions.first, ifStmt.conditions.count == 1 else {
      // Additional comma-separated conditions can't be represented in a
      // single `case`.
      return nil
    }

    if let matching = condition.condition.as(MatchingPatternConditionSyntax.self),
      let expr = matching.pattern.as(ExpressionPatternSyntax.self)
    {
      // `case <pattern> = <control>`: the control value must be the
      // expression on the right of `=`.
      let control = matching.initializer.value
      guard let name = soleVariableName(in: control), name == expectedControl || expectedControl == nil
      else {
        return nil
      }
      return BranchPattern(control: name, pattern: expr.expression.trimmedDescription)
    }

    if let sequence = condition.condition.as(SequenceExprSyntax.self),
      let elementList = sequence.elements.count == 3 ? Array(sequence.elements) : nil,
      let op = elementList[1].as(BinaryOperatorExprSyntax.self),
      op.operator.text == "==" || op.operator.text == "~="
    {
      // `<control> == <pattern>` (or `~=`): the side that is not a
      // comparison operand must reference the control variable.
      let lhs = elementList[0]
      let rhs = elementList[2]
      if let name = soleVariableName(in: ExprSyntax(lhs)), name == expectedControl || expectedControl == nil {
        return BranchPattern(control: name, pattern: rhs.trimmedDescription)
      }
      if let name = soleVariableName(in: ExprSyntax(rhs)), name == expectedControl || expectedControl == nil {
        return BranchPattern(control: name, pattern: lhs.trimmedDescription)
      }
      return nil
    }

    return nil
  }

  /// The identifier if `expr` consists solely of a reference to a variable
  /// (optionally wrapped in parentheses), `nil` otherwise.
  static func soleVariableName(in expr: ExprSyntax) -> String? {
    var e = expr
    if let tuple = e.as(TupleExprSyntax.self), tuple.elements.count == 1 {
      e = tuple.elements.first!.expression
    }
    guard let declRef = e.as(DeclReferenceExprSyntax.self) else {
      return nil
    }
    let name = declRef.baseName.text
    // Skip compiler-synthesized identifiers like `self`.
    guard name != "self" else {
      return nil
    }
    return name
  }

  /// Builds the replacement `switch` statement.
  static func convert(_ chain: SwitchChain) -> String? {
    var controlVariable: String? = nil
    var patterns: [String] = []
    for branch in chain.branches {
      guard let branchInfo = branchPattern(branch.ifStmt, expectedControl: controlVariable) else {
        return nil
      }
      controlVariable = branchInfo.control
      patterns.append(branchInfo.pattern)
    }
    guard let control = controlVariable else {
      return nil
    }

    let indentUnit = "  "

    var result = "switch \(control) {\n"
    for (index, branch) in chain.branches.enumerated() {
      result += "\(indentUnit)case \(patterns[index]):\n"
      result += bodyText(of: branch.ifStmt.body, indentUnit: indentUnit)
    }
    if let elseBlock = chain.elseBlock {
      result += "\(indentUnit)default:\n"
      result += bodyText(of: elseBlock, indentUnit: indentUnit)
    } else {
      result += "\(indentUnit)default:\n\(indentUnit)\(indentUnit)break\n"
    }
    result += "}"
    return result
  }

  /// The body of a branch, with one level of block indentation removed.
  static func bodyText(of block: CodeBlockSyntax, indentUnit: String) -> String {
    let statements = block.statements
    if statements.isEmpty {
      return "\(indentUnit)\(indentUnit)break\n"
    }
    var text = ""
    for statement in statements {
      var description = statement.trimmedDescription
      // De-indent the block's own indentation.
      let lines = description.split(separator: "\n", omittingEmptySubsequences: false)
      description = lines.map { line in
        if line.hasPrefix(indentUnit) {
          return String(line.dropFirst(indentUnit.count))
        }
        return String(line)
      }.joined(separator: "\n")
      text += "\(indentUnit)\(indentUnit)\(description)\n"
    }
    return text
  }

  /// The leading whitespace of the line containing the root `if`, i.e. the
}
