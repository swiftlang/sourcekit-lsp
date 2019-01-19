//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKSupport

/// A `CommandDataType` represents the underlying data of a custom `Command`.
public protocol CommandDataType: Codable {
  static var identifier: String { get }
  var title: String { get set }
  var textDocument: TextDocumentIdentifier { get set }
}

extension CommandDataType {

  fileprivate typealias EncodingContainer = KeyedEncodingContainer<Command.CodingKeys>
  fileprivate typealias DecodingContainer = KeyedDecodingContainer<Command.CodingKeys>

  fileprivate static func decodeLSPArgumentKey(fromContainer container: DecodingContainer) throws -> Self {
    let arguments: [Self] = try container.decode([Self].self, forKey: .arguments)
    guard arguments.count == 1 else {
      log("Tried to decode command with an invalid argument structure", level: .warning)
      throw Command.CodingError.invalidArguments
    }
    return arguments[0]
  }

  fileprivate func encodeForLSPArgumentKey(inContainer container: inout EncodingContainer) throws {
    try container.encode([self], forKey: .arguments)
  }
}

/// Represents a reference to a command identified by a string. Used as the result of
/// requests that returns actions to the user, later used as the parameter of
/// workspace/executeCommand if the user wishes to execute said command.
public struct Command {

  /// Title of the command, like `save`.
  public var title: String {
    return data.title
  }

  /// The internal identifier for this command.
  public var command: String {
    return type(of: data).identifier
  }

  /// The data related to this command.
  /// This is called `arguments` and is [Any]? in the LSP, but internally we treat it
  /// differently to make it easier to create and (de)serialize commands.
  public var data: CommandDataType

  public var textDocument: TextDocumentIdentifier {
    return data.textDocument
  }

  public init(data: CommandDataType) {
    self.data = data
  }

  public func getDataAs<T: CommandDataType>(_ dataType: T.Type) -> T? {
    return data as? T
  }
}

extension Command: Codable {
  public enum CodingError: Error {
    case unknownCommand
    case invalidArguments
  }

  public enum CodingKeys: String, CodingKey {
    case title
    case command
    case arguments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let identifier: String = try container.decode(String.self, forKey: .command)
    guard let commandToDecode = builtinCommands.first(where: { $0.identifier == identifier }) else {
      log("Failed to decode Command: Unknown identifier \(identifier)", level: .warning)
      throw CodingError.unknownCommand
    }
    let data = try commandToDecode.decodeLSPArgumentKey(fromContainer: container)
    self.init(data: data)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(command, forKey: .command)
    try data.encodeForLSPArgumentKey(inContainer: &container)
  }
}

public struct SemanticRefactorCommandDataType: CommandDataType, Hashable {
  public static let identifier = "sourcekit.lsp.semantic.refactoring.command"

  /// The title of the refactoring action.
  public var title: String

  /// The sourcekitd identifier of the refactoring action.
  public var actionString: String

  /// The starting line of the range to refactor.
  public var line: Int

  /// The starting column of the range to refactor.
  public var column: Int

  /// The length of the range to refactor.
  public var length: Int

  public var textDocument: TextDocumentIdentifier

  public init(title: String, textDocument: TextDocumentIdentifier, actionString: String, line: Int, column: Int, length: Int) {
    self.title = title
    self.textDocument = textDocument
    self.actionString = actionString
    self.line = line
    self.column = column
    self.length = length
  }
}
