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

/// The type hierarchy request is sent from the client to the server to return a
/// type hierarchy for the language element of the given text document positions.
/// Will return nil if the server couldn’t infer a valid type from the position.
///
/// The type hierarchy requests are executed in two steps:
/// 1. A type hierarchy item is resolved for the given text document position
///   (via `textDocument/prepareTypeHierarchy`)
/// 2. The supertype or subtype type hierarchy items are resolved for a type hierarchy item
///   (via `typeHierarchy/supertypes` or `typeHierarchy/subtypes`)
public struct TypeHierarchyPrepareRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/prepareTypeHierarchy"
  public typealias Response = [TypeHierarchyItem]?

  /// The document in which to prepare the type hierarchy items.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to prepare the type hierarchy items.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}
