//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import XCTest
import SKCore
import TSCBasic

final class CompilationDatabaseTests: XCTestCase {
  func testModifyCompilationDatabase() async throws {
    let ws = try await mutableSourceKitTibsTestWorkspace(name: "ClangCrashRecoveryBuildSettings")!
    let loc = ws.testLoc("loc")

    try ws.openDocument(loc.url, language: .cpp)

    // Do a sanity check and verify that we get the expected result from a hover response before modifing the compile commands.

    let highlightRequest = DocumentHighlightRequest(textDocument: loc.docIdentifier, position: Position(line: 9, utf16index: 3))
    let preChangeHighlightResponse = try ws.sk.sendSync(highlightRequest)
    XCTAssertEqual(preChangeHighlightResponse, [
      DocumentHighlight(range: Position(line: 3, utf16index: 5)..<Position(line: 3, utf16index: 8), kind: .text),
      DocumentHighlight(range: Position(line: 9, utf16index: 2)..<Position(line: 9, utf16index: 5), kind: .text)
    ])

    // Remove -DFOO from the compile commands.

    let compilationDatabaseUrl = ws.builder.buildRoot.appendingPathComponent("compile_commands.json")

    _ = try ws.sources.edit({ builder in
      let compilationDatabase = try JSONCompilationDatabase(file: AbsolutePath(validating: compilationDatabaseUrl.path))
      let newCommands = compilationDatabase.allCommands.map { (command: CompilationDatabaseCompileCommand) -> CompilationDatabaseCompileCommand in
        var command = command
        command.commandLine.removeAll(where: { $0 == "-DFOO" })
        return command
      }
      let newCompilationDatabase = JSONCompilationDatabase(newCommands)
      let newCompilationDatabaseData = try JSONEncoder().encode(newCompilationDatabase)
      let newCompilationDatabaseStr = String(data: newCompilationDatabaseData, encoding: .utf8)!
      builder.write(newCompilationDatabaseStr, to: compilationDatabaseUrl)
    })

    ws.sk.send(DidChangeWatchedFilesNotification(changes: [
      FileEvent(uri: DocumentURI(compilationDatabaseUrl), type: .changed)
    ]))

    // DocumentHighlight should now point to the definition in the `#else` block.

    let expectedPostEditHighlight = [
      DocumentHighlight(range: Position(line: 5, utf16index: 5)..<Position(line: 5, utf16index: 8), kind: .text),
      DocumentHighlight(range: Position(line: 9, utf16index: 2)..<Position(line: 9, utf16index: 5), kind: .text)
    ]

    var didReceiveCorrectHighlight = false

    // Updating the build settings takes a few seconds.
    // Send code completion requests every second until we receive correct results.
    for _ in 0..<30 {
      let postChangeHighlightResponse = try ws.sk.sendSync(highlightRequest)

      if postChangeHighlightResponse == expectedPostEditHighlight {
        didReceiveCorrectHighlight = true
        break
      }
      try await Task.sleep(for: .seconds(1))
    }

    XCTAssert(didReceiveCorrectHighlight)
  }
}
