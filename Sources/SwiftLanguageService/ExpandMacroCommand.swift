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

@_spi(SourceKitLSP) package import LanguageServerProtocol
import SourceKitD

package struct ExpandMacroCommand: SwiftCommand {
  package static let identifier: String = "expand.macro.command"

  /// The name of this refactoring action.
  package var title = "Expand Macro"

  /// The sourcekitd identifier of the refactoring action.
  package var actionString = "source.refactoring.kind.expand.macro"

  /// The range to expand.
  @CustomCodable<PositionRange>
  package var positionRange: Range<Position>

  /// The text document related to the refactoring action.
  package var textDocument: TextDocumentIdentifier

  package init(positionRange: Range<Position>, textDocument: TextDocumentIdentifier) {
    self.positionRange = positionRange
    self.textDocument = textDocument
  }
}
