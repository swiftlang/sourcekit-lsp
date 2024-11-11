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

#if compiler(>=6.0)
public import SwiftBasicFormat
public import SwiftSyntax
#else
import SwiftBasicFormat
import SwiftSyntax
#endif

/// A specialization of `BasicFormat` for closure literals in a code completion
/// context.
///
/// This is more conservative about newline insertion: unless the closure has
/// multiple statements in its body it will not be reformatted to multiple
/// lines.
@_spi(Testing)
public class ClosureCompletionFormat: BasicFormat {
  @_spi(Testing)
  public override func requiresNewline(
    between first: TokenSyntax?,
    and second: TokenSyntax?
  ) -> Bool {
    if let first, isEndOfSmallClosureSignature(first) {
      return false
    } else if let first, isSmallClosureDelimiter(first, kind: \.leftBrace) {
      return false
    } else if let second, isSmallClosureDelimiter(second, kind: \.rightBrace) {
      return false
    } else {
      return super.requiresNewline(between: first, and: second)
    }
  }

  /// Returns `true` if `token` is an opening or closing brace (according to
  /// `kind`) of a closure, and that closure has no more than one statement in
  /// its body.
  private func isSmallClosureDelimiter(
    _ token: TokenSyntax,
    kind: KeyPath<ClosureExprSyntax, TokenSyntax>
  ) -> Bool {
    guard token.keyPathInParent == kind,
      let closure = token.parent?.as(ClosureExprSyntax.self)
    else {
      return false
    }

    return closure.statements.count <= 1
  }

  /// Returns `true` if `token` is the last token in the signature of a closure,
  /// and that closure has no more than one statement in its body.
  private func isEndOfSmallClosureSignature(_ token: TokenSyntax) -> Bool {
    guard
      token.keyPathInParent == \ClosureSignatureSyntax.inKeyword,
      let closure = token.ancestorOrSelf(mapping: { $0.as(ClosureExprSyntax.self) })
    else {
      return false
    }

    return closure.statements.count <= 1
  }
}
