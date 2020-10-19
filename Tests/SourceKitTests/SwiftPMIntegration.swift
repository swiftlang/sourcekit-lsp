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
import XCTest

final class SwiftPMIntegrationTests: XCTestCase {

  func testSwiftPMIntegration() throws {
    guard let ws = try staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage") else { return }
    try ws.buildAndIndex()

    let call = ws.testLoc("Lib.foo:call")
    let def = ws.testLoc("Lib.foo:def")
    try ws.openDocument(call.url, language: .swift)
    let refs = try ws.sk.sendSync(ReferencesRequest(textDocument: call.docIdentifier, position: call.position, context: ReferencesContext(includeDeclaration: true)))

    XCTAssertEqual(Set(refs), [
      Location(call),
      Location(def),
    ])

    let completions = try ws.sk.sendSync(CompletionRequest(textDocument: call.docIdentifier, position: call.position))

    XCTAssertEqual(completions.items, [
      CompletionItem(
        label: "foo()",
        kind: .method,
        detail: "Void",
        sortText: nil,
        filterText: "foo()",
        textEdit: TextEdit(range: Position(line: 2, utf16index: 24)..<Position(line: 2, utf16index: 24), newText: "foo()"),
        insertText: "foo()",
        insertTextFormat: .plain,
        deprecated: false),
      CompletionItem(
        label: "self",
        kind: .keyword,
        detail: "Lib",
        sortText: nil,
        filterText: "self",
        textEdit: TextEdit(range: Position(line: 2, utf16index: 24)..<Position(line: 2, utf16index: 24), newText: "self"),
        insertText: "self",
        insertTextFormat: .plain,
        deprecated: false),
    ])
  }
}
