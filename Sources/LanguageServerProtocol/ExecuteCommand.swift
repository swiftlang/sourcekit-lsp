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

import Foundation

/// Request sent from the client to to trigger command execution on the server.
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

  // Note: The LSP type for this response is `Any?`.
  public typealias Response = CommandArgumentType?

  /// The command to be executed.
  public var command: String

  /// Arguments that the command should be invoked with.
  public var arguments: [CommandArgumentType]?

  /// The document in which the command was invoked.
  public var textDocument: TextDocumentIdentifier? {
    return metadata?.textDocument
  }

  /// Optional metadata containing SourceKit-LSP infomration about this command.
  public var metadata: SourceKitLSPCommandMetadata? {
    guard case .dictionary(let dictionary)? = arguments?.last else {
      return nil
    }
    guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
      return nil
    }
    return try? JSONDecoder().decode(SourceKitLSPCommandMetadata.self, from: data)
  }

  public init(command: String, arguments: [CommandArgumentType]?) {
    self.command = command
    self.arguments = arguments
  }
}

/// Represents metadata that SourceKit-LSP injects at every command returned by code actions.
/// The ExecuteCommand is not a TextDocumentRequest, so metadata is injected to allow SourceKit-LSP
/// to determine where a command should be executed.
public struct SourceKitLSPCommandMetadata: Codable, Hashable {
  public var textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }
}
