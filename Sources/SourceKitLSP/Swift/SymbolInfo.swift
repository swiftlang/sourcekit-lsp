//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SwiftSyntax

fileprivate class StartOfIdentifierFinder: SyntaxAnyVisitor {
  let requestedPosition: AbsolutePosition
  var resolvedPosition: AbsolutePosition?

  init(position: AbsolutePosition) {
    self.requestedPosition = position
    super.init(viewMode: .sourceAccurate)
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if (node.position...node.endPosition).contains(requestedPosition) {
      return .visitChildren
    } else {
      return .skipChildren
    }
  }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    if token.tokenKind.isPunctuation || token.tokenKind == .endOfFile {
      return .skipChildren
    }
    if (token.positionAfterSkippingLeadingTrivia...token.endPositionBeforeTrailingTrivia).contains(requestedPosition) {
      self.resolvedPosition = token.positionAfterSkippingLeadingTrivia
    }
    return .skipChildren
  }
}

extension SwiftLanguageServer {
  /// VS Code considers the position after an identifier as part of an identifier. Ie. if you have `let foo| = 1`, then
  /// it considers the cursor to be positioned at the identifier. This scenario is hit, when selecting an identifier by
  /// double-clicking it and then eg. performing jump-to-definition. In that case VS Code will send the position after
  /// the identifier.
  /// `sourcekitd`, on the other hand, does not consider the position after the identifier as part of the identifier.
  /// To bridge the gap here, normalize any positions inside, or directly after, an identifier to the identifier's
  /// start.
  private func adjustPositionToStartOfIdentifier(
    _ position: Position,
    in snapshot: DocumentSnapshot
  ) async -> Position {
    let tree = await self.syntaxTreeManager.syntaxTree(for: snapshot)
    guard let swiftSyntaxPosition = snapshot.position(of: position) else {
      return position
    }
    let visitor = StartOfIdentifierFinder(position: swiftSyntaxPosition)
    visitor.walk(tree)
    if let resolvedPosition = visitor.resolvedPosition {
      return snapshot.position(of: resolvedPosition) ?? position
    } else {
      return position
    }
  }

  public func symbolInfo(_ req: SymbolInfoRequest) async throws -> [SymbolDetails] {
    let uri = req.textDocument.uri
    let snapshot = try documentManager.latestSnapshot(uri)
    let position = await self.adjustPositionToStartOfIdentifier(req.position, in: snapshot)
    guard let cursorInfo = try await cursorInfo(uri, position..<position) else {
      return []
    }
    return [cursorInfo.symbolInfo]
  }
}
