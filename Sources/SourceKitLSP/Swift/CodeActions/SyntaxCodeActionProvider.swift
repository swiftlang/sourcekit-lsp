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

import LSPLogging
import LanguageServerProtocol
import SwiftRefactor
import SwiftSyntax

/// Describes types that provide one or more code actions based on purely
/// syntactic information.
protocol SyntaxCodeActionProvider {
  /// Produce code actions within the given scope. Each code action
  /// corresponds to one syntactic transformation that can be performed, such
  /// as adding or removing separators from an integer literal.
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction]
}

/// Defines the scope in which a syntactic code action occurs.
struct SyntaxCodeActionScope {
  /// The snapshot of the document on which the code actions will be evaluated.
  var snapshot: DocumentSnapshot

  /// The actual code action request, which can specify additional parameters
  /// to guide the code actions.
  var request: CodeActionRequest

  /// The source file in which the syntactic code action will operate.
  var file: SourceFileSyntax

  /// The UTF-8 byte range in the source file in which code actions should be
  /// considered, i.e., where the cursor or selection is.
  var range: Range<AbsolutePosition>

  init(
    snapshot: DocumentSnapshot,
    syntaxTree tree: SourceFileSyntax,
    request: CodeActionRequest
  ) throws {
    self.snapshot = snapshot
    self.request = request
    self.file = tree

    let start = snapshot.absolutePosition(of: request.range.lowerBound)
    let end = snapshot.absolutePosition(of: request.range.upperBound)
    let left = file.token(at: start)
    let right = file.token(at: end)
    let leftOff = left?.position ?? AbsolutePosition(utf8Offset: 0)
    let rightOff = right?.endPosition ?? leftOff
    self.range = leftOff..<rightOff
  }

  /// The first token in the
  var firstToken: TokenSyntax? {
    file.token(at: range.lowerBound)
  }
}
