//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring

/// A code completion item that should be returned to the client.
struct CompletionItem {
  /// The label with which the item should be displayed in an IDE
  let label: String

  /// The string that should be used to match against what the user type.
  let filterText: String

  /// The module that defines the code completion item or `nil` if the item is not defined in a module, like a keyword.
  let module: String?

  /// The type that the code completion item produces.
  ///
  /// Eg. the type of a variable or the return type of a function. `nil` for completions that don't have a type, like
  /// keywords.
  let typeName: String?

  /// The edits that should be made if the code completion is selected.
  let textEdit: TextEdit
  let kind: ItemKind
  let isSystem: Bool
  let textMatchScore: Double
  let priorityBucket: PriorityBucket
  let semanticScore: Double
  let semanticClassification: SemanticClassification?
  let id: Identifier
  let hasDiagnostic: Bool
  let groupID: Int?
}

extension CompletionItem: CustomStringConvertible, CustomDebugStringConvertible {
  var description: String { filterText }
  var debugDescription: String {
    """
    [\(kind)]\
    \(isSystem ? "[sys]" : "")\
    \(label);\
    \(typeName == nil ? "" : "type=\(typeName!)") \
    edit=\(textEdit); \
    pri=\(priorityBucket.rawValue); \
    index=\(id.index)
    """
  }
}
