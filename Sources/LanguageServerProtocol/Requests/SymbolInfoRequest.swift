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
  public struct ModuleInfo: Codable, Hashable, Sendable {
    /// The name of the module in which the symbol is defined.
    public let moduleName: String

    /// If the symbol is defined within a subgroup of a module, the name of the group. Otherwise `nil`.
    public let groupName: String?

    public init(moduleName: String, groupName: String? = nil) {
      self.moduleName = moduleName
      self.groupName = groupName
    }
  }

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

  /// Whether the symbol is a dynamic call for which it isn't known which method will be invoked at runtime. This is
  /// the case for protocol methods and class functions.
  ///
  /// Optional because `clangd` does not return whether a symbol is dynamic.
  public var isDynamic: Bool?

  /// Whether this symbol is defined in the SDK or standard library.
  ///
  /// This property only applies to Swift symbols.
  public var isSystem: Bool?

  /// If the symbol is dynamic, the USRs of the types that might be called.
  ///
  /// This is relevant in the following cases
  /// ```swift
  /// class A {
  ///   func doThing() {}
  /// }
  /// class B: A {}
  /// class C: B {
  ///   override func doThing() {}
  /// }
  /// class D: A {
  ///   override func doThing() {}
  /// }
  /// func test(value: B) {
  ///   value.doThing()
  /// }
  /// ```
  ///
  /// The USR of the called function in `value.doThing` is `A.doThing` (or its
  /// mangled form) but it can never call `D.doThing`. In this case, the
  /// receiver USR would be `B`, indicating that only overrides of subtypes in
  /// `B` may be called dynamically.
  public var receiverUsrs: [String]?

  /// If the symbol is defined in a module that doesn't have source information associated with it, the name and group
  /// and group name that defines this symbol.
  ///
  /// This property only applies to Swift symbols.
  public var systemModule: ModuleInfo?

  /// The line number where the symbol is declared in the file.
  ///
  /// This value is 1-based, meaning the first line of the file is numbered 1.
  /// For example, in the following content:
  /// ```
  /// func test() {}
  /// ```
  /// If `test()` appears on the second line, `line` would be `2`.
  public var line: Int?

  /// The length of the symbol’s declaration in characters.
  ///
  /// This represents how many characters the symbol’s name and syntax span.
  /// For example, for the symbol `test()`, `length` would be `6` (including the parentheses `()`).
  public var length: Int?

  /// The column number where the symbol's declaration starts in the line.
  ///
  /// This value is 1-based, meaning the first character of the line is column 1.
  /// For example, in the following line:
  /// ```
  /// func test() {}
  /// ```
  /// If `test` starts at the 6th character, the `column` would be `6`.
  public var column: Int?

  public init(
    name: String?,
    containerName: String?,
    usr: String?,
    bestLocalDeclaration: Location?,
    kind: SymbolKind?,
    isDynamic: Bool?,
    isSystem: Bool?,
    receiverUsrs: [String]?,
    systemModule: ModuleInfo?,
    line: Int?,
    length: Int?,
    column: Int?
  ) {
    self.name = name
    self.containerName = containerName
    self.usr = usr
    self.bestLocalDeclaration = bestLocalDeclaration
    self.kind = kind
    self.isDynamic = isDynamic
    self.isSystem = isSystem
    self.receiverUsrs = receiverUsrs
    self.systemModule = systemModule
    self.line = line
    self.length = length
    self.column = column
  }
}
