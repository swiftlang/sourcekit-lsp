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

extension IntegerLiteralExprSyntax.Radix {
  static let allCases: [Self] = [.binary, .octal, .decimal, .hex]
}

/// Syntactic code action provider to convert integer literals between
/// different bases.
struct ConvertIntegerLiteral: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard
      let token = scope.innermostNodeContainingRange,
      let integerExpr = token.parent?.as(IntegerLiteralExprSyntax.self),
      let integerValue = Int(
        integerExpr.split().value.filter { $0 != "_" },
        radix: integerExpr.radix.size
      )
    else {
      return []
    }

    var actions = [CodeAction]()
    let currentRadix = integerExpr.radix
    for radix in IntegerLiteralExprSyntax.Radix.allCases {
      guard radix != currentRadix else {
        continue
      }

      //TODO: Add this to swift-syntax?
      let prefix: String
      switch radix {
      case .binary:
        prefix = "0b"
      case .octal:
        prefix = "0o"
      case .hex:
        prefix = "0x"
      case .decimal:
        prefix = ""
      }

      let convertedValue: ExprSyntax =
        "\(raw: prefix)\(raw: String(integerValue, radix: radix.size))"
      let edit = TextEdit(
        range: scope.snapshot.range(of: integerExpr),
        newText: convertedValue.description
      )
      actions.append(
        CodeAction(
          title: "Convert \(integerExpr) to \(convertedValue)",
          kind: .refactorInline,
          edit: WorkspaceEdit(changes: [scope.snapshot.uri: [edit]])
        )
      )
    }

    return actions
  }
}
