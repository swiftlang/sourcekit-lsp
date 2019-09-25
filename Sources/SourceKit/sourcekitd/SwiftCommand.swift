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
public protocol SwiftCommand: Codable, Hashable {
  init?(fromLSPDictionary: [String: LSPAny])

  static var identifier: String { get }
  var title: String { get set }

  func encodeToLSPAny() -> LSPAny
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

  public static var identifier: String {
    return "semantic.refactor.command"
  }

  /// The name of this refactoring action.
  public var title: String

  /// The sourcekitd identifier of the refactoring action.
  public var actionString: String

  /// The range to refactor.
  public var positionRange: Range<Position>

  /// The text document related to the refactoring action.
  public var textDocument: TextDocumentIdentifier

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .dictionary(let dict)? = dictionary[CodingKeys.textDocument.stringValue],
          case .string(let title)? = dictionary[CodingKeys.title.stringValue],
          case .string(let actionString)? = dictionary[CodingKeys.actionString.stringValue],
          case .string(let urlString)? = dict[TextDocumentIdentifier.CodingKeys.url.stringValue],
          case .dictionary(let rangeDict)? = dictionary[CodingKeys.positionRange.stringValue],
          case .dictionary(let start)? = rangeDict[PositionRange.CodingKeys.lowerBound.stringValue],
          case .int(let startLine) = start[Position.CodingKeys.line.stringValue],
          case .int(let startutf16index) = start[Position.CodingKeys.utf16index.stringValue],
          case .dictionary(let end)? = rangeDict[PositionRange.CodingKeys.upperBound.stringValue],
          case .int(let endLine) = end[Position.CodingKeys.line.stringValue],
          case .int(let endutf16index) = end[Position.CodingKeys.utf16index.stringValue],
          let url = URL(string: urlString) else
    {
      return nil
    }
    let startPosition = Position(line: startLine, utf16index: startutf16index)
    let endPosition = Position(line: endLine, utf16index: endutf16index)
    let positionRange = startPosition..<endPosition
    self.init(title: title,
              actionString: actionString,
              positionRange: positionRange,
              textDocument: TextDocumentIdentifier(url))
  }

  public init(title: String, actionString: String, positionRange: Range<Position>, textDocument: TextDocumentIdentifier) {
    self.title = title
    self.actionString = actionString
    self.positionRange = positionRange
    self.textDocument = textDocument
  }

  public func encodeToLSPAny() -> LSPAny {
    let textDocumentArgument = LSPAny.dictionary(
      [TextDocumentIdentifier.CodingKeys.url.stringValue: .string(textDocument.url.absoluteString)]
    )
    let startRange = LSPAny.dictionary(
      [Position.CodingKeys.line.stringValue: .int(positionRange.lowerBound.line),
       Position.CodingKeys.utf16index.stringValue: .int(positionRange.lowerBound.utf16index)]
    )
    let endRange = LSPAny.dictionary(
      [Position.CodingKeys.line.stringValue: .int(positionRange.upperBound.line),
       Position.CodingKeys.utf16index.stringValue: .int(positionRange.upperBound.utf16index)]
    )
    return .dictionary([CodingKeys.title.stringValue: .string(title),
                        CodingKeys.actionString.stringValue: .string(actionString),
                        CodingKeys.positionRange.stringValue: .dictionary([
                          PositionRange.CodingKeys.lowerBound.stringValue: startRange,
                          PositionRange.CodingKeys.upperBound.stringValue: endRange
                        ]),
                        CodingKeys.textDocument.stringValue: textDocumentArgument])
  }
}
