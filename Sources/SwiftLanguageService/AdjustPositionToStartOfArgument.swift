//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKLogging
import SourceKitLSP
import SwiftSyntax

private class StartOfArgumentFinder: SyntaxAnyVisitor {
  let requestedPosition: AbsolutePosition
  var resolvedPosition: AbsolutePosition?

  init(position: AbsolutePosition) {
    self.requestedPosition = position
    super.init(viewMode: .sourceAccurate)
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if node.range.contains(requestedPosition) {
      return .visitChildren
    }
    return .skipChildren
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    return visit(arguments: node.arguments)
  }

  override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
    return visit(arguments: node.arguments)
  }

  private func visit(arguments: LabeledExprListSyntax) -> SyntaxVisitorContinueKind {
    guard (arguments.position...arguments.endPosition).contains(requestedPosition) else {
      return .skipChildren
    }

    guard !arguments.isEmpty else {
      self.resolvedPosition = arguments.position
      return .skipChildren
    }

    for argument in arguments {
      if (argument.position...argument.endPosition).contains(requestedPosition) {
        if let trailingComma = argument.trailingComma,
          requestedPosition >= trailingComma.endPositionBeforeTrailingTrivia
        {
          self.resolvedPosition = trailingComma.endPositionBeforeTrailingTrivia
        } else {
          self.resolvedPosition = argument.expression.positionAfterSkippingLeadingTrivia
        }
        return .visitChildren
      }
    }

    return .skipChildren
  }
}

extension SwiftLanguageService {
  func adjustPositionToStartOfArgument(
    _ position: Position,
    in snapshot: DocumentSnapshot
  ) async -> Position {
    let tree = await self.syntaxTreeManager.syntaxTree(for: snapshot)
    let visitor = StartOfArgumentFinder(position: snapshot.absolutePosition(of: position))
    visitor.walk(tree)
    if let resolvedPosition = visitor.resolvedPosition {
      return snapshot.position(of: resolvedPosition)
    }
    return position
  }
}
