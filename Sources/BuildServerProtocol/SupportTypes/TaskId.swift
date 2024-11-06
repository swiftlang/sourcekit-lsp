//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

public typealias TaskIdentifier = String

public struct TaskId: Sendable, Codable, Hashable {
  /// A unique identifier
  public var id: TaskIdentifier

  /// The parent task ids, if any. A non-empty parents field means
  /// this task is a sub-task of every parent task id. The child-parent
  /// relationship of tasks makes it possible to render tasks in
  /// a tree-like user interface or inspect what caused a certain task
  /// execution.
  /// OriginId should not be included in the parents field, there is a separate
  /// field for that.
  public var parents: [TaskIdentifier]?

  public init(id: TaskIdentifier, parents: [TaskIdentifier]? = nil) {
    self.id = id
    self.parents = parents
  }
}
