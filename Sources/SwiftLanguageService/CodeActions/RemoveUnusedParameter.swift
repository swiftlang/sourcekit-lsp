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
import SwiftSyntax

/// A code action that removes a function parameter that is not used in the
/// function body and updates call sites within the same file.
///
/// The action is offered when the cursor is on a parameter in a function
/// declaration and that parameter's name is not referenced in the function body.
///
/// **Before:**
/// ```swift
/// func greet(name: String, title: String) {
///     print("Hello, \(name)")
/// }
///
/// greet(name: "Alice", title: "Ms.")
/// ```
///
/// **After:**
/// ```swift
/// func greet(name: String) {
///     print("Hello, \(name)")
/// }
///
/// greet(name: "Alice")
/// ```
struct RemoveUnusedParameter: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    // Find the parameter the cursor is on.
    guard let paramSyntax = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: FunctionParameterSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) }
    ) else {
      return []
    }

    // Find the enclosing function declaration.
    guard let funcDecl = paramSyntax.findParentOfSelf(
      ofType: FunctionDeclSyntax.self,
      stoppingIf: { _ in false }
    ) else {
      return []
    }

    // Get the parameter's local name (the name used in the function body).
    let localName = paramSyntax.secondName?.text ?? paramSyntax.firstName.text

    // If the local name is `_`, we can't detect usage — skip.
    if localName == "_" {
      return []
    }

    // Check if the parameter is used in the function body.
    guard let body = funcDecl.body else {
      return []
    }

    let collector = ReferenceCounter(variableName: localName)
    collector.walk(body)
    if collector.count > 0 {
      return []
    }

    // The parameter is unused. Build the edit to remove it.
    let paramList = funcDecl.signature.parameterClause.parameters

    // Find the index of this parameter.
    guard let paramIndex = paramList.firstIndex(where: { $0.id == paramSyntax.id }) else {
      return []
    }

    let externalName = paramSyntax.firstName.text
    let funcName = funcDecl.name.text

    var textEdits: [TextEdit] = []

    // Remove the parameter from the declaration.
    let paramCount = paramList.count
    if paramCount == 1 {
      // Only parameter — replace the entire parameter list content with empty.
      let startPos = scope.snapshot.position(of: paramSyntax.positionAfterSkippingLeadingTrivia)
      let endPos = scope.snapshot.position(of: paramSyntax.endPositionBeforeTrailingTrivia)
      textEdits.append(TextEdit(range: startPos..<endPos, newText: ""))
    } else {
      // Multiple parameters — remove this one and its associated comma.
      let isLast = paramList.index(after: paramIndex) == paramList.endIndex

      if isLast {
        // Remove the comma from the previous parameter and this parameter.
        let prevIndex = paramList.index(before: paramIndex)
        let prevParam = paramList[prevIndex]
        let startPos = scope.snapshot.position(of: prevParam.endPositionBeforeTrailingTrivia)
        let endPos = scope.snapshot.position(of: paramSyntax.endPositionBeforeTrailingTrivia)
        textEdits.append(TextEdit(range: startPos..<endPos, newText: ""))
      } else {
        // Remove this parameter and its trailing comma.
        let nextIndex = paramList.index(after: paramIndex)
        let nextParam = paramList[nextIndex]
        let startPos = scope.snapshot.position(of: paramSyntax.positionAfterSkippingLeadingTrivia)
        let endPos = scope.snapshot.position(of: nextParam.positionAfterSkippingLeadingTrivia)
        textEdits.append(TextEdit(range: startPos..<endPos, newText: ""))
      }
    }

    // Find and update call sites within the same file.
    let callSiteCollector = CallSiteCollector(
      functionName: funcName,
      parameterExternalName: externalName,
      parameterIndex: paramList.distance(from: paramList.startIndex, to: paramIndex)
    )
    callSiteCollector.walk(scope.file)

    for callEdit in callSiteCollector.edits {
      let startPos = scope.snapshot.position(of: callEdit.start)
      let endPos = scope.snapshot.position(of: callEdit.end)
      textEdits.append(TextEdit(range: startPos..<endPos, newText: callEdit.replacement))
    }

    let displayName = externalName == "_" ? localName : externalName

    return [
      CodeAction(
        title: "Remove unused parameter '\(displayName)'",
        kind: .refactorRewrite,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: textEdits
          ]
        )
      )
    ]
  }
}

// MARK: - Helpers

private class ReferenceCounter: SyntaxVisitor {
  let variableName: String
  var count = 0

  init(variableName: String) {
    self.variableName = variableName
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == variableName && node.argumentNames == nil {
      count += 1
    }
    return .visitChildren
  }
}

private struct CallSiteEdit {
  let start: AbsolutePosition
  let end: AbsolutePosition
  let replacement: String
}

private class CallSiteCollector: SyntaxVisitor {
  let functionName: String
  let parameterExternalName: String
  let parameterIndex: Int
  var edits: [CallSiteEdit] = []

  init(functionName: String, parameterExternalName: String, parameterIndex: Int) {
    self.functionName = functionName
    self.parameterExternalName = parameterExternalName
    self.parameterIndex = parameterIndex
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    // Check if this call matches the function name.
    guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
      callee.baseName.text == functionName
    else {
      return .visitChildren
    }

    let args = node.arguments
    let argCount = args.count

    // Try to find the argument by matching the external name at the expected index.
    guard parameterIndex < argCount else {
      return .visitChildren
    }

    let argIndex = args.index(args.startIndex, offsetBy: parameterIndex)
    let arg = args[argIndex]

    // Verify the label matches (or both are unlabeled).
    let argLabel = arg.label?.text ?? "_"
    if argLabel != parameterExternalName {
      return .visitChildren
    }

    if argCount == 1 {
      // Only argument — remove it entirely.
      edits.append(
        CallSiteEdit(
          start: arg.positionAfterSkippingLeadingTrivia,
          end: arg.endPositionBeforeTrailingTrivia,
          replacement: ""
        )
      )
    } else {
      let isLast = args.index(after: argIndex) == args.endIndex

      if isLast {
        // Remove comma from previous argument and this argument.
        let prevIndex = args.index(before: argIndex)
        let prevArg = args[prevIndex]
        edits.append(
          CallSiteEdit(
            start: prevArg.endPositionBeforeTrailingTrivia,
            end: arg.endPositionBeforeTrailingTrivia,
            replacement: ""
          )
        )
      } else {
        // Remove this argument and its trailing comma/space.
        let nextIndex = args.index(after: argIndex)
        let nextArg = args[nextIndex]
        edits.append(
          CallSiteEdit(
            start: arg.positionAfterSkippingLeadingTrivia,
            end: nextArg.positionAfterSkippingLeadingTrivia,
            replacement: ""
          )
        )
      }
    }

    return .visitChildren
  }
}

