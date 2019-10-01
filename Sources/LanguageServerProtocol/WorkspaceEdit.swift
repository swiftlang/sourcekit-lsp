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
public struct WorkspaceEdit: Hashable, ResponseType, LSPAnyCodable {

  /// The edits to be applied to existing resources.
  public var changes: [URL: [TextEdit]]?

  public init(changes: [URL: [TextEdit]]?) {
    self.changes = changes
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .dictionary(let lspDict) = dictionary[CodingKeys.changes.stringValue] else {
      return nil
    }
    var dictionary = [URL: [TextEdit]]()
    for (key, value) in lspDict {
      guard let url = URL(string: key) else {
        return nil
      }
      guard case .array(let array) = value else {
        return nil
      }
      var edits = [TextEdit]()
      for case .dictionary(let editDict) in array {
        guard let edit = TextEdit(fromLSPDictionary: editDict) else {
          return nil
        }
        edits.append(edit)
      }
      dictionary[url] = edits
    }
    self.changes = dictionary
  }

  public func encodeToLSPAny() -> LSPAny {
    guard let changes = changes else {
      return nil
    }
    let values = changes.map {
      ($0.key.absoluteString, LSPAny.array($0.value.map { $0.encodeToLSPAny() }))
    }
    let dictionary = Dictionary(uniqueKeysWithValues: values)
    return .dictionary([
      CodingKeys.changes.stringValue: .dictionary(dictionary)
    ])
  }
}

// Workaround for Codable not correctly encoding dictionaries whose keys aren't strings.
extension WorkspaceEdit: Codable {
  enum CodingKeys: String, CodingKey {
    case changes
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.changes = try container.decode([URL: [TextEdit]].self, forKey: .changes)
  }

  public func encode(to encoder: Encoder) throws {
    guard let changes = changes else {
      return
    }
    var stringDictionary = [String: [TextEdit]]()
    for (key, value) in changes {
      stringDictionary[key.absoluteString] = value
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(stringDictionary, forKey: .changes)
  }
}
