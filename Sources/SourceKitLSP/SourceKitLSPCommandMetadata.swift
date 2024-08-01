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
import LanguageServerProtocol
import SKLogging
import SKSupport

/// Represents metadata that SourceKit-LSP injects at every command returned by code actions.
/// The ExecuteCommand is not a TextDocumentRequest, so metadata is injected to allow SourceKit-LSP
/// to determine where a command should be executed.
package struct SourceKitLSPCommandMetadata: Codable, Hashable {

  package var sourcekitlsp_textDocument: TextDocumentIdentifier

  package init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    let textDocumentKey = CodingKeys.sourcekitlsp_textDocument.stringValue
    guard case .dictionary(let textDocumentDict)? = dictionary[textDocumentKey],
      let textDocument = TextDocumentIdentifier(fromLSPDictionary: textDocumentDict)
    else {
      return nil
    }
    self.init(textDocument: textDocument)
  }

  package init(textDocument: TextDocumentIdentifier) {
    self.sourcekitlsp_textDocument = textDocument
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.sourcekitlsp_textDocument.stringValue: sourcekitlsp_textDocument.encodeToLSPAny()
    ])
  }
}

extension CodeActionRequest {
  package func injectMetadata(toResponse response: CodeActionRequestResponse?) -> CodeActionRequestResponse? {
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    let metadataArgument = metadata.encodeToLSPAny()
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
  package var textDocument: TextDocumentIdentifier? {
    return metadata?.sourcekitlsp_textDocument
  }

  /// Optional metadata containing SourceKit-LSP information about this command.
  package var metadata: SourceKitLSPCommandMetadata? {
    guard case .dictionary(let dictionary)? = arguments?.last else {
      return nil
    }
    guard let metadata = SourceKitLSPCommandMetadata(fromLSPDictionary: dictionary) else {
      logger.error("failed to decode lsp metadata in executeCommand request")
      return nil
    }
    return metadata
  }

  /// Returns this Command's arguments without SourceKit-LSP's injected metadata, if it exists.
  package var argumentsWithoutSourceKitMetadata: [LSPAny]? {
    guard metadata != nil else {
      return arguments
    }
    return arguments?.dropLast()
  }
}
