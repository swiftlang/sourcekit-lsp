//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request to find all references to the symbol at the given location across the workspace.
///
/// Looks up the symbol at the given position and returns a list of all references to that symbol
/// across the whole workspace. Unlike `documentHighlight`, this is not scoped to a single document.
///
/// Servers that provide document highlights should set the`referencesProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///   - includeDeclaration: Whether to include the declaration in the list of symbols.
///
/// - Returns: An array of locations, one for each reference.
public struct ReferencesRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/references"
  public typealias Response = [Location]

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public var context: ReferencesContext

  public init(textDocument: TextDocumentIdentifier, position: Position, context: ReferencesContext) {
    self.textDocument = textDocument
    self.position = position
    self.context = context
  }
}

public struct ReferencesContext: Codable, Hashable {
  /// Whether to include the declaration in the list of symbols, or just the references.
  public var includeDeclaration: Bool

  public init(includeDeclaration: Bool) {
    self.includeDeclaration = includeDeclaration
  }
}
