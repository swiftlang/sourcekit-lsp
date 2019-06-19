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

/// A workspace edit represents changes to many resources managed in the workspace.
public struct WorkspaceEdit: Codable, Hashable, ResponseType {

  /// The edits to be applied to existing resources.
  public var changes: [String: [TextEdit]]?

  public init(changes: [URL: [TextEdit]]?) {
    guard let changes = changes else {
      return
    }
    let changesArray = changes.map { ($0.key.absoluteString, $0.value) }
    self.changes = Dictionary(uniqueKeysWithValues: changesArray)
  }
}
