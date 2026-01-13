//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
@_spi(SourceKitLSP) import SwiftLanguageService
import XCTest

class AddMissingImportsUnitTests: XCTestCase {

  func testAddMissingImports() {
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 10)..<Position(line: 0, utf16index: 19),
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let uri = try! DocumentURI(string: "file:///main.swift")

    // Mock lookup: 'LibStruct' is defined in 'Lib'
    let lookup: (String) -> Set<String> = { name in
      if name == "LibStruct" {
        return ["Lib"]
      }
      return []
    }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1)

    guard let action = actions.first else { return }
    XCTAssertEqual(action.title, "Import Lib")

    guard let edit = action.edit, let changes = edit.changes?[uri] else {
      XCTFail("No edit found")
      return
    }

    XCTAssertEqual(changes.count, 1)
    XCTAssertEqual(changes.first?.newText, "import Lib\n")
    XCTAssertEqual(changes.first?.range, Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0))
  }

  func testDoNotImportIfAlreadyImported() {
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 10)..<Position(line: 0, utf16index: 19),
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let uri = try! DocumentURI(string: "file:///main.swift")

    let lookup: (String) -> Set<String> = { name in
      if name == "LibStruct" {
        return ["Lib"]
      }
      return []
    }

    // Lib IS already imported
    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: ["Lib"],
      uri: uri,
      lookup: lookup
    )

    XCTAssertTrue(actions.isEmpty, "Should not suggest importing Lib if it is already imported")
  }

  func testMultipleCandidates() {
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 5),
      severity: .error,
      source: "sourcekitd",
      message: "cannot find 'CommonType' in scope"
    )
    let uri = try! DocumentURI(string: "file:///main.swift")

    let lookup: (String) -> Set<String> = { name in
      if name == "CommonType" {
        return ["ModuleA", "ModuleB"]
      }
      return []
    }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 2)
    let titles = actions.map { $0.title }.sorted()
    XCTAssertEqual(titles, ["Import ModuleA", "Import ModuleB"])
  }
}
