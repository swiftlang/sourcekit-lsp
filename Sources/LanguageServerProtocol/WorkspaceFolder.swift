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

/// Unique identifier for a document.
public struct WorkspaceFolder {

  /// A URL that uniquely identifies the workspace.
  public var url: URL

  /// The name of the workspace (default: basename of url).
  public var name: String

  public init(url: URL, name: String? = nil) {
    self.url = url
    self.name = name ?? url.lastPathComponent
    if self.name.isEmpty {
      self.name = "unknown_workspace"
    }
  }
}

extension WorkspaceFolder: Equatable {}
extension WorkspaceFolder: Hashable {}

// Encode using the key "uri" to match LSP.
extension WorkspaceFolder: Codable {
  private enum CodingKeys: String, CodingKey {
    case url = "uri"
    case name
  }
}
