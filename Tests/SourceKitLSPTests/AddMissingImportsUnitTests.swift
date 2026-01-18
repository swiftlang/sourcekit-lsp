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
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
import SKTestSupport
import SKUtilities
import SourceKitLSP
import SwiftExtensions
@_spi(SourceKitLSP) import SwiftLanguageService
import SwiftParser
import SwiftSyntax
import XCTest

class AddMissingImportsUnitTests: XCTestCase {

  /// Creates a syntax tree and snapshot from source code for testing.
  private func makeSyntaxTreeAndSnapshot(
    from source: String,
    uri: DocumentURI
  ) -> (SourceFileSyntax, DocumentSnapshot) {
    let syntaxTree = Parser.parse(source: source)
    let snapshot = DocumentSnapshot(uri: uri, language: .swift, version: 0, lineTable: LineTable(source))
    return (syntaxTree, snapshot)
  }

  func testAddMissingImports() throws {
    let source = "let x = 1️⃣LibStruct()2️⃣"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let action = try XCTUnwrap(
      SwiftLanguageService.findMissingImports(
        diagnostics: [diagnostic],
        existingImports: [],
        currentModule: nil,
        syntaxTree: syntaxTree,
        snapshot: snapshot,
        uri: uri
      ) { _ in ["Lib"] }.only
    )

    XCTAssertEqual(action.title, "Import Lib")

    let edits = try XCTUnwrap(action.edit?.changes?[uri])
    let result = apply(edits: edits, to: text)
    XCTAssertEqual(result, "import Lib\nlet x = LibStruct()")
  }

  func testDoNotImportIfAlreadyImported() {
    let source = "let x = 1️⃣LibStruct()2️⃣"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    // Lib IS already imported
    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: ["Lib"],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri
    ) { _ in ["Lib"] }

    XCTAssertTrue(actions.isEmpty, "Should not suggest importing Lib if it is already imported")
  }

  func testMultipleCandidates() throws {
    let source = "let x = 1️⃣CommonType()2️⃣"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'CommonType' in scope"
    )

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri
    ) { _ in ["ModuleA", "ModuleB"] }

    XCTAssertEqual(actions.count, 2)
    let sortedActions = actions.sorted(by: { $0.title < $1.title })
    XCTAssertEqual(sortedActions.map { $0.title }, ["Import ModuleA", "Import ModuleB"])

    for (action, module) in zip(sortedActions, ["ModuleA", "ModuleB"]) {
      let edits = try XCTUnwrap(action.edit?.changes?[uri])
      let result = apply(edits: edits, to: text)
      XCTAssertEqual(result, "import \(module)\nlet x = CommonType()")
    }
  }

  func testImportInsertionAfterFileHeader() throws {
    let source = """
      //===----------------------------------------------------------------------===//
      //
      // This source file is part of the Swift.org open source project
      //
      //===----------------------------------------------------------------------===//

      1️⃣let x = LibStruct()2️⃣
      """
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let action = try XCTUnwrap(
      SwiftLanguageService.findMissingImports(
        diagnostics: [diagnostic],
        existingImports: [],
        currentModule: nil,
        syntaxTree: syntaxTree,
        snapshot: snapshot,
        uri: uri
      ) { _ in ["Lib"] }.only
    )

    let edits = try XCTUnwrap(action.edit?.changes?[uri])
    let result = apply(edits: edits, to: text)
    XCTAssertEqual(
      result,
      """
      //===----------------------------------------------------------------------===//
      //
      // This source file is part of the Swift.org open source project
      //
      //===----------------------------------------------------------------------===//

      import Lib
      let x = LibStruct()
      """
    )
  }

  func testImportInsertionAfterExistingImports() throws {
    let source = """
      import Foundation

      let x = 1️⃣LibStruct()2️⃣
      """
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)
    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let action = try XCTUnwrap(
      SwiftLanguageService.findMissingImports(
        diagnostics: [diagnostic],
        existingImports: ["Foundation"],
        currentModule: nil,
        syntaxTree: syntaxTree,
        snapshot: snapshot,
        uri: uri
      ) { _ in ["Lib"] }.only
    )

    let edits = try XCTUnwrap(action.edit?.changes?[uri])
    let result = apply(edits: edits, to: text)
    XCTAssertEqual(
      result,
      """
      import Foundation
      import Lib

      let x = LibStruct()
      """
    )
  }

  func testDoNotSuggestCurrentModule() {
    let source = "let x = 1️⃣MyType()2️⃣"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'MyType' in scope"
    )

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: "MyModule",  // This is the current module
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri
    ) { _ in ["MyModule"] }

    // Should not suggest importing MyModule (self-import)
    XCTAssertTrue(actions.isEmpty, "Should not suggest importing the current module")
  }

  func testDiagnosticMatchingWithCode() throws {
    let source = "let x = 1️⃣LibStruct()2️⃣"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    // Diagnostic with proper code
    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let action = try XCTUnwrap(
      SwiftLanguageService.findMissingImports(
        diagnostics: [diagnostic],
        existingImports: [],
        currentModule: nil,
        syntaxTree: syntaxTree,
        snapshot: snapshot,
        uri: uri
      ) { _ in ["Lib"] }.only
    )

    XCTAssertEqual(action.title, "Import Lib")
    let edits = try XCTUnwrap(action.edit?.changes?[uri])
    let result = apply(edits: edits, to: text)
    XCTAssertEqual(result, "import Lib\nlet x = LibStruct()")
  }

  func testDiagnosticMatchingWithTypeCode() throws {
    let source = "let x: 1️⃣LibStruct2️⃣ = LibStruct()"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    // Diagnostic with 'cannot_find_type_in_scope' code (used for types in type positions)
    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: .string("cannot_find_type_in_scope"),
      source: "sourcekitd",
      message: "cannot find type 'LibStruct' in scope"
    )

    let action = try XCTUnwrap(
      SwiftLanguageService.findMissingImports(
        diagnostics: [diagnostic],
        existingImports: [],
        currentModule: nil,
        syntaxTree: syntaxTree,
        snapshot: snapshot,
        uri: uri
      ) { _ in ["Lib"] }.only
    )

    XCTAssertEqual(action.title, "Import Lib")
    let edits = try XCTUnwrap(action.edit?.changes?[uri])
    let result = apply(edits: edits, to: text)
    XCTAssertEqual(result, "import Lib\nlet x: LibStruct = LibStruct()")
  }

  func testDiagnosticMatchingWithNilCode() {
    let source = "let x = 1️⃣LibStruct()2️⃣"
    let (positions, text) = DocumentPositions.extract(from: source)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: text, uri: uri)

    // Diagnostic with nil code - should NOT produce any code actions
    // (we now require proper diagnostic codes from SourceKit)
    let diagnostic = Diagnostic(
      range: positions["1️⃣"]..<positions["2️⃣"],
      severity: .error,
      code: nil,
      source: "sourcekitd",
      message: "Cannot find 'LibStruct' in scope"
    )

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri
    ) { _ in ["Lib"] }

    XCTAssertTrue(actions.isEmpty, "Diagnostics without codes should not produce code actions")
  }
}
