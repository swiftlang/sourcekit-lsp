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

/// Request for semantic information about the symbol at a given location **(LSP Extension)**.
///
/// This request looks up the symbol (if any) at a given text document location and returns
/// SymbolDetails for that location, including information such as the symbol's USR. The symbolInfo
/// request is not primarily designed for editors, but instead as an implementation detail of how
/// one LSP implementation (e.g. SourceKit) gets information from another (e.g. clangd) to use in
/// performing index queries or otherwise implementing the higher level requests such as definition.
///
/// - Parameters:
///   - textDocument: The document in which to lookup the symbol location.
///   - position: The document location at which to lookup symbol information.
///
/// - Returns: `[SymbolDetails]` for the given location, which may have multiple elements if there are
///   multiple references, or no elements if there is no symbol at the given location.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP and clangd. It does *not* require
/// any additional client or server capabilities to use.
public struct SymbolInfoRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/symbolInfo"
  public typealias Response = [SymbolDetails]

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// Detailed information about a symbol, such as the response to a `SymbolInfoRequest`
/// **(LSP Extension)**.
public struct SymbolDetails: ResponseType, Hashable {

  /// The name of the symbol, if any.
  public var name: String?

  /// The name of the containing type for the symbol, if any.
  ///
  /// For example, in the following snippet, the `containerName` of `foo()` is `C`.
  ///
  /// ```c++
  /// class C {
  ///   void foo() {}
  /// }
  /// ```
  public var containerName: String?

  /// The USR of the symbol, if any.
  public var usr: String?

  /// An opaque identifier in a format known only to clangd.
  // public var id: String?

  /// Best known declaration or definition location without global knowledge.
  ///
  /// For a local or private variable, this is generally the canonical definition location -
  /// appropriate as a response to a `textDocument/definition` request. For global symbols this is
  /// the best known location within a single compilation unit. For example, in C++ this might be
  /// the declaration location from a header as opposed to the definition in some other
  /// translation unit.
  public var bestLocalDeclaration: Location? = nil

  /// The kind of the symbol
  public var kind: SymbolKind?

  public init(
    name: String?,
    containerName: String? = nil,
    usr: String?,
    bestLocalDeclaration: Location? = nil,
    kind: SymbolKind? = nil)
  {
    self.name = name
    self.containerName = containerName
    self.usr = usr
    self.bestLocalDeclaration = bestLocalDeclaration
    self.kind = kind
  }
}
