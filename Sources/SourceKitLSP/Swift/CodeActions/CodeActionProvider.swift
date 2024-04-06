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

public protocol CodeActionProvider {
  static var kind: CodeActionKind { get }
  static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction]
}

public struct CodeActionScope {
  public var snapshot: DocumentSnapshot
  public var parameters: CodeActionRequest
  public var file: SourceFileSyntax
  public var range: ByteSourceRange

  init(snapshot: DocumentSnapshot, syntaxTree tree: SourceFileSyntax, parameters: CodeActionRequest) throws {
    self.snapshot = snapshot
    self.parameters = parameters
    self.file = tree

    let start = self.snapshot.utf8Offset(of: self.parameters.range.lowerBound) ?? 0
    let end = self.snapshot.utf8Offset(of: self.parameters.range.upperBound) ?? start
    let left = self.file.token(at: start)
    let right = self.file.token(at: end)

    let leftOff = left?.positionAfterSkippingLeadingTrivia.utf8Offset ?? 0
    let rightOff = right?.endPositionBeforeTrailingTrivia.utf8Offset ?? leftOff
    assert(leftOff <= rightOff)
    self.range = ByteSourceRange(offset: leftOff, length: rightOff - leftOff)
  }

  public func starts(with tokenKind: TokenKind) -> TokenSyntax? {
    guard
      let token = self.file.token(at: self.range.offset),
      token.tokenKind == tokenKind
    else {
      return nil
    }
    return token
  }
}

extension SyntaxProtocol {
  func token(at utf8Offset: Int) -> TokenSyntax? {
    return token(at: AbsolutePosition(utf8Offset: utf8Offset))
  }
}

extension ByteSourceRange {
  fileprivate func contains(_ other: Int) -> Bool {
    return self.offset <= other && other <= self.endOffset
  }
}

extension SyntaxProtocol {
  var textRange: ByteSourceRange {
    return ByteSourceRange(
      offset: self.positionAfterSkippingLeadingTrivia.utf8Offset,
      length: self.trimmedLength.utf8Length
    )
  }
}
