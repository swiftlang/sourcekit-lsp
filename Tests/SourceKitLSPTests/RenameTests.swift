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
import SKTestSupport
import XCTest

final class RenameTests: XCTestCase {
  func testRenameVariableBaseName() async throws {
    try await assertSingleFileRename(
      """
      let 1️⃣foo2️⃣ = 1
      print(3️⃣foo4️⃣)
      """,
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
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
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
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
      func 1️⃣foo(5️⃣x: Int) {}
      2️⃣foo(6️⃣x: 1)
      _ = 3️⃣foo(7️⃣x:)
      _ = 4️⃣foo
      """,
      newName: "bar(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: """
        func bar(y: Int) {}
        bar(y: 1)
        _ = bar(y:)
        _ = bar
        """
    )
  }

  func testRenameFromFunctionParameter() async throws {
    try await assertSingleFileRename(
      """
      func foo(1️⃣x: Int) {}
      foo(2️⃣x: 1)
      _ = foo(3️⃣x:)
      _ = foo
      """,
      newName: "bar(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: """
        func bar(y: Int) {}
        bar(y: 1)
        _ = bar(y:)
        _ = bar
        """
    )
  }

  func testRenameFromFunctionParameterOnSeparateLine() async throws {
    try await assertSingleFileRename(
      """
      func foo(
        1️⃣x: Int
      ) {}
      foo(x: 1)
      """,
      newName: "bar(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: """
        func bar(
          y: Int
        ) {}
        bar(y: 1)
        """
    )
  }

  func testSecondParameterNameIfMatches() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(4️⃣x y: Int) {}
      2️⃣foo(5️⃣x: 1)
      _ = 3️⃣foo(6️⃣x:)
      """,
      newName: "foo(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
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
      func 1️⃣foo(4️⃣_ y: Int) {}
      2️⃣foo(1)
      _ = 3️⃣foo(5️⃣_:)
      """,
      newName: "foo(y:)",
      expectedPrepareRenamePlaceholder: "foo(_:)",
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
      func 1️⃣foo(4️⃣x: Int) {}
      2️⃣foo(5️⃣x: 1)
      _ = 3️⃣foo(6️⃣x:)
      """,
      newName: "foo(_:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
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
      func 1️⃣foo(4️⃣x a: Int) {}
      2️⃣foo(5️⃣x: 1)
      _ = 3️⃣foo(6️⃣x:)
      """,
      newName: "foo(_:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
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
        1️⃣subscript(3️⃣x x: Int) -> Int { x }
      }
      Foo()2️⃣[4️⃣x: 1]
      """,
      newName: "subscript(y:)",
      expectedPrepareRenamePlaceholder: "subscript(x:)",
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
        1️⃣subscript(3️⃣x x: Int) -> Int { x }
      }
      Foo()2️⃣[4️⃣x: 1]
      """,
      newName: "subscript(_:)",
      expectedPrepareRenamePlaceholder: "subscript(x:)",
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
        1️⃣subscript(3️⃣x: Int) -> Int { x }
      }
      Foo()2️⃣[1]
      """,
      newName: "subscript(x:)",
      expectedPrepareRenamePlaceholder: "subscript(_:)",
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
        1️⃣subscript(3️⃣x: Int) -> Int { x }
      }
      Foo()2️⃣[1]
      """,
      newName: "arrayAccess(x:)",
      expectedPrepareRenamePlaceholder: "subscript(_:)",
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
        1️⃣init(4️⃣x: Int) {}
      }
      Foo(x: 1)
      Foo.2️⃣init(5️⃣x: 1)
      _ = Foo.3️⃣init(6️⃣x:)
      """,
      newName: "init(y:)",
      expectedPrepareRenamePlaceholder: "init(x:)",
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
        1️⃣init(4️⃣x: Int) {}
      }
      Foo(5️⃣x: 1)
      Foo.2️⃣init(6️⃣x: 1)
      _ = Foo.3️⃣init(7️⃣x:)
      """,
      newName: "create(y:)",
      expectedPrepareRenamePlaceholder: "init(x:)",
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
      func 1️⃣foo(4️⃣a: Int, 5️⃣b: Int) {}
      2️⃣foo(6️⃣a: 1, 7️⃣b: 1)
      _ = 3️⃣foo(8️⃣a:9️⃣b:)
      """,
      newName: "foo(x:y:)",
      expectedPrepareRenamePlaceholder: "foo(a:b:)",
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
      func 1️⃣foo(4️⃣a: Int, 5️⃣b: Int) {}
      2️⃣foo(6️⃣a: 1, 7️⃣b: 1)
      _ = 3️⃣foo(8️⃣a:9️⃣b:)
      """,
      newName: "foo(x:)",
      expectedPrepareRenamePlaceholder: "foo(a:b:)",
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
      func 1️⃣foo(4️⃣a: Int) {}
      2️⃣foo(5️⃣a: 1)
      _ = 3️⃣foo(6️⃣a:)
      """,
      newName: "foo(x:y:)",
      expectedPrepareRenamePlaceholder: "foo(a:)",
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
      func 1️⃣foo(4️⃣a: Int) {}
      2️⃣foo(5️⃣a: 1)
      _ = 3️⃣foo(6️⃣a:)
      """,
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo(a:)",
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
      expectedPrepareRenamePlaceholder: "foo",
      expected: """
        let bar = 1
        _ = bar
        """
    )
  }

  func testNewNameDoesntContainClosingParenthesis() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(3️⃣a: Int) {}
      2️⃣foo(4️⃣a: 1)
      """,
      newName: "bar(x:",
      expectedPrepareRenamePlaceholder: "foo(a:)",
      expected: """
        func bar(x: Int) {}
        bar(x: 1)
        """
    )
  }

  func testNewNameContainsTextAfterParenthesis() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(3️⃣a: Int) {}
      2️⃣foo(4️⃣a: 1)
      """,
      newName: "bar(x:)other:",
      expectedPrepareRenamePlaceholder: "foo(a:)",
      expected: """
        func bar(x: Int) {}
        bar(x: 1)
        """
    )
  }

  func testSpacesInNewParameterNames() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(4️⃣a: Int) {}
      2️⃣foo(5️⃣a: 1)
      _ = 3️⃣foo(6️⃣a:)
      """,
      newName: "bar ( x : )",
      expectedPrepareRenamePlaceholder: "foo(a:)",
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
      expectedPrepareRenamePlaceholder: "+(_:_:)",
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
      func 1️⃣foo(3️⃣x: Int) {
        print(x)
      }
      2️⃣foo(4️⃣x: 1)
      """,
      newName: "bar(:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: """
        func bar(_ x: Int) {
          print(x)
        }
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
      expectedPrepareRenamePlaceholder: "bar(x:)",
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
      expectedPrepareRenamePlaceholder: "foo",
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
        public func 1️⃣foo(2️⃣argLabel: Int) {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func test() {
          3️⃣foo(4️⃣argLabel: 1)
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
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
          .target(name: "LibA"),
          .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
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
      expectedPrepareRenamePlaceholder: "foo",
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
      expectedPrepareRenamePlaceholder: "foo",
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
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func 1️⃣foo2️⃣(3️⃣a: Int) {}
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
    let uri = DocumentURI(for: .swift)
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

  func testRenameParameterReferencesInsideBody() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x: Int) {
        print(x)
      }
      func test() {
        2️⃣foo(x: 1)
      }
      """,
      newName: "bar(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: """
        func bar(y: Int) {
          print(y)
        }
        func test() {
          bar(y: 1)
        }
        """
    )
  }

  func testDontRenameParameterReferencesInsideBodyIfTheyUseSecondName() async throws {
    try await assertSingleFileRename(
      """
      func 1️⃣foo(x a: Int) {
        print(a)
      }
      func test() {
        2️⃣foo(x: 1)
      }
      """,
      newName: "bar(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: """
        func bar(y a: Int) {
          print(a)
        }
        func test() {
          bar(y: 1)
        }
        """
    )
  }

  func testRenameParameterReferencesInsideBodyAcrossFiles() async throws {
    try await assertMultiFileRename(
      files: [
        "a.swift": """
        func foo(x: Int) {
          print(x)
        }
        """,
        "b.swift": """
        func test() {
          1️⃣foo(x: 1)
        }
        """,
      ],
      newName: "bar(y:)",
      expectedPrepareRenamePlaceholder: "foo(x:)",
      expected: [
        "a.swift": """
        func bar(y: Int) {
          print(y)
        }
        """,
        "b.swift": """
        func test() {
          bar(y: 1)
        }
        """,
      ]
    )
  }

  func testRenameParameterInsideFunction() async throws {
    try await assertSingleFileRename(
      """
      func test(myParam: Int) {
        print(1️⃣myParam)
      }
      """,
      newName: "other",
      expectedPrepareRenamePlaceholder: "myParam",
      expected: """
        func test(myParam other: Int) {
          print(other)
        }
        """
    )
  }

  func testRenameParameterSecondNameInsideFunction() async throws {
    try await assertSingleFileRename(
      """
      func test(myExternalName myParam: Int) {
        print(1️⃣myParam)
      }
      """,
      newName: "other",
      expectedPrepareRenamePlaceholder: "myParam",
      expected: """
        func test(myExternalName other: Int) {
          print(other)
        }
        """
    )
  }

  func testRenameClassHierarchy() async throws {
    try await assertMultiFileRename(
      files: [
        "Lib.swift": """
        class Base {
          func 1️⃣foo() {}
        }

        class Inherited: Base {
          override func 2️⃣foo() {}
        }

        class OtherInherited: Base {
          override func 3️⃣foo() {}
        }

        func calls() {
          Base().4️⃣foo()
          Inherited().5️⃣foo()
          OtherInherited().6️⃣foo()
        }
        """
      ],
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
      expected: [
        "Lib.swift": """
        class Base {
          func bar() {}
        }

        class Inherited: Base {
          override func bar() {}
        }

        class OtherInherited: Base {
          override func bar() {}
        }

        func calls() {
          Base().bar()
          Inherited().bar()
          OtherInherited().bar()
        }
        """
      ]
    )
  }

  func testRenameProtocolRequirement() async throws {
    try await assertMultiFileRename(
      files: [
        "Lib.swift": """
        protocol MyProtocol {
          func 1️⃣foo()
        }

        extension MyProtocol {
          func 2️⃣foo() {}
        }

        struct Foo: MyProtocol {
          func 3️⃣foo() {}
        }

        func calls() {
          Foo().4️⃣foo()
        }
        func protocolCall(proto: MyProtocol) {
          proto.5️⃣foo()
        }
        """
      ],
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
      expected: [
        "Lib.swift": """
        protocol MyProtocol {
          func bar()
        }

        extension MyProtocol {
          func bar() {}
        }

        struct Foo: MyProtocol {
          func bar() {}
        }

        func calls() {
          Foo().bar()
        }
        func protocolCall(proto: MyProtocol) {
          proto.bar()
        }
        """
      ]
    )
  }

  func testRenameProtocolsConnectedByClassHierarchy() async throws {
    try await assertMultiFileRename(
      files: [
        "Lib.swift": """
        protocol MyProtocol {
          func 1️⃣foo()
        }

        protocol MyOtherProtocol {
          func 2️⃣foo()
        }

        class Base: MyProtocol {
          func 3️⃣foo() {}
        }

        class Inherited: Base, MyOtherProtocol {}
        """
      ],
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
      expected: [
        "Lib.swift": """
        protocol MyProtocol {
          func bar()
        }

        protocol MyOtherProtocol {
          func bar()
        }

        class Base: MyProtocol {
          func bar() {}
        }

        class Inherited: Base, MyOtherProtocol {}
        """
      ]
    )
  }

  func testRenameClassHierarchyWithoutIndexData() async throws {
    // Without index data we don't know overriding + overridden decls.
    // Check that we at least fall back to renaming the direct references to `Inherited.foo`.
    try await assertSingleFileRename(
      """
      class Base {
        func foo() {}
      }

      class Inherited: Base {
        override func 2️⃣foo() {}
      }

      class OtherInherited: Base {
        override func foo() {}
      }

      func calls() {
        Base().foo()
        Inherited().5️⃣foo()
        OtherInherited().foo()
      }
      """,
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
      expected: """
        class Base {
          func foo() {}
        }

        class Inherited: Base {
          override func bar() {}
        }

        class OtherInherited: Base {
          override func foo() {}
        }

        func calls() {
          Base().foo()
          Inherited().bar()
          OtherInherited().foo()
        }
        """
    )
  }

  func testRenameClassHierarchyWithoutIndexCpp() async throws {
    try await assertSingleFileRename(
      """
      class Base {
        virtual void 1️⃣foo();
      };

      class Inherited: Base {
        void 2️⃣foo() override {}
      };

      class OtherInherited: Base {
        void 3️⃣foo() override {}
      };
      """,
      language: .cpp,
      newName: "bar",
      expectedPrepareRenamePlaceholder: "foo",
      expected: """
        class Base {
          virtual void bar();
        };

        class Inherited: Base {
          void bar() override {}
        };

        class OtherInherited: Base {
          void bar() override {}
        };
        """
    )
  }

  func testRenameAfterFileMove() async throws {
    try await SkipUnless.sourcekitdSupportsRename()
    let project = try await SwiftPMTestProject(
      files: [
        "definition.swift": """
        func 1️⃣foo2️⃣() {}
        """,
        "caller.swift": """
        func test() {
          3️⃣foo4️⃣()
        }
        """,
      ],
      enableBackgroundIndexing: true
    )

    let definitionUri = try project.uri(for: "definition.swift")
    let (callerUri, callerPositions) = try project.openDocument("caller.swift")

    // Validate that we get correct rename results before moving the definition file.
    let resultBeforeFileMove = try await project.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(callerUri), position: callerPositions["3️⃣"], newName: "bar")
    )
    XCTAssertEqual(
      resultBeforeFileMove,
      WorkspaceEdit(
        changes: [
          definitionUri: [
            TextEdit(
              range: try project.position(
                of: "1️⃣",
                in: "definition.swift"
              )..<project.position(of: "2️⃣", in: "definition.swift"),
              newText: "bar"
            )
          ],
          callerUri: [TextEdit(range: callerPositions["3️⃣"]..<callerPositions["4️⃣"], newText: "bar")],
        ]
      )
    )

    let movedDefinitionUri =
      DocumentURI(
        definitionUri.fileURL!
          .deletingLastPathComponent()
          .appendingPathComponent("movedDefinition.swift")
      )

    try FileManager.default.moveItem(at: XCTUnwrap(definitionUri.fileURL), to: XCTUnwrap(movedDefinitionUri.fileURL))

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: definitionUri, type: .deleted), FileEvent(uri: movedDefinitionUri, type: .created),
      ])
    )

    try await project.testClient.send(PollIndexRequest())

    let resultAfterFileMove = try await project.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(callerUri), position: callerPositions["3️⃣"], newName: "bar")
    )
    XCTAssertEqual(
      resultAfterFileMove,
      WorkspaceEdit(
        changes: [
          movedDefinitionUri: [
            TextEdit(
              range: try project.position(
                of: "1️⃣",
                in: "definition.swift"
              )..<project.position(of: "2️⃣", in: "definition.swift"),
              newText: "bar"
            )
          ],
          callerUri: [TextEdit(range: callerPositions["3️⃣"]..<callerPositions["4️⃣"], newText: "bar")],
        ]
      )
    )
  }

  func testRenameEnumCaseWithUnlabeledAssociatedValue() async throws {
    try await SkipUnless.sourcekitdCanRenameEnumCaseLabels()
    try await assertSingleFileRename(
      """
      enum MyEnum {
        case 1️⃣myCase(String)
      }
      """,
      newName: "newName",
      expectedPrepareRenamePlaceholder: "myCase(_:)",
      expected: """
        enum MyEnum {
          case newName(String)
        }
        """
    )
  }

  func testAddLabelToEnumCase() async throws {
    try await SkipUnless.sourcekitdCanRenameEnumCaseLabels()
    try await assertSingleFileRename(
      """
      enum MyEnum {
        case 1️⃣myCase(String)
      }
      """,
      newName: "newName(newLabel:)",
      expectedPrepareRenamePlaceholder: "myCase(_:)",
      expected: """
        enum MyEnum {
          case newName(newLabel: String)
        }
        """
    )
  }

  func testRemoveLabelFromEnumCase() async throws {
    try await SkipUnless.sourcekitdCanRenameEnumCaseLabels()
    try await assertSingleFileRename(
      """
      enum MyEnum {
        case myCase(label: String)
      }

      func test() {
        _ = MyEnum.2️⃣myCase(label: "abc")
      }
      """,
      newName: "newName(_:)",
      expectedPrepareRenamePlaceholder: "myCase(label:)",
      expected: """
        enum MyEnum {
          case newName(_ label: String)
        }

        func test() {
          _ = MyEnum.newName("abc")
        }
        """
    )
  }

  func testRenameEnumCaseWithUnderscoreLabel() async throws {
    try await SkipUnless.sourcekitdCanRenameEnumCaseLabels()
    try await assertSingleFileRename(
      """
      enum MyEnum {
        case myCase(_ label: String)
      }

      func test() {
        _ = MyEnum.2️⃣myCase("abc")
      }
      """,
      newName: "newName(_:)",
      expectedPrepareRenamePlaceholder: "myCase(_:)",
      expected: """
        enum MyEnum {
          case newName(_ label: String)
        }

        func test() {
          _ = MyEnum.newName("abc")
        }
        """
    )
  }

  func testRenameEnumCaseWithUnderscoreToLabelMatchingInternalName() async throws {
    try await SkipUnless.sourcekitdCanRenameEnumCaseLabels()
    try await assertSingleFileRename(
      """
      enum MyEnum {
        case myCase(_ label: String)
      }

      func test() {
        _ = MyEnum.2️⃣myCase("abc")
      }
      """,
      newName: "newName(label:)",
      expectedPrepareRenamePlaceholder: "myCase(_:)",
      expected: """
        enum MyEnum {
          case newName(label: String)
        }

        func test() {
          _ = MyEnum.newName(label: "abc")
        }
        """
    )
  }

  func testRenameEnumCaseWithUnderscoreToLabelNotMatchingInternalName() async throws {
    try await SkipUnless.sourcekitdCanRenameEnumCaseLabels()
    // Note that the renamed code doesn't compile because enum cases can't have an external and internal parameter name.
    // But it's probably the best thing we can do because we don't want to erase the user-specified internal name, which
    // they didn't request to rename. Also, this is a pretty niche case and having a special case for it is probably not
    // worth it.
    try await assertSingleFileRename(
      """
      enum MyEnum {
        case myCase(_ label: String)
      }

      func test() {
        _ = MyEnum.2️⃣myCase("abc")
      }
      """,
      newName: "newName(publicLabel:)",
      expectedPrepareRenamePlaceholder: "myCase(_:)",
      expected: """
        enum MyEnum {
          case newName(publicLabel label: String)
        }

        func test() {
          _ = MyEnum.newName(publicLabel: "abc")
        }
        """
    )
  }

  func testRenameDoesNotReportEditsIfNoActualChangeIsMade() async throws {
    try await SkipUnless.sourcekitdSupportsRename()
    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": """
        func 1️⃣foo(x: Int) {}
        """,
        "FileB.swift": """
        func test() {
          foo(x: 1)
        }
        """,
      ],
      enableBackgroundIndexing: true
    )
    let (uri, positions) = try project.openDocument("FileA.swift")
    let result = try await project.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"], newName: "foo(x:)")
    )
    XCTAssertEqual(result?.changes, [:])
  }
}
