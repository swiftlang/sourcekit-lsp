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

import enum PackageLoading.Platform

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
  language: Language? = nil,
  newName: String,
  expected: String,
  testName: String = #function,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  try await SkipUnless.sourcekitdSupportsRename()
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI.for(.swift, testName: testName)
  let positions = testClient.openDocument(markedSource, uri: uri, language: language)
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

/// Assert that applying changes to `originalFiles` results in `expected`.
///
/// Upon failure, `message` is added to the XCTest failure messages to provide context which rename failed.
private func assertRenamedSourceMatches(
  originalFiles: [RelativeFileLocation: String],
  changes: [DocumentURI: [TextEdit]],
  expected: [RelativeFileLocation: String],
  in ws: MultiFileTestWorkspace,
  message: String,
  testName: String = #function,
  file: StaticString = #file,
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
private func assertMultiFileRename(
  files: [RelativeFileLocation: String],
  headerFileLanguage: Language? = nil,
  newName: String,
  expectedPrepareRenamePlaceholder: String,
  expected: [RelativeFileLocation: String],
  manifest: String = SwiftPMTestWorkspace.defaultPackageManifest,
  preRenameActions: (SwiftPMTestWorkspace) throws -> Void = { _ in },
  testName: String = #function,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  try await SkipUnless.sourcekitdSupportsRename()
  let ws = try await SwiftPMTestWorkspace(
    files: files,
    manifest: manifest,
    build: true,
    testName: testName
  )
  try preRenameActions(ws)
  for (fileLocation, markedSource) in files.sorted(by: { $0.key.fileName < $1.key.fileName }) {
    let markers = extractMarkers(markedSource).markers.keys.sorted().filter { $0 != "0️⃣" }
    if markers.isEmpty {
      continue
    }
    let (uri, positions) = try ws.openDocument(
      fileLocation.fileName,
      language: fileLocation.fileName.hasSuffix(".h") ? headerFileLanguage : nil
    )
    defer {
      ws.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(uri)))
    }
    for marker in markers {
      let prepareRenameResponse = try await ws.testClient.send(
        PrepareRenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions[marker])
      )
      XCTAssertEqual(
        prepareRenameResponse?.placeholder,
        expectedPrepareRenamePlaceholder,
        "Prepare rename placeholder does not match while performing rename at \(marker)",
        file: file,
        line: line
      )

      let response = try await ws.testClient.send(
        RenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions[marker], newName: newName)
      )
      let changes = try XCTUnwrap(response?.changes, "Did not receive any edits", file: file, line: line)
      try assertRenamedSourceMatches(
        originalFiles: files,
        changes: changes,
        expected: expected,
        in: ws,
        message: "while performing rename at \(marker)",
        file: file,
        line: line
      )
    }
  }
}

private let libAlibBPackageManifest = """
  // swift-tools-version: 5.7

  import PackageDescription

  let package = Package(
    name: "MyLibrary",
    targets: [
     .target(name: "LibA"),
     .target(name: "LibB", dependencies: ["LibA"]),
    ]
  )
  """

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
    try SkipUnless.platformIsDarwin("#selector in test case doesn't compile without Objective-C runtime.")
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
    try await assertMultiFileRename(
      files: [
        "a.swift": """
        func 1️⃣foo() {}
        """,
        "b.swift": """
        func test() {
          2️⃣foo()
        }
        """,
      ],
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo()",
      expected: [
        "a.swift": """
        func bar() {}
        """,
        "b.swift": """
        func test() {
          bar()
        }
        """,
      ]
    )
  }

  func testSwiftCrossModuleRename() async throws {
    try await assertMultiFileRename(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣foo(argLabel: Int) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          5️⃣foo(argLabel: 1)
        }
        """,
      ],
      newName: "bar(new:)",
      expectedPrepareRenamePlaceholder: "foo(argLabel:)",
      expected: [
        "LibA/LibA.swift": """
        public func bar(new: Int) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          bar(new: 1)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testTryIndexLocationsDontMatchInMemoryLocations() async throws {
    try await assertMultiFileRename(
      files: [
        "a.swift": """
        func 1️⃣foo() {}
        """,
        "b.swift": """
        0️⃣func test() {
          foo()
        }
        """,
      ],
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo()",
      expected: [
        "a.swift": """
        func bar() {}
        """,
        "b.swift": """
        func test() {
          foo()
        }
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(
              name: "MyLibrary", 
              swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-objc-attr-requires-foundation-module"])]
            )
          ]
        )
        """,
      preRenameActions: { ws in
        let (bUri, bPositions) = try ws.openDocument("b.swift")
        ws.testClient.send(
          DidChangeTextDocumentNotification(
            textDocument: VersionedTextDocumentIdentifier(bUri, version: 1),
            contentChanges: [TextDocumentContentChangeEvent(range: Range(bPositions["0️⃣"]), text: "\n")]
          )
        )
      }
    )
  }

  func testTryIndexLocationsDontMatchInMemoryLocationsByLineColumnButNotOffset() async throws {
    try await assertMultiFileRename(
      files: [
        "a.swift": """
        func 1️⃣foo() {}
        """,
        "b.swift": """
        0️⃣func test() {
          foo()
        }
        """,
      ],
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo()",
      expected: [
        "a.swift": """
        func bar() {}
        """,
        "b.swift": """
        func test() {
          bar()
        }
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(
              name: "MyLibrary", 
              swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-objc-attr-requires-foundation-module"])]
            )
          ]
        )
        """,
      preRenameActions: { ws in
        let (bUri, bPositions) = try ws.openDocument("b.swift")
        ws.testClient.send(
          DidChangeTextDocumentNotification(
            textDocument: VersionedTextDocumentIdentifier(bUri, version: 1),
            contentChanges: [
              TextDocumentContentChangeEvent(range: Range(bPositions["0️⃣"]), text: "/* this is just a comment */")
            ]
          )
        )
      }
    )
  }

  func testPrepeareRenameOnDefinition() async throws {
    try await SkipUnless.sourcekitdSupportsRename()
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)
    let positions = testClient.openDocument(
      """
      func 1️⃣foo2️⃣(a: Int) {}
      """,
      uri: uri
    )
    let response = try await testClient.send(
      PrepareRenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let range = try XCTUnwrap(response?.range)
    let placeholder = try XCTUnwrap(response?.placeholder)
    XCTAssertEqual(range, positions["1️⃣"]..<positions["2️⃣"])
    XCTAssertEqual(placeholder, "foo(a:)")
  }

  func testPrepeareRenameOnReference() async throws {
    try await SkipUnless.sourcekitdSupportsRename()
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)
    let positions = testClient.openDocument(
      """
      func foo(a: Int, b: Int = 1) {}
      1️⃣foo2️⃣(a: 1)
      """,
      uri: uri
    )
    let response = try await testClient.send(
      PrepareRenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let range = try XCTUnwrap(response?.range)
    let placeholder = try XCTUnwrap(response?.placeholder)
    XCTAssertEqual(range, positions["1️⃣"]..<positions["2️⃣"])
    XCTAssertEqual(placeholder, "foo(a:b:)")
  }

  func testGlobalRenameC() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "Sources/MyLibrary/include/lib.h": """
        void 1️⃣do2️⃣Stuff();
        """,
        "lib.c": """
        #include "lib.h"

        void 3️⃣doStuff() {
          4️⃣doStuff();
        }
        """,
      ],
      headerFileLanguage: .c,
      newName: "doRecursiveStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "Sources/MyLibrary/include/lib.h": """
        void doRecursiveStuff();
        """,
        "lib.c": """
        #include "lib.h"

        void doRecursiveStuff() {
          doRecursiveStuff();
        }
        """,
      ]
    )
  }

  func testGlobalRenameObjC() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "Sources/MyLibrary/include/lib.h": """
        @interface Foo
        - (int)1️⃣perform2️⃣Action:(int)action 3️⃣wi4️⃣th:(int)value;
        @end
        """,
        "lib.m": """
        #include "lib.h"

        @implementation Foo
        - (int)5️⃣performAction:(int)action 6️⃣with:(int)value {
          return [self 7️⃣performAction:action 8️⃣with:value];
        }
        @end
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:by:",
      expectedPrepareRenamePlaceholder: "performAction:with:",
      expected: [
        "Sources/MyLibrary/include/lib.h": """
        @interface Foo
        - (int)performNewAction:(int)action by:(int)value;
        @end
        """,
        "lib.m": """
        #include "lib.h"

        @implementation Foo
        - (int)performNewAction:(int)action by:(int)value {
          return [self performNewAction:action by:value];
        }
        @end
        """,
      ]
    )
  }
}

final class CrossLanguageRenameTests: XCTestCase {
  func testZeroArgCFunction() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        void 1️⃣cFunc();
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void 2️⃣cFunc() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣cFunc()
        }
        """,
      ],
      headerFileLanguage: .c,
      newName: "dFunc",
      expectedPrepareRenamePlaceholder: "cFunc",
      expected: [
        "LibA/include/LibA.h": """
        void dFunc();
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void dFunc() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          dFunc()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testMultiArgCFunction() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        void 1️⃣cFunc(int x, int y);
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void 2️⃣cFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣cFunc(1, 2)
        }
        """,
      ],
      newName: "dFunc",
      expectedPrepareRenamePlaceholder: "cFunc",
      expected: [
        "LibA/include/LibA.h": """
        void dFunc(int x, int y);
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void dFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          dFunc(1, 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testCFunctionWithSwiftNameAnnotation() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        void 1️⃣cFunc(int x, int y) __attribute__((swift_name("cFunc(x:y:)")));
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void 2️⃣cFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣cFunc(x: 1, y: 2)
        }
        """,
      ],
      headerFileLanguage: .c,
      newName: "dFunc",
      expectedPrepareRenamePlaceholder: "cFunc",
      expected: [
        "LibA/include/LibA.h": """
        void dFunc(int x, int y) __attribute__((swift_name("cFunc(x:y:)")));
        """,
        "LibA/LibA.c": """
        #include "LibA.h"

        void dFunc(int x, int y) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          cFunc(x: 1, y: 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testZeroArgObjCSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performAction {
          return [self 2️⃣performAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣performAction()
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction",
      expectedPrepareRenamePlaceholder: "performAction",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction {
          return [self performNewAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.performNewAction()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testZeroArgObjCClassSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)1️⃣performAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        + (int)performAction {
          return [Foo 2️⃣performAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.3️⃣performAction()
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction",
      expectedPrepareRenamePlaceholder: "performAction",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)performNewAction;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        + (int)performNewAction {
          return [Foo performNewAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.performNewAction()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testOneArgObjCSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction:(int)action;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)2️⃣performAction:(int)action {
          return [self performAction:action];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣performAction(1)
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:",
      expectedPrepareRenamePlaceholder: "performAction:",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction:(int)action;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction:(int)action {
          return [self performNewAction:action];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.performNewAction(1)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testMultiArgObjCSelector() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction:(int)action with:(int)value;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)2️⃣performAction:(int)action with:(int)value {
          return [self performAction:action with:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣performAction(1, with: 2)
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:by:",
      expectedPrepareRenamePlaceholder: "performAction:with:",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction:(int)action by:(int)value;
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction:(int)action by:(int)value {
          return [self performNewAction:action by:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.performNewAction(1, by: 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testObjCSelectorWithSwiftNameAnnotation() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)1️⃣performAction:(int)action withValue:(int)value __attribute__((swift_name("perform(action:with:)")));
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)2️⃣performAction:(int)action withValue:(int)value {
          return [self performAction:action withValue:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣perform(action: 1, with: 2)
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "performNewAction:by:",
      expectedPrepareRenamePlaceholder: "performAction:withValue:",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        - (int)performNewAction:(int)action by:(int)value __attribute__((swift_name("perform(action:with:)")));
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Foo
        - (int)performNewAction:(int)action by:(int)value {
          return [self performNewAction:action by:value];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.perform(action: 1, with: 2)
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testObjCClass() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface 1️⃣Foo
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation 2️⃣Foo
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: 3️⃣Foo) {
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "Bar",
      expectedPrepareRenamePlaceholder: "Foo",
      expected: [
        "LibA/include/LibA.h": """
        @interface Bar
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation Bar
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Bar) {
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testObjCClassWithSwiftNameAnnotation() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        __attribute__((swift_name("Foo")))
        @interface 1️⃣AHFoo
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation 2️⃣AHFoo
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: 3️⃣Foo) {
        }
        """,
      ],
      headerFileLanguage: .objective_c,
      newName: "AHBar",
      expectedPrepareRenamePlaceholder: "AHFoo",
      expected: [
        "LibA/include/LibA.h": """
        __attribute__((swift_name("Foo")))
        @interface AHBar
        @end
        """,
        "LibA/LibA.m": """
        #include "LibA.h"

        @implementation AHBar
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }

  func testCppMethod() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          void 1️⃣doStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::2️⃣doStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣doStuff()
        }
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "doCoolStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          void doCoolStuff() const;
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::doCoolStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.doCoolStuff()
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
           .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.unsafeFlags(["-cxx-interoperability-mode=default"])]),
          ]
        )
        """
    )
  }

  func testCppMethodWithSwiftName() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          void 1️⃣doStuff(int x) const __attribute__((swift_name("do(stuff:)")));
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::2️⃣doStuff(int x) const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣do(stuff: 1)
        }
        """,
      ],
      headerFileLanguage: .cpp,
      newName: "doCoolStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          void doCoolStuff(int x) const __attribute__((swift_name("do(stuff:)")));
        };
        """,
        "LibA/LibA.cpp": """
        #include "LibA.h"

        void Foo::doCoolStuff(int x) const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.do(stuff: 1)
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
           .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.unsafeFlags(["-cxx-interoperability-mode=default"])]),
          ]
        )
        """
    )
  }

  func testCppMethodInObjCpp() async throws {
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        struct Foo {
          void 1️⃣doStuff() const;
        };
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        void Foo::2️⃣doStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.3️⃣doStuff()
        }
        """,
      ],
      headerFileLanguage: .objective_cpp,
      newName: "doCoolStuff",
      expectedPrepareRenamePlaceholder: "doStuff",
      expected: [
        "LibA/include/LibA.h": """
        struct Foo {
          void doCoolStuff() const;
        };
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        void Foo::doCoolStuff() const {};
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test(foo: Foo) {
          foo.doCoolStuff()
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
           .target(name: "LibB", dependencies: ["LibA"], swiftSettings: [.unsafeFlags(["-cxx-interoperability-mode=default"])]),
          ]
        )
        """
    )
  }

  func testZeroArgObjCClassSelectorInObjCpp() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    try await SkipUnless.clangdSupportsIndexBasedRename()
    try await assertMultiFileRename(
      files: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)1️⃣performAction;
        @end
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        @implementation Foo
        + (int)performAction {
          return [Foo 2️⃣performAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.3️⃣performAction()
        }
        """,
      ],
      headerFileLanguage: .objective_cpp,
      newName: "performNewAction",
      expectedPrepareRenamePlaceholder: "performAction",
      expected: [
        "LibA/include/LibA.h": """
        @interface Foo
        + (int)performNewAction;
        @end
        """,
        "LibA/LibA.mm": """
        #include "LibA.h"

        @implementation Foo
        + (int)performNewAction {
          return [Foo performNewAction];
        }
        @end
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          Foo.performNewAction()
        }
        """,
      ],
      manifest: libAlibBPackageManifest
    )
  }
}
