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

/// Request sent from the client to trigger command execution on the server.
///
/// The execution of this request can be the result of a request that returns a command,
/// such as CodeActionsRequest and CodeLensRequest. In most cases, the server creates a WorkspaceEdit
/// structure and applies the changes to the workspace using the ApplyEditRequest.
///
/// Servers that provide command execution should set the `executeCommand` server capability.
///
/// - Parameters:
///   - command: The command to be executed.
///   - arguments: The arguments to use when executing the command.
public struct ExecuteCommandRequest: RequestType {
  public static let method: String = "workspace/executeCommand"
  public typealias Response = LSPAny?

  /// The command to be executed.
  public var command: String

  /// Arguments that the command should be invoked with.
  public var arguments: [LSPAny]?

  public init(command: String, arguments: [LSPAny]?) {
    self.command = command
    self.arguments = arguments
  }
}
