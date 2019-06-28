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

/// The rename request is sent from the client to the server to perform 
/// a workspace-wide rename of a symbol.
///
///
/// - Parameters:
///   - textDocument: The document with the symbol selected for renaming
///   - position: Position of the symbol selected for renaming
///   - newName: The new name of the symbol
///
/// - Returns: WorkspaceEdit or nil, describing the modification to the workspace.
public struct RenameRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/rename"
  public typealias Response = WorkspaceEdit?

  /// The document to rename.
  public var textDocument: TextDocumentIdentifier

  /// The position at which this request was sent.
  public var position: Position

  /// The new name of the symbol. If the given name is not valid the
  /// request must return a `ResponseError` with an appropriate message set.
  public var newName: String

  public init(textDocument: TextDocumentIdentifier, position: Position, newName: String) {
    self.textDocument = textDocument
    self.position = position
    self.newName = newName
  }
}

/// A workspace edit represents changes to many resources managed in the workspace.
/// The edit should either provide changes or documentChanges. If the client can handle
/// versioned document edits and if documentChanges are present,
/// the latter are preferred over changes.
public struct WorkspaceEdit: Codable, Hashable, ResponseType {
  /// Holds changes to existing resources.
  public var changes: [URL:[TextEdit]]?

  // TODO: Implement `documentChanges`

  public init(changes: [URL:[TextEdit]]) {
    self.changes = changes
  }

  private enum CodingKeys: String, CodingKey {
    case changes
  }
  
  public init(from decoder: Decoder) throws {
    // we need to map [URL:[TextEdit]] to [String:[TextEdit]] because only 
    // Dictionaries keyed by String are encoded to dictionaries
    // even though URL is encoded directly as a string
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let stringDict = try container.decodeIfPresent([String:[TextEdit]].self, forKey: .changes) {
      self.changes = [URL:[TextEdit]](uniqueKeysWithValues: stringDict.map({ (URL(fileURLWithPath: $0), $1) }))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if let changes = self.changes {
      let stringDict = [String:[TextEdit]](uniqueKeysWithValues: changes.map({ ("\($0)", $1) }))
      try container.encode(stringDict, forKey: .changes)
    }
  }
}
