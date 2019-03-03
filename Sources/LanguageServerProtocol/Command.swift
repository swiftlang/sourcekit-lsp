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

/// Represents the identifiers of SourceKit-LSP's supported commands.
public enum CommandIdentifier: String, Codable, CaseIterable {
  case semanticRefactor = "sourcekit.lsp.semantic.refactoring.command"
}

/// Represents a reference to a command identified by a string. Used as the result of
/// requests that returns actions to the user, later used as the parameter of
/// workspace/executeCommand if the user wishes to execute said command.
public enum Command: Hashable {
  case semanticRefactor(TextDocumentIdentifier, SemanticRefactorCommandArgs)

  /// The title of this command.
  public var title: String {
    switch self {
    case let .semanticRefactor(_, args):
      return args.title
    }
  }

  /// The internal identifier of this command.
  public var identifier: CommandIdentifier {
    switch self {
    case .semanticRefactor:
      return CommandIdentifier.semanticRefactor
    }
  }

  /// The arguments related to this command.
  /// This is [Any]? in the LSP, but treated differently here
  /// to make it easier to create and (de)serialize commands.
  public var arguments: CommandArgs? {
    switch self {
    case let .semanticRefactor(_, args):
      return args
    }
  }

  /// The documented related to this command.
  public var textDocument: TextDocumentIdentifier {
    switch self {
    case let .semanticRefactor(textDocument, _):
      return textDocument
    }
  }
}

public protocol CommandArgs: Codable {}
extension TextDocumentIdentifier: CommandArgs {}

extension Command: Codable {

  public enum CodingKeys: String, CodingKey {
    case title
    case command
    case arguments
  }

  public enum CodingError: Error {
    case unknownCommand
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let identifier = try container.decode(String.self, forKey: .command)
    var argumentsContainer = try container.nestedUnkeyedContainer(forKey: .arguments)
    // Command arguments are sent to the LSP as a [Any]? [textDocument, arguments?] array.
    let textDocument = try argumentsContainer.decode(TextDocumentIdentifier.self)
    switch identifier {
    case CommandIdentifier.semanticRefactor.rawValue:
      let args = try argumentsContainer.decode(SemanticRefactorCommandArgs.self)
      self = .semanticRefactor(textDocument, args)
    default:
      log("Failed to decode Command: Unknown identifier \(identifier)", level: .warning)
      throw CodingError.unknownCommand
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(identifier, forKey: .command)
    var argumentsContainer = container.nestedUnkeyedContainer(forKey: .arguments)
    // Command arguments are sent to the LSP as a [Any]? [textDocument, arguments?] array.
    try argumentsContainer.encode(textDocument)
    try arguments?.encode(toArgumentsEncoder: &argumentsContainer)
  }
}

extension CommandArgs {
  func encode(toArgumentsEncoder encoder: inout UnkeyedEncodingContainer) throws {
    try encoder.encode(self)
  }
}

public struct SemanticRefactorCommandArgs: CommandArgs, Hashable {

  /// The name of this refactoring action.
  public var title: String

  /// The sourcekitd identifier of the refactoring action.
  public var actionString: String

  /// The starting line of the range to refactor.
  public var line: Int

  /// The starting column of the range to refactor.
  public var column: Int

  /// The length of the range to refactor.
  public var length: Int

  public init(title: String, actionString: String, line: Int, column: Int, length: Int) {
    self.title = title
    self.actionString = actionString
    self.line = line
    self.column = column
    self.length = length
  }
}
