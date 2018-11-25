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

/// A workspace edit represents changes to many resources managed in the workspace.
/// The edit should either provide changes or documentChanges. If the client can handle versioned document
/// edits and if documentChanges are present, the latter are preferred over changes.
public struct WorkspaceEdit : Codable, Hashable {
  /// The edits to be applied, which must be non-overlapping.
  public var changes: [TextEdit]?

  public var documentChanges: [TextDocumentEdit]?

  public init(changes: [TextEdit]) {
    self.changes = changes
  }

  public init(documentChanges: [TextDocumentEdit]) {
    self.documentChanges = documentChanges
  }
}
