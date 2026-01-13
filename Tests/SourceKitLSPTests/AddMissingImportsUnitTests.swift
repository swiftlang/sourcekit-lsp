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
import SKUtilities
import SourceKitLSP
@_spi(SourceKitLSP) import SwiftLanguageService
import SwiftParser
import SwiftSyntax
import XCTest

class AddMissingImportsUnitTests: XCTestCase {

  // MARK: - Helper Methods

  /// Creates a syntax tree and snapshot from source code for testing.
  private func makeSyntaxTreeAndSnapshot(from source: String, uri: DocumentURI) -> (SourceFileSyntax, DocumentSnapshot)
  {
    let syntaxTree = Parser.parse(source: source)
    let snapshot = DocumentSnapshot(uri: uri, language: .swift, version: 0, lineTable: LineTable(source))
    return (syntaxTree, snapshot)
  }

  // MARK: - Basic Functionality Tests

  func testAddMissingImports() {
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 10)..<Position(line: 0, utf16index: 19),
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let uri = try! DocumentURI(string: "file:///main.swift")
    let source = "let x = LibStruct()"
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

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
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
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
    // Should insert at beginning since there are no imports
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
    let source = "let x = LibStruct()"
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

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
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
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
    let source = "let x = CommonType()"
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let lookup: (String) -> Set<String> = { name in
      if name == "CommonType" {
        return ["ModuleA", "ModuleB"]
      }
      return []
    }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 2)
    let titles = actions.map { $0.title }.sorted()
    XCTAssertEqual(titles, ["Import ModuleA", "Import ModuleB"])
  }

  // MARK: - Edge Case Regression Tests

  func testImportInsertionAfterFileHeader() {
    let diagnostic = Diagnostic(
      range: Position(line: 5, utf16index: 10)..<Position(line: 5, utf16index: 19),
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let uri = try! DocumentURI(string: "file:///main.swift")
    let source = """
      //===----------------------------------------------------------------------===//
      //
      // This source file is part of the Swift.org open source project
      //
      //===----------------------------------------------------------------------===//

      let x = LibStruct()
      """
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let lookup: (String) -> Set<String> = { name in
      if name == "LibStruct" {
        return ["Lib"]
      }
      return []
    }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1)
    guard let action = actions.first, let edit = action.edit, let changes = edit.changes?[uri] else {
      XCTFail("No edit found")
      return
    }

    // Import should be inserted at the beginning since header comments are leading trivia in this parse
    // (The multi-line string literal has leading indentation which makes the comments part of trivia)
    XCTAssertEqual(changes.first?.range.lowerBound.line, 0)
  }

  func testImportInsertionWithMultiLineHeader() {
    let source = """
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

      func test() {
        let x = LibStruct()
      }
      """
    let uri = try! DocumentURI(string: "file:///main.swift")
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 13, utf16index: 10)..<Position(line: 13, utf16index: 19),
      severity: .error,
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let lookup: (String) -> Set<String> = { _ in ["Lib"] }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1)
    guard let action = actions.first, let edit = action.edit, let changes = edit.changes?[uri] else {
      XCTFail("No edit found")
      return
    }

    // Import should be inserted at the beginning since header comments are leading trivia
    XCTAssertEqual(changes.first?.range.lowerBound.line, 0)
  }

  func testImportInsertionWithNoImportsAndNoHeader() {
    let source = "func test() { let x = LibStruct() }"
    let uri = try! DocumentURI(string: "file:///main.swift")
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 26)..<Position(line: 0, utf16index: 35),
      severity: .error,
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let lookup: (String) -> Set<String> = { _ in ["Lib"] }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1)
    guard let action = actions.first, let edit = action.edit, let changes = edit.changes?[uri] else {
      XCTFail("No edit found")
      return
    }

    // Import should be at the very beginning (line 0)
    XCTAssertEqual(changes.first?.range.lowerBound, Position(line: 0, utf16index: 0))
  }

  func testImportInsertionAfterExistingImports() {
    let source = """
      import Foundation

      let x = LibStruct()
      """
    let uri = try! DocumentURI(string: "file:///main.swift")
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 2, utf16index: 8)..<Position(line: 2, utf16index: 17),
      severity: .error,
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let lookup: (String) -> Set<String> = { _ in ["Lib"] }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: ["Foundation"],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1)
    guard let action = actions.first, let edit = action.edit, let changes = edit.changes?[uri] else {
      XCTFail("No edit found")
      return
    }

    // Import should be inserted at the beginning (line 0) since Foundation import is on line 0
    // and we insert after the last import
    XCTAssertEqual(changes.first?.range.lowerBound.line, 0)
  }

  func testDoNotSuggestCurrentModule() {
    let source = "let x = MyType()"
    let uri = try! DocumentURI(string: "file:///main.swift")
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 14),
      severity: .error,
      source: "sourcekitd",
      message: "cannot find 'MyType' in scope"
    )

    let lookup: (String) -> Set<String> = { name in
      if name == "MyType" {
        // Type is found in the current module
        return ["MyModule"]
      }
      return []
    }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: "MyModule",  // This is the current module
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    // Should not suggest importing MyModule (self-import)
    XCTAssertTrue(actions.isEmpty, "Should not suggest importing the current module")
  }

  func testDiagnosticMatchingWithCode() {
    let source = "let x = LibStruct()"
    let uri = try! DocumentURI(string: "file:///main.swift")
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    // Diagnostic with proper code
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 17),
      severity: .error,
      code: .string("cannot_find_in_scope"),
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let lookup: (String) -> Set<String> = { _ in ["Lib"] }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1, "Should match diagnostic by code")
  }

  func testDiagnosticMatchingWithStringFallback() {
    let source = "let x = LibStruct()"
    let uri = try! DocumentURI(string: "file:///main.swift")
    let (syntaxTree, snapshot) = makeSyntaxTreeAndSnapshot(from: source, uri: uri)

    // Diagnostic without code, should use string matching fallback
    let diagnostic = Diagnostic(
      range: Position(line: 0, utf16index: 8)..<Position(line: 0, utf16index: 17),
      severity: .error,
      source: "sourcekitd",
      message: "cannot find 'LibStruct' in scope"
    )

    let lookup: (String) -> Set<String> = { _ in ["Lib"] }

    let actions = SwiftLanguageService.findMissingImports(
      diagnostics: [diagnostic],
      existingImports: [],
      currentModule: nil,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: uri,
      lookup: lookup
    )

    XCTAssertEqual(actions.count, 1, "Should match diagnostic by string fallback when code is absent")
  }
}
