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

import LanguageServerProtocol
import Foundation
import SKSupport

/// Represents metadata that SourceKit-LSP injects at every command returned by code actions.
/// The ExecuteCommand is not a TextDocumentRequest, so metadata is injected to allow SourceKit-LSP
/// to determine where a command should be executed.
public struct SourceKitLSPCommandMetadata: Codable, Hashable {

  public static func decode(fromDictionary dictionary: [String: LSPAny]) -> SourceKitLSPCommandMetadata? {
    guard case .dictionary(let textDocumentDict)? = dictionary[CodingKeys.sourcekitlsp_textDocument.stringValue],
          case .string(let urlString)? = textDocumentDict[TextDocumentIdentifier.CodingKeys.url.stringValue],
          let url = URL(string: urlString) else
    {
      return nil
    }
    let textDocument = TextDocumentIdentifier(url)
    return SourceKitLSPCommandMetadata(textDocument: textDocument)
  }

  public var sourcekitlsp_textDocument: TextDocumentIdentifier

  public init(textDocument: TextDocumentIdentifier) {
    self.sourcekitlsp_textDocument = textDocument
  }

  func asCommandArgument() -> LSPAny {
    let textDocumentArgument = LSPAny.dictionary(
      [TextDocumentIdentifier.CodingKeys.url.stringValue: .string(sourcekitlsp_textDocument.url.absoluteString)]
    )
    return .dictionary([CodingKeys.sourcekitlsp_textDocument.stringValue: textDocumentArgument])
  }
}

extension CodeActionRequest {
  public func injectMetadata(atResponse response: CodeActionRequestResponse?) -> CodeActionRequestResponse? {
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    let metadataArgument = metadata.asCommandArgument()
    switch response {
    case .codeActions(var codeActions)?:
      for i in 0..<codeActions.count {
        codeActions[i].command?.arguments?.append(metadataArgument)
      }
      return .codeActions(codeActions)
    case .commands(var commands)?:
      for i in 0..<commands.count {
        commands[i].arguments?.append(metadataArgument)
      }
      return .commands(commands)
    case nil:
      return nil
    }
  }
}

extension ExecuteCommandRequest {
  /// The document in which the command was invoked.
  public var textDocument: TextDocumentIdentifier? {
    return metadata?.sourcekitlsp_textDocument
  }

  /// Optional metadata containing SourceKit-LSP information about this command.
  public var metadata: SourceKitLSPCommandMetadata? {
    guard case .dictionary(let dictionary)? = arguments?.last else {
      return nil
    }
    guard let metadata = SourceKitLSPCommandMetadata.decode(fromDictionary: dictionary) else {
      log("failed to decode lsp metadata in executeCommand request", level: .error)
      return nil
    }
    return metadata
  }

  /// Returns this Command's arguments without SourceKit-LSP's injected metadata, if it exists.
  public var argumentsWithoutLSPMetadata: [LSPAny]? {
    guard metadata != nil else {
      return arguments
    }
    return arguments?.dropLast()
  }
}
