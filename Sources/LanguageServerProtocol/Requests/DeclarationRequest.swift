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

/// Request to find the declarations(s) of the symbol at the given location.
///
/// Looks up the symbol at the given position and returns a list of all
/// declarations involving that symbol in the workspace.
///
/// This request differs from `DefinitionRequest` because a symbol usually has
/// only one definition but potentially has many declarations involving that
/// symbol. E.g. the definition of a type versus the forward declarations of that type.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: The location of the declaration(s).
public struct DeclarationRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/declaration"
  public typealias Response = LocationsOrLocationLinksResponse?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}
