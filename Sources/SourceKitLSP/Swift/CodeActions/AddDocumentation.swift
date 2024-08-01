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

import SwiftBasicFormat
import SwiftParser
import SwiftRefactor
import SwiftSyntax

/// Insert a documentation template associated with a function or macro.
///
/// ## Before
///
/// ```swift
/// static func refactor(syntax: DeclSyntax, in context: Void) -> DeclSyntax? {}
/// ```
///
/// ## After
///
/// ```swift
/// ///
/// /// - Parameters:
/// ///   - syntax:
/// ///   - context:
/// /// - Returns:
/// static func refactor(syntax: DeclSyntax, in context: Void) -> DeclSyntax? {}
/// ```
package struct AddDocumentation: EditRefactoringProvider {
  package static func textRefactor(syntax: DeclSyntax, in context: Void) -> [SourceEdit] {
    let hasDocumentation = syntax.leadingTrivia.contains { trivia in
      switch trivia {
      case .blockComment, .docBlockComment, .lineComment, .docLineComment:
        return true
      default:
        return false
      }
    }

    // We consider nodes at the start of the source file at being on a new line
    let isOnNewLine =
      syntax.leadingTrivia.contains(where: \.isNewline) || syntax.previousToken(viewMode: .sourceAccurate) == nil

    guard !hasDocumentation && isOnNewLine else {
      return []
    }

    let newlineAndIndentation = [.newlines(1)] + (syntax.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? [])
    var content: [TriviaPiece] = []
    content.append(.docLineComment("/// A description"))

    if let parameters = syntax.parameters?.parameters {
      if let onlyParam = parameters.only {
        let paramToken = onlyParam.secondName?.text ?? onlyParam.firstName.text
        content += newlineAndIndentation
        content.append(.docLineComment("/// - Parameter \(paramToken):"))
      } else {
        content += newlineAndIndentation
        content.append(.docLineComment("/// - Parameters:"))
        content += parameters.flatMap({ param in
          newlineAndIndentation + [
            .docLineComment("///   - \(param.secondName?.text ?? param.firstName.text):")
          ]
        })
        content += newlineAndIndentation
        content.append(.docLineComment("///"))
      }
    }

    if syntax.throwsKeyword != nil {
      content += newlineAndIndentation
      content.append(.docLineComment("/// - Throws:"))
    }

    if syntax.returnType != nil {
      content += newlineAndIndentation
      content.append(.docLineComment("/// - Returns:"))
    }
    content += newlineAndIndentation

    let insertPos = syntax.positionAfterSkippingLeadingTrivia
    return [
      SourceEdit(
        range: insertPos..<insertPos,
        replacement: Trivia(pieces: content).description
      )
    ]
  }
}

extension AddDocumentation: SyntaxRefactoringCodeActionProvider {
  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Input? {
    return scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: DeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockItemSyntax.self) || $0.is(MemberBlockItemSyntax.self) || $0.is(ExprSyntax.self) }
    )
  }

  static var title: String { "Add documentation" }
}

extension DeclSyntax {
  fileprivate var parameters: FunctionParameterClauseSyntax? {
    switch self.as(DeclSyntaxEnum.self) {
    case .functionDecl(let functionDecl):
      return functionDecl.signature.parameterClause
    case .subscriptDecl(let subscriptDecl):
      return subscriptDecl.parameterClause
    case .initializerDecl(let initializer):
      return initializer.signature.parameterClause
    case .macroDecl(let macro):
      return macro.signature.parameterClause
    default:
      return nil
    }
  }

  fileprivate var throwsKeyword: TokenSyntax? {
    switch self.as(DeclSyntaxEnum.self) {
    case .functionDecl(let functionDecl):
      return functionDecl.signature.effectSpecifiers?.throwsClause?.throwsSpecifier
    case .initializerDecl(let initializer):
      return initializer.signature.effectSpecifiers?.throwsClause?.throwsSpecifier
    default:
      return nil
    }
  }

  fileprivate var returnType: TypeSyntax? {
    switch self.as(DeclSyntaxEnum.self) {
    case .functionDecl(let functionDecl):
      return functionDecl.signature.returnClause?.type
    case .subscriptDecl(let subscriptDecl):
      return subscriptDecl.returnClause.type
    case .initializerDecl(let initializer):
      return initializer.signature.returnClause?.type
    case .macroDecl(let macro):
      return macro.signature.returnClause?.type
    default:
      return nil
    }
  }
}
