//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
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

private func apply(edits: [TextEdit], to source: String) -> String {
  var lineTable = LineTable(source)
  let edits = edits.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
  for edit in edits.reversed() {
    lineTable.replace(
      fromLine: edit.range.lowerBound.line,
      utf16Offset: edit.range.lowerBound.utf16index,
      toLine: edit.range.upperBound.line,
      utf16Offset: edit.range.upperBound.utf16index,
      with: edit.newText
    )
  }
  return lineTable.content
}

/// Perform a rename request at every location marker in `markedSource`, renaming it to `newName`.
/// Test that applying the edits returned from the requests always result in `expected`.
func assertSingleFileRename(
  _ markedSource: String,
  language: Language = .swift,
  newName: String,
  expectedPrepareRenamePlaceholder: String,
  expected: String,
  testName: String = #function,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  try await SkipUnless.sourcekitdSupportsRename()
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: language, testName: testName)
  let positions = testClient.openDocument(markedSource, uri: uri, language: language)
  guard !positions.allMarkers.isEmpty else {
    XCTFail("Test case did not contain any markers at which to invoke the rename", file: file, line: line)
    return
  }
  for marker in positions.allMarkers {
    let position = positions[marker]
    let prepareRenameResponse = try await testClient.send(
      PrepareRenameRequest(textDocument: TextDocumentIdentifier(uri), position: position)
    )
    if let prepareRenameResponse {
      XCTAssertEqual(
        prepareRenameResponse.placeholder,
        expectedPrepareRenamePlaceholder,
        "Prepare rename placeholder does not match while performing rename at \(marker)",
        file: file,
        line: line
      )
      // VS Code considers the upper bound of a range as part of the identifier so both `contains` and equality in
      // `upperBound` are fine.
      XCTAssert(
        prepareRenameResponse.range.contains(position) || prepareRenameResponse.range.upperBound == position,
        "Prepare rename range \(prepareRenameResponse.range) does not contain rename position \(position)",
        file: file,
        line: line
      )
    } else {
      XCTFail("Expected non-nil prepareRename response", file: file, line: line)
    }

    let response = try await testClient.send(
      RenameRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions[marker],
        newName: newName
      )
    )
    let edits = try XCTUnwrap(response?.changes?[uri], "while performing rename at \(marker)", file: file, line: line)
    let source = extractMarkers(markedSource).textWithoutMarkers
    let renamed = apply(edits: edits, to: source)
    XCTAssertEqual(renamed, expected, "while performing rename at \(marker)", file: file, line: line)
  }
}

/// Assert that applying changes to `originalFiles` results in `expected`.
///
/// Upon failure, `message` is added to the XCTest failure messages to provide context which rename failed.
func assertRenamedSourceMatches(
  originalFiles: [RelativeFileLocation: String],
  changes: [DocumentURI: [TextEdit]],
  expected: [RelativeFileLocation: String],
  in ws: MultiFileTestProject,
  message: String,
  testName: String = #function,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  for (expectedFileLocation, expectedRenamed) in expected {
    let originalMarkedSource = try XCTUnwrap(
      originalFiles[expectedFileLocation],
      "No original source for \(expectedFileLocation.fileName) specified; \(message)",
      file: file,
      line: line
    )
    let originalSource = extractMarkers(originalMarkedSource).textWithoutMarkers
    let edits = changes[try ws.uri(for: expectedFileLocation.fileName)] ?? []
    let renamed = apply(edits: edits, to: originalSource)
    XCTAssertEqual(
      renamed,
      expectedRenamed,
      "applying edits did not match expected renamed source for \(expectedFileLocation.fileName); \(message)",
      file: file,
      line: line
    )
  }
}

/// Perform a rename request at every location marker except 0️⃣ in `files`, renaming it to `newName`. The location
/// marker 0️⃣ is intended to be used as an anchor for `preRenameActions`.
///
/// Test that applying the edits returned from the requests always result in `expected`.
///
/// `preRenameActions` is executed after opening the workspace but before performing the rename. This allows a workspace
/// to be placed in a state where there are in-memory changes that haven't been written to disk yet.
func assertMultiFileRename(
  files: [RelativeFileLocation: String],
  headerFileLanguage: Language? = nil,
  newName: String,
  expectedPrepareRenamePlaceholder: String,
  expected: [RelativeFileLocation: String],
  manifest: String = SwiftPMTestProject.defaultPackageManifest,
  preRenameActions: (SwiftPMTestProject) throws -> Void = { _ in },
  testName: String = #function,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  try await SkipUnless.sourcekitdSupportsRename()
  let project = try await SwiftPMTestProject(
    files: files,
    manifest: manifest,
    enableBackgroundIndexing: true,
    testName: testName
  )
  try preRenameActions(project)
  for (fileLocation, markedSource) in files.sorted(by: { $0.key.fileName < $1.key.fileName }) {
    let markers = extractMarkers(markedSource).markers.keys.sorted().filter { $0 != "0️⃣" }
    if markers.isEmpty {
      continue
    }
    let (uri, positions) = try project.openDocument(
      fileLocation.fileName,
      language: fileLocation.fileName.hasSuffix(".h") ? headerFileLanguage : nil
    )
    defer {
      project.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(uri)))
    }
    for marker in markers {
      let prepareRenameResponse = try await project.testClient.send(
        PrepareRenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions[marker])
      )
      XCTAssertEqual(
        prepareRenameResponse?.placeholder,
        expectedPrepareRenamePlaceholder,
        "Prepare rename placeholder does not match while performing rename at \(marker)",
        file: file,
        line: line
      )

      let response = try await project.testClient.send(
        RenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions[marker], newName: newName)
      )
      let changes = try XCTUnwrap(response?.changes, "Did not receive any edits", file: file, line: line)
      try assertRenamedSourceMatches(
        originalFiles: files,
        changes: changes,
        expected: expected,
        in: project,
        message: "while performing rename at \(marker)",
        file: file,
        line: line
      )
    }
  }
}
