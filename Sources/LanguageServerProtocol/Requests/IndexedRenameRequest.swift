//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Rename all occurrences of a symbol named `oldName` to `newName` at the
/// given `positions`.
///
/// The use case of this method is for when the positions to rename are already
/// known, eg. from an index lookup outside of clangd's built-in index. In
/// particular, it determines the edits necessary to rename multi-piece
/// Objective-C selector names.
///
/// `textDocument` is used to determine the language options for the symbol to
/// rename, eg. to decide whether `oldName` and `newName` are Objective-C
/// selectors or normal identifiers.
///
/// This is a clangd extension.
public struct IndexedRenameRequest: TextDocumentRequest, Hashable {
  public static let method: String = "workspace/indexedRename"
  public typealias Response = WorkspaceEdit?

  /// The document in which the declaration to rename is declared. Its compiler
  /// arguments are used to infer language settings for the rename.
  public var textDocument: TextDocumentIdentifier

  /// The old name of the symbol.
  public var oldName: String

  /// The new name of the symbol.
  public var newName: String

  /// The positions at which the symbol is known to appear and that should be
  /// renamed. The key is a document URI
  public var positions: [DocumentURI: [Position]]

  public init(
    textDocument: TextDocumentIdentifier,
    oldName: String,
    newName: String,
    positions: [DocumentURI: [Position]]
  ) {
    self.textDocument = textDocument
    self.oldName = oldName
    self.newName = newName
    self.positions = positions
  }
}

// Workaround for Codable not correctly encoding dictionaries whose keys aren't strings.
extension IndexedRenameRequest: Codable {
  private enum CodingKeys: CodingKey {
    case textDocument
    case oldName
    case newName
    case positions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.textDocument = try container.decode(
      TextDocumentIdentifier.self,
      forKey: IndexedRenameRequest.CodingKeys.textDocument
    )
    self.oldName = try container.decode(String.self, forKey: IndexedRenameRequest.CodingKeys.oldName)
    self.newName = try container.decode(String.self, forKey: IndexedRenameRequest.CodingKeys.newName)
    self.positions = try container.decode([String: [Position]].self, forKey: .positions).mapKeys(DocumentURI.init)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(self.textDocument, forKey: IndexedRenameRequest.CodingKeys.textDocument)
    try container.encode(self.oldName, forKey: IndexedRenameRequest.CodingKeys.oldName)
    try container.encode(self.newName, forKey: IndexedRenameRequest.CodingKeys.newName)
    try container.encode(self.positions.mapKeys(\.stringValue), forKey: IndexedRenameRequest.CodingKeys.positions)

  }
}

fileprivate extension Dictionary {
  func mapKeys<NewKeyType: Hashable>(_ transform: (Key) -> NewKeyType) -> [NewKeyType: Value] {
    return [NewKeyType: Value](uniqueKeysWithValues: self.map { (transform($0.key), $0.value) })
  }
}
