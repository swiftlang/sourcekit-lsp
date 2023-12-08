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
  let response = try await testClient.send(
    RenameRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: positions["1️⃣"],
      newName: newName
    )
  )
  let edits = try XCTUnwrap(response?.changes?[uri], file: file, line: line)
  let source = extractMarkers(markedSource).textWithoutMarkers
  let renamed = apply(edits: edits, to: source)
  XCTAssertEqual(renamed, expected, file: file, line: line)
}

final class RenameTests: XCTestCase {
  func testRenameVariableBaseName() async throws {
    try await assertSingleFileRename(
      """
      let 1️⃣foo = 1
      print(foo)
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
      foo()
      """,
      newName: "bar()",
      expected: """
        func bar() {}
        bar()
        """
    )
  }

  func testRenameFunctionParameter() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x: Int) {}
      foo(x: 1)
      """,
      newName: "bar(y:)",
      expected: """
        func bar(y: Int) {}
        bar(y: 1)
        """
    )
  }

  func testSecondParameterNameIfMatches() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x y: Int) {}
      foo(x: 1)
      """,
      newName: "foo(y:)",
      expected: """
        func foo(y: Int) {}
        foo(y: 1)
        """
    )
  }

  func testIntroduceLabel() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(_ y: Int) {}
      foo(1)
      """,
      newName: "foo(y:)",
      expected: """
        func foo(y: Int) {}
        foo(y: 1)
        """
    )
  }

  func testRemoveLabel() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x: Int) {}
      foo(x: 1)
      """,
      newName: "foo(_:)",
      expected: """
        func foo(_ x: Int) {}
        foo(1)
        """
    )
  }

  func testRemoveLabelWithExistingInternalName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x a: Int) {}
      foo(x: 1)
      """,
      newName: "foo(_:)",
      expected: """
        func foo(_ a: Int) {}
        foo(1)
        """
    )
  }

  func testRenameSubscript() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {
        1️⃣subscript(x x: Int) -> Int { x }
      }
      Foo()[x: 1]
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
      Foo()[x: 1]
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
      Foo()[1]
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
      Foo()[1]
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
      """,
      newName: "init(y:)",
      expected: """
        struct Foo {
          init(y: Int) {}
        }
        Foo(y: 1)
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
      """,
      newName: "create(y:)",
      expected: """
        struct Foo {
          init(y: Int) {}
        }
        Foo(y: 1)
        """
    )
  }

  func testRenameCompoundFunctionName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      _ = foo(a:)
      """,
      newName: "foo(b:)",
      expected: """
        func foo(b: Int) {}
        _ = foo(b:)
        """
    )
  }

  func testRemoveLabelFromCompoundFunctionName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      _ = foo(a:)
      """,
      newName: "foo(_:)",
      expected: """
        func foo(_ a: Int) {}
        _ = foo(_:)
        """
    )
  }

  func testIntroduceLabelToCompoundFunctionName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(_ a: Int) {}
      _ = foo(_:)
      """,
      newName: "foo(a:)",
      expected: """
        func foo(a: Int) {}
        _ = foo(a:)
        """
    )
  }

  func testRenameFromReference() async throws {
    try await assertSingleFileRename(
      """
      func foo(_ a: Int) {}
      _ = 1️⃣foo(_:)
      """,
      newName: "foo(a:)",
      expected: """
        func foo(a: Int) {}
        _ = foo(a:)
        """
    )
  }

  func testRenameMultipleParameters() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int, b: Int) {}
      foo(a: 1, b: 1)
      """,
      newName: "foo(x:y:)",
      expected: """
        func foo(x: Int, y: Int) {}
        foo(x: 1, y: 1)
        """
    )
  }

  func testDontRenameParametersOmittedFromNewName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int, b: Int) {}
      foo(a: 1, b: 1)
      """,
      newName: "foo(x:)",
      expected: """
        func foo(x: Int, b: Int) {}
        foo(x: 1, b: 1)
        """
    )
  }

  func testIgnoreAdditionalParametersInNewName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      foo(a: 1)
      """,
      newName: "foo(x:y:)",
      expected: """
        func foo(x: Int) {}
        foo(x: 1)
        """
    )
  }

  func testOnlySpecifyBaseNameWhenRenamingFunction() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      foo(a: 1)
      """,
      newName: "bar",
      expected: """
        func bar(a: Int) {}
        bar(a: 1)
        """
    )
  }

  func testIgnoreParametersInNewNameWhenRenamingVariable() async throws {
    try await assertSingleFileRename(
      """
      let 1️⃣foo = 1
      _ = foo
      """,
      newName: "bar(x:y:)",
      expected: """
        let bar = 1
        _ = bar
        """
    )
  }

  func testErrorIfNewNameDoesntContainClosingParenthesis() async throws {
    // FIXME: syntactic rename does not support in-memory files... It should
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      func 1️⃣foo(a: Int) {}
      foo(a: 1)
      """
    )
    let request = RenameRequest(
      textDocument: TextDocumentIdentifier(ws.fileURI),
      position: ws.positions["1️⃣"],
      newName: "bar(x:"
    )
    await assertThrowsError(try await ws.testClient.send(request))
  }

  func testErrorIfNewNameContainsTextAfterParenthesis() async throws {
    // FIXME: syntactic rename does not support in-memory files... It should
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      func 1️⃣foo(a: Int) {}
      foo(a: 1)
      """
    )
    let request = RenameRequest(
      textDocument: TextDocumentIdentifier(ws.fileURI),
      position: ws.positions["1️⃣"],
      newName: "bar(x:)other:"
    )
    await assertThrowsError(try await ws.testClient.send(request))
  }

  func testSpacesInNewParameterNames() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(a: Int) {}
      foo(a: 1)
      """,
      newName: "bar ( x : )",
      expected: """
        func bar ( x : Int) {}
        bar ( x : 1)
        """
    )
  }

  func testRenameOperator() async throws {
    try await assertSingleFileRename(
      """
      struct Foo {}
      func 1️⃣+(x: Foo, y: Foo) {}
      Foo() + Foo()
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
      foo(x: 1)
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
      _ = #selector(Foo.bar(x:))
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
}
