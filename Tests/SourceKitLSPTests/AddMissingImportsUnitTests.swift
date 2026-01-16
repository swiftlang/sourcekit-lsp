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
    let markedSource = "let x = 1️⃣LibStruct()"
    let (positions, source) = extractMarkers(markedSource)
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Range(snapshot.position(of: positions["1️⃣"]!)),
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
    let result = apply(edits: edits, to: source)
    XCTAssertEqual(result, "import Lib\nlet x = LibStruct()")
  }

  func testDoNotImportIfAlreadyImported() {
    let source = "let x = LibStruct()"
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 17),
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
    let source = "let x = CommonType()"
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 18),
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
    let titles = actions.map { $0.title }.sorted()
    XCTAssertEqual(titles, ["Import ModuleA", "Import ModuleB"])
  }

  func testImportInsertionAfterExistingImports() throws {
    let source = """
      import Foundation

      let x = LibStruct()
      """
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 2, utf16index: 8)..<Position(line: 2, utf16index: 17),
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
    let result = apply(edits: edits, to: source)
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
    let source = "let x = MyType()"
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 14),
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
    let source = "let x = LibStruct()"
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    // Diagnostic with proper code
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 17),
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
  }

  func testDiagnosticMatchingWithTypeCode() throws {
    let source = "let x: LibStruct = LibStruct()"
    let uri = DocumentURI(for: .swift)
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    // Diagnostic with 'cannot_find_type_in_scope' code (used for types in type positions)
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 7)..<Position(line: 0, utf16index: 16),
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
  }
}
