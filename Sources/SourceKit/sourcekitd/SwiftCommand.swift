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
import LanguageServerProtocol
import Foundation

/// The set of known Swift commands.
///
/// All commands from the Swift LSP should be listed here.
public let builtinSwiftCommands: [String] = []

/// A `Command` that should be executed by Swift's language server.
public protocol SwiftCommand: Codable, Hashable {
  static var identifier: String { get }
  static func decode(fromDictionary dictionary: [String: LSPAny]) -> Self?
  var title: String { get set }
  func asCommandArgument() -> LSPAny
}

extension SwiftCommand {
  /// Converts this `SwiftCommand` to a generic LSP `Command` object.
  public func asCommand() throws -> Command {
    let argument = asCommandArgument()
    return Command(title: title, command: Self.identifier, arguments: [argument])
  }
}

extension ExecuteCommandRequest {
  /// Attempts to convert the underlying `Command` metadata from this request
  /// to a specific Swift language server `SwiftCommand`.
  ///
  /// - Parameters:
  ///   - type: The `SwiftCommand` metatype to convert to.
  public func swiftCommand<T: SwiftCommand>(ofType type: T.Type) -> T? {
    guard type.identifier == command else {
      return nil
    }
    guard let argument = arguments?.first else {
      return nil
    }
    guard case let .dictionary(dictionary) = argument else {
      return nil
    }
    return type.decode(fromDictionary: dictionary)
  }
}

public struct SemanticRefactorCommand: SwiftCommand {

  public static var identifier: String {
    return "semantic.refactor.command"
  }

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

  /// The text document related to the refactoring action.
  public var textDocument: TextDocumentIdentifier

  public static func decode(fromDictionary dictionary: [String: LSPAny]) -> SemanticRefactorCommand? {
    guard case .dictionary(let dict)? = dictionary[CodingKeys.textDocument.stringValue],
          case .string(let title)? = dictionary[CodingKeys.title.stringValue],
          case .string(let actionString)? = dictionary[CodingKeys.actionString.stringValue],
          case .int(let line)? = dictionary[CodingKeys.line.stringValue],
          case .int(let column)? = dictionary[CodingKeys.column.stringValue],
          case .int(let length)? = dictionary[CodingKeys.length.stringValue],
          case .string(let urlString)? = dict[TextDocumentIdentifier.CodingKeys.url.stringValue],
          let url = URL(string: urlString) else
    {
      return nil
    }
    return SemanticRefactorCommand(title: title,
                                   actionString: actionString,
                                   line: line,
                                   column: column,
                                   length: length,
                                   textDocument: TextDocumentIdentifier(url))
  }

  public init(title: String, actionString: String, line: Int, column: Int, length: Int, textDocument: TextDocumentIdentifier) {
    self.title = title
    self.actionString = actionString
    self.line = line
    self.column = column
    self.length = length
    self.textDocument = textDocument
  }

  public func asCommandArgument() -> LSPAny {
    let textDocumentArgument = LSPAny.dictionary(
      [TextDocumentIdentifier.CodingKeys.url.stringValue: .string(textDocument.url.absoluteString)]
    )
    return .dictionary([CodingKeys.title.stringValue: .string(title),
                        CodingKeys.actionString.stringValue: .string(actionString),
                        CodingKeys.line.stringValue: .int(line),
                        CodingKeys.column.stringValue: .int(column),
                        CodingKeys.length.stringValue: .int(length),
                        CodingKeys.textDocument.stringValue: textDocumentArgument])
  }
}
