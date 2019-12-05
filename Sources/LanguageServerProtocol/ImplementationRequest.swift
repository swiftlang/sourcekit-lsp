//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The go to implementation request is sent from the client to the server 
/// to resolve the implementation location of a symbol at a given 
/// text document position.
///
/// Servers that provide Goto Implementation support should set 
/// the `implementationProvider` server capability.
///
/// - Parameters:
///   - textDocument: The document in which the given symbol is located.
///   - position: The document location of a given symbol.
///
/// - Returns: The location of the implementations of protocol requirements,
///            protocol conforming types, subclasses, or overrides.
public struct ImplementationRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/implementation"
  public typealias Response = LocationsOrLocationLinksResponse?

  /// The document in which the given symbol is located.
  public var textDocument: TextDocumentIdentifier

  /// The document location of a given symbol.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}
