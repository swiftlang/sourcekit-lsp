//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The code lens request is sent from the client to the server to compute code lenses for a given text document.
public struct CodeLensRequest: TextDocumentRequest {
  public static var method: String = "textDocument/codeLens"
  public typealias Response = [CodeLens]?

  /// The document to request code lens for.
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}

/// A code lens represents a command that should be shown along with
/// source text, like the number of references, a way to run tests, etc.
///
/// A code lens is _unresolved_ when no command is associated to it. For
/// performance reasons the creation of a code lens and resolving should be done
/// in two stages.
public struct CodeLens: ResponseType, Hashable {
  /// The range in which this code lens is valid. Should only span a single
  /// line.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

   /// The command this code lens represents.
  public var command: Command?

  /// A data entry field that is preserved on a code lens item between
  /// a code lens and a code lens resolve request.
  public var data: LSPAny?

  public init(range: Range<Position>, command: Command? = nil, data: LSPAny? = nil) {
    self.range = range
    self.command = command
    self.data = data
  }
}
