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

import Foundation

public typealias CodeActionProviderCompletion = (([CodeAction]) -> Void)
public typealias CodeActionProvider = ((CodeActionRequest, CodeActionProviderCompletion) -> Void)

/// Request for returning all possible code actions for a given text document and range.
///
/// The code action request is sent from the client to the server to compute commands for a given text
/// document and range. These commands are typically code fixes to either fix problems or to beautify/
/// refactor code.
///
/// Servers that provide code actions should set the `codeActions` server capability.
///
/// - Parameters:
///   - textDocument: The document in which the command was invoked.
///   - range: The specific range inside the document to search for code actions.
///   - context: The context of the request.
///
/// - Returns: A list of code actions for the given range and context.
public struct CodeActionRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/codeAction"
  public typealias Response = CodeActionRequestResponse?

  /// The range for which the command was invoked.
  public var range: PositionRange

  /// Context carrying additional information.
  public var context: CodeActionContext

  /// The document in which the command was invoked.
  public var textDocument: TextDocumentIdentifier

  public init(range: Range<Position>, context: CodeActionContext, textDocument: TextDocumentIdentifier) {
    self.range = PositionRange(range)
    self.context = context
    self.textDocument = textDocument
  }
}

/// Wrapper type for the response of a CodeAction request.
/// If the client supports CodeAction literals, the encoded type will be the CodeAction array itself.
/// Otherwise, the encoded value will be an array of CodeActions' inner Command structs.
public struct CodeActionRequestResponse: ResponseType, Codable {
  public var codeActions: [CodeAction]
  public var commands: [Command]

  public init(codeActions: [CodeAction], clientCapabilities: TextDocumentClientCapabilities.CodeAction?) {
    if let literalSupport = clientCapabilities?.codeActionLiteralSupport {
      let supportedKinds = literalSupport.codeActionKind.valueSet
      self.codeActions = codeActions.filter {
        if let kind = $0.kind {
          return supportedKinds.contains(kind)
        } else {
          // The client guarantees that unsupported kinds will be treated,
          // so it's probably safe to include unspecified kinds into the result.
          return true
        }
      }
      self.commands = []
    } else {
      self.codeActions = []
      self.commands = codeActions.compactMap { $0.command }
    }
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var codeActions = [CodeAction]()
    var commands = [Command]()
    while container.isAtEnd == false {
      if let codeAction = try container.decodeIfPresent(CodeAction.self) {
        codeActions.append(codeAction)
      } else if let command = try container.decodeIfPresent(Command.self) {
        commands.append(command)
      } else {
        let error = "CodeActionRequestResponse has neither a CodeAction or a Command."
        throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
      }
    }
    self.codeActions = codeActions
    self.commands = commands
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    for codeAction in codeActions {
      try container.encode(codeAction)
    }
    for command in commands {
      try container.encode(command)
    }
  }
}

public struct CodeActionContext: Codable, Hashable {

  /// An array of diagnostics.
  public var diagnostics: [Diagnostic]

  /// Requested kind of actions to return.
  /// If provided, actions of these kinds are filtered out by the client before being shown,
  /// so servers can omit computing them.
  public var only: [CodeActionKind]?

  public init(diagnostics: [Diagnostic] = [], only: [CodeActionKind]? = nil) {
    self.diagnostics = diagnostics
    self.only = only
  }
}

public struct CodeAction: Codable, Equatable, ResponseType {

  /// A short, human-readable, title for this code action.
  public var title: String

  /// The kind of the code action.
  public var kind: CodeActionKind?

  /// The diagnostics that this code action resolves, if applicable.
  public var diagnostics: [Diagnostic]?

  /// A command this code action executes.
  /// If a code action provides an edit and a command,
  /// first the edit is executed and then the command.
  public var command: Command?

  public init(title: String, kind: CodeActionKind? = nil, diagnostics: [Diagnostic]? = nil, command: Command? = nil) {
    self.title = title
    self.kind = kind
    self.diagnostics = diagnostics
    self.command = command
  }
}
