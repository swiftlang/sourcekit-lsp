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

import LSPTestSupport
import LanguageServerProtocol
import SKSupport
import SKTestSupport
import SourceKitLSP
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
private func assertSingleFileRename(
  _ markedSource: String,
  newName: String,
  expected: String,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI.for(.swift)
  let positions = testClient.openDocument(markedSource, uri: uri)
  for marker in positions.allMarkers {
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

final class RenameTests: XCTestCase {
  func testRenameVariableBaseName() async throws {
    try await assertSingleFileRename(
      """
      let 1️⃣foo = 1
      print(2️⃣foo)
      """,
      newName: "bar",
      expected: """
        let bar = 1
        print(bar)
        """
    )
  }

  func testRenameFunctionBaseName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo() {}
      2️⃣foo()
      _ = 3️⃣foo
      """,
      newName: "bar()",
      expected: """
        func bar() {}
        bar()
        _ = bar
        """
    )
  }

  func testRenameFunctionParameter() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x: Int) {}
      2️⃣foo(x: 1)
      _ = 3️⃣foo(x:)
      _ = 4️⃣foo
      """,
      newName: "bar(y:)",
      expected: """
        func bar(y: Int) {}
        bar(y: 1)
        _ = bar(y:)
        _ = bar
        """
    )
  }

  func testSecondParameterNameIfMatches() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x y: Int) {}
      2️⃣foo(x: 1)
      _ = 3️⃣foo(x:)
      """,
      newName: "foo(y:)",
      expected: """
        func foo(y: Int) {}
        foo(y: 1)
        _ = foo(y:)
        """
    )
  }

  func testIntroduceLabel() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(_ y: Int) {}
      2️⃣foo(1)
      _ = 3️⃣foo(_:)
      """,
      newName: "foo(y:)",
      expected: """
        func foo(y: Int) {}
        foo(y: 1)
        _ = foo(y:)
        """
    )
  }

  func testRemoveLabel() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x: Int) {}
      2️⃣foo(x: 1)
      _ = 3️⃣foo(x:)
      """,
      newName: "foo(_:)",
      expected: """
        func foo(_ x: Int) {}
        foo(1)
        _ = foo(_:)
        """
    )
  }

  func testRemoveLabelWithExistingInternalName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x a: Int) {}
      2️⃣foo(x: 1)
      _ = 3️⃣foo(x:)
      """,
      newName: "foo(_:)",
      expected: """
        func foo(_ a: Int) {}
        foo(1)
        _ = foo(_:)
        """
    )
  }

  func testRenameSubscript() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣subscript(x x: Int) -> Int { x }
      }
      Foo()2️⃣[x: 1]
      """,
      newName: "subscript(y:)",
      expected: """
        struct Foo {
          subscript(y x: Int) -> Int { x }
        }
        Foo()[y: 1]
        """
    )
  }

  func testRemoveExternalLabelFromSubscript() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣subscript(x x: Int) -> Int { x }
      }
      Foo()2️⃣[x: 1]
      """,
      newName: "subscript(_:)",
      expected: """
        struct Foo {
          subscript(_ x: Int) -> Int { x }
        }
        Foo()[1]
        """
    )
  }

  func testIntroduceExternalLabelFromSubscript() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣subscript(x: Int) -> Int { x }
      }
      Foo()2️⃣[1]
      """,
      newName: "subscript(x:)",
      expected: """
        struct Foo {
          subscript(x x: Int) -> Int { x }
        }
        Foo()[x: 1]
        """
    )
  }

  func testIgnoreRenameSubscriptBaseName() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣subscript(x: Int) -> Int { x }
      }
      Foo()2️⃣[1]
      """,
      newName: "arrayAccess(x:)",
      expected: """
        struct Foo {
          subscript(x x: Int) -> Int { x }
        }
        Foo()[x: 1]
        """
    )
  }

  func testRenameInitializerLabels() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣init(x: Int) {}
      }
      Foo(x: 1)
      Foo.2️⃣init(x: 1)
      _ = Foo.3️⃣init(x:)
      """,
      newName: "init(y:)",
      expected: """
        struct Foo {
          init(y: Int) {}
        }
        Foo(y: 1)
        Foo.init(y: 1)
        _ = Foo.init(y:)
        """
    )
  }

  func testIgnoreRenameOfInitBaseName() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣init(x: Int) {}
      }
      Foo(x: 1)
      Foo.2️⃣init(x: 1)
      _ = Foo.3️⃣init(x:)
      """,
      newName: "create(y:)",
      expected: """
        struct Foo {
          init(y: Int) {}
        }
        Foo(y: 1)
        Foo.init(y: 1)
        _ = Foo.init(y:)
        """
    )
  }

  func testRenameMultipleParameters() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int, b: Int) {}
      2️⃣foo(a: 1, b: 1)
      _ = 3️⃣foo(a:b:)
      """,
      newName: "foo(x:y:)",
      expected: """
        func foo(x: Int, y: Int) {}
        foo(x: 1, y: 1)
        _ = foo(x:y:)
        """
    )
  }

  func testDontRenameParametersOmittedFromNewName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int, b: Int) {}
      2️⃣foo(a: 1, b: 1)
      _ = 3️⃣foo(a:b:)
      """,
      newName: "foo(x:)",
      expected: """
        func foo(x: Int, b: Int) {}
        foo(x: 1, b: 1)
        _ = foo(x:b:)
        """
    )
  }

  func testIgnoreAdditionalParametersInNewName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      2️⃣foo(a: 1)
      _ = 3️⃣foo(a:)
      """,
      newName: "foo(x:y:)",
      expected: """
        func foo(x: Int) {}
        foo(x: 1)
        _ = foo(x:)
        """
    )
  }

  func testOnlySpecifyBaseNameWhenRenamingFunction() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      2️⃣foo(a: 1)
      _ = 3️⃣foo(a:)
      """,
      newName: "bar",
      expected: """
        func bar(a: Int) {}
        bar(a: 1)
        _ = bar(a:)
        """
    )
  }

  func testIgnoreParametersInNewNameWhenRenamingVariable() async throws {
    try await assertSingleFileRename(
      """
      let 1️⃣foo = 1
      _ = 2️⃣foo
      """,
      newName: "bar(x:y:)",
      expected: """
        let bar = 1
        _ = bar
        """
    )
  }

  func testNewNameDoesntContainClosingParenthesis() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      2️⃣foo(a: 1)
      """,
      newName: "bar(x:",
      expected: """
        func bar(x: Int) {}
        bar(x: 1)
        """
    )
  }

  func testNewNameContainsTextAfterParenthesis() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      2️⃣foo(a: 1)
      """,
      newName: "bar(x:)other:",
      expected: """
        func bar(x: Int) {}
        bar(x: 1)
        """
    )
  }

  func testSpacesInNewParameterNames() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      2️⃣foo(a: 1)
      _ = foo(a:)
      """,
      newName: "bar ( x : )",
      expected: """
        func bar ( x : Int) {}
        bar ( x : 1)
        _ = bar ( x :)
        """
    )
  }

  func testRenameOperator() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {}
      func 1️⃣+(x: Foo, y: Foo) {}
      Foo() 2️⃣+ Foo()
      """,
      newName: "-",
      expected: """
        struct Foo {}
        func -(x: Foo, y: Foo) {}
        Foo() - Foo()
        """
    )
  }

  func testRenameParameterToEmptyName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x: Int) {}
      2️⃣foo(x: 1)
      """,
      newName: "bar(:)",
      expected: """
        func bar(_ x: Int) {}
        bar(1)
        """
    )
  }

  func testRenameInsidePoundSelector() async throws {
    #if !canImport(Darwin)
    throw XCTSkip("#selector in test case doesn't compile without Objective-C runtime.")
    #endif
    try await assertSingleFileRename(
      """
      import Foundation
      class Foo: NSObject {
        @objc public func 1️⃣bar(x: Int) {}
      }
      _ = #selector(Foo.2️⃣bar(x:))
      """,
      newName: "foo(y:)",
      expected: """
        import Foundation
        class Foo: NSObject {
          @objc public func foo(y: Int) {}
        }
        _ = #selector(Foo.foo(y:))
        """
    )
  }

  func testCrossFileSwiftRename() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "a.swift": """
        func 1️⃣foo2️⃣() {}
        """,
        "b.swift": """
        func test() {
          3️⃣foo4️⃣()
        }
        """,
      ],
      build: true
    )

    let (aUri, aPositions) = try ws.openDocument("a.swift")
    let response = try await ws.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(aUri), position: aPositions["1️⃣"], newName: "bar")
    )
    let changes = try XCTUnwrap(response?.changes)
    XCTAssertEqual(
      changes,
      [
        aUri: [TextEdit(range: aPositions["1️⃣"]..<aPositions["2️⃣"], newText: "bar")],
        try ws.uri(for: "b.swift"): [
          TextEdit(range: try ws.position(of: "3️⃣", in: "b.swift")..<ws.position(of: "4️⃣", in: "b.swift"), newText: "bar")
        ],
      ]
    )
  }

  func testSwiftCrossModuleRename() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣foo2️⃣(3️⃣argLabel4️⃣: Int) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          5️⃣foo6️⃣(7️⃣argLabel8️⃣: 1)
        }
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """,
      build: true
    )

    let expectedChanges = [
      try ws.uri(for: "LibA.swift"): [
        TextEdit(
          range: try ws.position(of: "1️⃣", in: "LibA.swift")..<ws.position(of: "2️⃣", in: "LibA.swift"),
          newText: "bar"
        ),
        TextEdit(
          range: try ws.position(of: "3️⃣", in: "LibA.swift")..<ws.position(of: "4️⃣", in: "LibA.swift"),
          newText: "new"
        ),
      ],
      try ws.uri(for: "LibB.swift"): [
        TextEdit(
          range: try ws.position(of: "5️⃣", in: "LibB.swift")..<ws.position(of: "6️⃣", in: "LibB.swift"),
          newText: "bar"
        ),
        TextEdit(
          range: try ws.position(of: "7️⃣", in: "LibB.swift")..<ws.position(of: "8️⃣", in: "LibB.swift"),
          newText: "new"
        ),
      ],
    ]

    let (aUri, aPositions) = try ws.openDocument("LibA.swift")

    let definitionResponse = try await ws.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(aUri), position: aPositions["1️⃣"], newName: "bar(new:)")
    )
    XCTAssertEqual(try XCTUnwrap(definitionResponse?.changes), expectedChanges)

    let (bUri, bPositions) = try ws.openDocument("LibB.swift")

    let callResponse = try await ws.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["5️⃣"], newName: "bar(new:)")
    )
    XCTAssertEqual(try XCTUnwrap(callResponse?.changes), expectedChanges)
  }

  func testTryIndexLocationsDontMatchInMemoryLocations() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "a.swift": """
        func 1️⃣foo2️⃣() {}
        """,
        "b.swift": """
        0️⃣func test() {
          foo()
        }
        """,
      ],
      build: true
    )

    // Modify b.swift so that the locations from the index no longer match the in-memory document.
    let (bUri, bPositions) = try ws.openDocument("b.swift")
    ws.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(bUri, version: 1),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(bPositions["0️⃣"]), text: "\n")]
      )
    )

    // We should notice that the locations from the index don't match the current state of b.swift and not include any
    // edits in b.swift
    let (aUri, aPositions) = try ws.openDocument("a.swift")
    let response = try await ws.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(aUri), position: aPositions["1️⃣"], newName: "bar")
    )
    let changes = try XCTUnwrap(response?.changes)
    XCTAssertEqual(
      changes,
      [aUri: [TextEdit(range: aPositions["1️⃣"]..<aPositions["2️⃣"], newText: "bar")]]
    )
  }

  func testTryIndexLocationsDontMatchInMemoryLocationsByLineColumnButNotOffset() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "a.swift": """
        func 1️⃣foo2️⃣() {}
        """,
        "b.swift": """
        0️⃣func test() {
          3️⃣foo4️⃣()
        }
        """,
      ],
      build: true
    )

    // Modify b.swift so that the locations from the index no longer match the in-memory document based on offsets but
    // without introducing new lines so that line/column references are still correct
    let (bUri, bPositions) = try ws.openDocument("b.swift")
    ws.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(bUri, version: 1),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(bPositions["0️⃣"]), text: "/* this is just a comment */")
        ]
      )
    )

    // Index and find-syntactic-rename ranges work based on line/column so we should still be able to match the location
    // of `foo` after the edit.
    let (aUri, aPositions) = try ws.openDocument("a.swift")
    let response = try await ws.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(aUri), position: aPositions["1️⃣"], newName: "bar")
    )
    let changes = try XCTUnwrap(response?.changes)
    XCTAssertEqual(
      changes,
      [
        aUri: [TextEdit(range: aPositions["1️⃣"]..<aPositions["2️⃣"], newText: "bar")],
        bUri: [TextEdit(range: bPositions["3️⃣"]..<bPositions["4️⃣"], newText: "bar")],
      ]
    )
  }
}
