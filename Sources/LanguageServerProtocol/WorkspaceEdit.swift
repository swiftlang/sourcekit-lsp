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
public struct WorkspaceEdit: Hashable, ResponseType {

  /// The edits to be applied to existing resources.
  public var changes: [URL: [TextEdit]]?

  public init(changes: [URL: [TextEdit]]?) {
    self.changes = changes
  }
}

// Workaround for Codable not correctly encoding dictionaries whose keys aren't strings.
extension WorkspaceEdit: Codable {
  private enum CodingKeys: String, CodingKey {
    case changes
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let changesDict = try container.decode([String: [TextEdit]].self, forKey: .changes)
    var changes = [URL: [TextEdit]]()
    for change in changesDict {
      guard let url = URL(string: change.key) else {
        let error = "Changes key is not an URL."
        throw DecodingError.dataCorruptedError(forKey: .changes, in: container, debugDescription: error)
      }
      changes[url] = change.value
    }
    self.changes = changes
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

extension WorkspaceEdit: LSPAnyCodable {
  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .dictionary(let lspDict) = dictionary[CodingKeys.changes.stringValue] else {
      return nil
    }
    var dictionary = [URL: [TextEdit]]()
    for (key, value) in lspDict {
      guard let url = URL(string: key) else {
        return nil
      }
      guard let edits = [TextEdit](fromLSPArray: value) else {
        return nil
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
      ($0.key.absoluteString, $0.value.encodeToLSPAny())
    }
    let dictionary = Dictionary(uniqueKeysWithValues: values)
    return .dictionary([
      CodingKeys.changes.stringValue: .dictionary(dictionary)
    ])
  }
}

extension Array: LSPAnyCodable where Element: LSPAnyCodable {
  public init?(fromLSPArray array: LSPAny) {
    guard case .array(let array) = array else {
      return nil
    }
    var result = [Element]()
    for case .dictionary(let editDict) in array {
      guard let element = Element.init(fromLSPDictionary: editDict) else {
        return nil
      }
      result.append(element)
    }
    self = result
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    return nil
  }

  public func encodeToLSPAny() -> LSPAny {
    return .array(map { $0.encodeToLSPAny() })
  }
}
