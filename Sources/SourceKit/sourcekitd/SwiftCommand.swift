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
public let builtinSwiftCommands: [String] = [
  SemanticRefactorCommand.self
].map { $0.identifier }

/// A `Command` that should be executed by Swift's language server.
public protocol SwiftCommand: Codable, Hashable, LSPAnyCodable {
  static var identifier: String { get }
  var title: String { get set }
}

extension SwiftCommand {
  /// Converts this `SwiftCommand` to a generic LSP `Command` object.
  public func asCommand() throws -> Command {
    let argument = encodeToLSPAny()
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
    return type.init(fromLSPDictionary: dictionary)
  }
}

public struct SemanticRefactorCommand: SwiftCommand {

  public static let identifier: String = "semantic.refactor.command"

  /// The name of this refactoring action.
  public var title: String

  /// The sourcekitd identifier of the refactoring action.
  public var actionString: String

  /// The range to refactor.
  public var positionRange: Range<Position>

  /// The text document related to the refactoring action.
  public var textDocument: TextDocumentIdentifier

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .dictionary(let documentDict)? = dictionary[CodingKeys.textDocument.stringValue],
          case .string(let title)? = dictionary[CodingKeys.title.stringValue],
          case .string(let actionString)? = dictionary[CodingKeys.actionString.stringValue],
          case .dictionary(let rangeDict)? = dictionary[CodingKeys.positionRange.stringValue] else
    {
      return nil
    }
    guard let positionRange = Range<Position>(fromLSPDictionary: rangeDict),
          let textDocument = TextDocumentIdentifier(fromLSPDictionary: documentDict) else {
      return nil
    }
    self.init(title: title,
              actionString: actionString,
              positionRange: positionRange,
              textDocument: textDocument)
  }

  public init(title: String, actionString: String, positionRange: Range<Position>, textDocument: TextDocumentIdentifier) {
    self.title = title
    self.actionString = actionString
    self.positionRange = positionRange
    self.textDocument = textDocument
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([CodingKeys.title.stringValue: .string(title),
                        CodingKeys.actionString.stringValue: .string(actionString),
                        CodingKeys.positionRange.stringValue: positionRange.encodeToLSPAny(),
                        CodingKeys.textDocument.stringValue: textDocument.encodeToLSPAny()])
  }
}
