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

import SKSupport

/// Represents a reference to a command identified by a string. Used as the result of
/// requests that returns actions to the user, later used as the parameter of
/// workspace/executeCommand if the user wishes to execute said command.
public protocol Command {
  /// The internal identifier for this command.
  static var command: String { get set }
  /// The arguments related to this command.
  /// This is [Any]? in the LSP, but internally we treat it
  /// differently to make it easier to create and (de)serialize commands.
  var arguments: CommandArgsType? { get set }
}

/// A `CommandDataType` represents the arguments required to execute a `Command`.
public protocol CommandArgsType: Codable {
  var textDocument: TextDocumentIdentifier { get set }
}

public struct SemanticRefactorCommand: Command {
  public static let command = "sourcekit.lsp.semantic.refactoring.command"

  public var arguments: SemanticRefactorCommandArgs?

  public init(arguments: SemanticRefactorCommandArgs) {
    self.arguments = arguments
  }
}

public struct SemanticRefactorCommandArgs: CommandArgsType {

  /// The sourcekitd identifier of the refactoring action.
  public var actionString: String

  /// The starting line of the range to refactor.
  public var line: Int

  /// The starting column of the range to refactor.
  public var column: Int

  /// The length of the range to refactor.
  public var length: Int

  public var textDocument: TextDocumentIdentifier

  public init(actionString: String, line: Int, column: Int, length: Int, textDocument: TextDocumentIdentifier) {
    self.title = title
    self.textDocument = textDocument
    self.actionString = actionString
    self.line = line
    self.column = column
    self.length = length
  }
}
