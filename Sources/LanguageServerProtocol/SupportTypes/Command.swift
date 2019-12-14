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

/// Represents a reference to a command identified by a string. Used as the result of
/// requests that returns actions to the user, later used as the parameter of
/// workspace/executeCommand if the user wishes to execute said command.
public struct Command: Codable, Hashable {

  /// The title of this command.
  public var title: String

  /// The internal identifier of this command.
  public var command: String

  /// The arguments related to this command.
  public var arguments: [LSPAny]?

  public init(title: String, command: String, arguments: [LSPAny]?) {
    self.title = title
    self.command = command
    self.arguments = arguments
  }
}
