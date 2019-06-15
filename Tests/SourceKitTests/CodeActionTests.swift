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

import LanguageServerProtocol
import SKSupport
import SKTestSupport
import XCTest

@testable import SourceKit

final class CodeActionTests: XCTestCase {
  func testCodeActionResponseLegacySupport() {
    let command = Command(title: "Title", command: "Command", arguments: [1,"f",2.2])
    let codeAction = CodeAction(title: "1")
    let codeAction2 = CodeAction(title: "2", command: command)

    var capabilities: TextDocumentClientCapabilities.CodeAction
    var capabilityJson: String
    var data: Data
    var response: CodeActionRequestResponse
    capabilityJson =
    """
     {
       "dynamicRegistration": true,
       "codeActionLiteralSupport" : {
         "codeActionKind": {
           "valueSet": []
         }
       }
     }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)
    response = .init(codeActions: [codeAction, codeAction2], clientCapabilities: capabilities)
    let actions = try! JSONDecoder().decode([CodeAction].self, from: JSONEncoder().encode(response))
    XCTAssertEqual(actions, [codeAction, codeAction2])

    capabilityJson =
    """
    {
      "dynamicRegistration": true
    }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)
    response = .init(codeActions: [codeAction, codeAction2], clientCapabilities: capabilities)
    let commands = try! JSONDecoder().decode([Command].self, from: JSONEncoder().encode(response))
    XCTAssertEqual(commands, [command])
  }

  func testCodeActionResponseRespectsSupportedKinds() {
    let unspecifiedAction = CodeAction(title: "Unspecified")
    let refactorAction = CodeAction(title: "Refactor", kind: .refactor)
    let quickfixAction = CodeAction(title: "Quickfix", kind: .quickFix)
    let actions = [unspecifiedAction, refactorAction, quickfixAction]

    var capabilities: TextDocumentClientCapabilities.CodeAction
    var capabilityJson: String
    var data: Data
    var response: CodeActionRequestResponse
    capabilityJson =
    """
    {
      "dynamicRegistration": true,
      "codeActionLiteralSupport" : {
        "codeActionKind": {
          "valueSet": ["refactor"]
        }
      }
    }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)

    response = .init(codeActions: actions, clientCapabilities: capabilities)
    XCTAssertEqual(response.codeActions, [unspecifiedAction, refactorAction])

    capabilityJson =
    """
    {
      "dynamicRegistration": true,
      "codeActionLiteralSupport" : {
        "codeActionKind": {
          "valueSet": []
        }
      }
    }
    """
    data = capabilityJson.data(using: .utf8)!
    capabilities = try! JSONDecoder().decode(TextDocumentClientCapabilities.CodeAction.self,
                                             from: data)

    response = .init(codeActions: actions, clientCapabilities: capabilities)
    XCTAssertEqual(response.codeActions, [unspecifiedAction])
  }
}
