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
import SourceKitD

/// A protocol to be utilised by all commands that are served by sourcekitd refactorings.
protocol RefactorCommand: SwiftCommand {
  /// The response type of the refactor command
  associatedtype Response: RefactoringResponse

  /// The sourcekitd identifier of the refactoring action.
  var actionString: String { get set }

  /// The range to refactor.
  var positionRange: Range<Position> { get set }

  /// The text document related to the refactoring action.
  var textDocument: TextDocumentIdentifier { get set }

  init(title: String, actionString: String, positionRange: Range<Position>, textDocument: TextDocumentIdentifier)
}
