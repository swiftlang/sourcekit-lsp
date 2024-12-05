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
import SKTestSupport
import SourceKitLSP
import XCTest

final class DocumentationLanguageServiceTests: XCTestCase {
  func testHandlesMarkdownFiles() async throws {
    try await assertHandles(language: .markdown)
  }

  func testHandlesTutorialFiles() async throws {
    try await assertHandles(language: .tutorial)
  }
}

fileprivate func assertHandles(language: Language) async throws {
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: language)
  testClient.openDocument("", uri: uri)

  // The DocumentationLanguageService doesn't do much right now except to enable handling `*.md`
  // and `*.tutorial` files for the purposes of fulfilling documentation requests. We'll just
  // issue a completion request here to make sure that an empty list is returned and that
  // SourceKit-LSP does not respond with an error on requests for Markdown and Tutorial files.
  let completions = try await testClient.send(
    CompletionRequest(textDocument: .init(uri), position: .init(line: 0, utf16index: 0))
  )
  XCTAssertEqual(completions, .init(isIncomplete: false, items: []))
}
