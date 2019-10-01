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

/// Request from the server to the client to modify resources on the client side.
///
/// - Parameters:
///   - label: An optional label of the workspace edit.
///   - edit: The edits to apply.
public struct ApplyEditRequest: RequestType {
  public static let method: String = "workspace/applyEdit"
  public typealias Response = ApplyEditResponse

  /// An optional label of the workspace edit.
  /// Used by the client's user interface for things such as
  /// the stack to undo the workspace edit.
  public var label: String?

  /// The edits to apply.
  public var edit: WorkspaceEdit

  public init(label: String? = nil, edit: WorkspaceEdit) {
    self.label = label
    self.edit = edit
  }
}

public struct ApplyEditResponse: Codable, Hashable, ResponseType {
  /// Indicates whether the edit was applied or not.
  public var applied: Bool

  /// An optional textual description for why the edit was not applied.
  public var failureReason: String?

  public init(applied: Bool, failureReason: String?) {
    self.applied = applied
    self.failureReason = failureReason
  }
}
