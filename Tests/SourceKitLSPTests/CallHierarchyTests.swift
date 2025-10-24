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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SwiftExtensions
import TSCBasic
import XCTest

final class CallHierarchyTests: XCTestCase {
  override func setUp() async throws {
    LoggingScope.configureDefaultLoggingSubsystem("org.swift.sourcekit-lsp-tests")
  }

  func testCallHierarchy() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣a() {}

      func 2️⃣b(x: String) {
        3️⃣a()
        4️⃣c()
        5️⃣b(x: "test")
      }

      func 6️⃣c() {
        7️⃣a()
        if 8️⃣d() {
          9️⃣c()
        }
      }

      func 🔟d() -> Bool {
        false
      }

      a()
      b(x: "test")
      """
    )

    func callHierarchy(at position: Position) async throws -> [CallHierarchyItem] {
      let request = CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: position
      )
      return try await project.testClient.send(request) ?? []
    }

    func incomingCalls(at position: Position) async throws -> [CallHierarchyIncomingCall] {
      guard let item = try await callHierarchy(at: position).first else {
        XCTFail("call hierarchy at \(position) was empty")
        return []
      }
      let request = CallHierarchyIncomingCallsRequest(item: item)
      return try await project.testClient.send(request) ?? []
    }

    func outgoingCalls(at position: Position) async throws -> [CallHierarchyOutgoingCall] {
      guard let item = try await callHierarchy(at: position).first else {
        XCTFail("call hierarchy at \(position) was empty")
        return []
      }
      let request = CallHierarchyOutgoingCallsRequest(item: item)
      return try await project.testClient.send(request) ?? []
    }

    func usr(at position: Position) async throws -> String {
      guard let item = try await callHierarchy(at: position).first else {
        XCTFail("call hierarchy at \(position) was empty")
        return ""
      }
      guard case let .dictionary(data) = item.data,
        case let .string(usr) = data["usr"]
      else {
        XCTFail("unable to find usr in call hierarchy in item data dictionary")
        return ""
      }
      return usr
    }

    // Convenience functions

    func item(
      _ name: String,
      _ kind: SymbolKind,
      detail: String? = nil,
      usr: String,
      at position: Position
    ) -> CallHierarchyItem {
      return CallHierarchyItem(
        name: name,
        kind: kind,
        tags: nil,
        detail: detail,
        uri: project.fileURI,
        range: Range(position),
        selectionRange: Range(position),
        data: .dictionary([
          "usr": .string(usr),
          "uri": .string(project.fileURI.stringValue),
        ])
      )
    }

    let aUsr = try await usr(at: project.positions["1️⃣"])
    let bUsr = try await usr(at: project.positions["2️⃣"])
    let cUsr = try await usr(at: project.positions["6️⃣"])
    let dUsr = try await usr(at: project.positions["🔟"])

    // Test outgoing call hierarchy

    assertEqual(try await outgoingCalls(at: project.positions["1️⃣"]), [])
    assertEqual(
      try await outgoingCalls(at: project.positions["2️⃣"]),
      [
        CallHierarchyOutgoingCall(
          to: item("a()", .function, usr: aUsr, at: project.positions["1️⃣"]),
          fromRanges: [Range(project.positions["3️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("b(x:)", .function, usr: bUsr, at: project.positions["2️⃣"]),
          fromRanges: [Range(project.positions["5️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("c()", .function, usr: cUsr, at: project.positions["6️⃣"]),
          fromRanges: [Range(project.positions["4️⃣"])]
        ),
      ]
    )
    assertEqual(
      try await outgoingCalls(at: project.positions["6️⃣"]),
      [
        CallHierarchyOutgoingCall(
          to: item("a()", .function, usr: aUsr, at: project.positions["1️⃣"]),
          fromRanges: [Range(project.positions["7️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("c()", .function, usr: cUsr, at: project.positions["6️⃣"]),
          fromRanges: [Range(project.positions["9️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("d()", .function, usr: dUsr, at: project.positions["🔟"]),
          fromRanges: [Range(project.positions["8️⃣"])]
        ),
      ]
    )

    // Test incoming call hierarchy

    assertEqual(
      try await incomingCalls(at: project.positions["1️⃣"]),
      [
        CallHierarchyIncomingCall(
          from: item("b(x:)", .function, usr: bUsr, at: project.positions["2️⃣"]),
          fromRanges: [Range(project.positions["3️⃣"])]
        ),
        CallHierarchyIncomingCall(
          from: item("c()", .function, usr: cUsr, at: project.positions["6️⃣"]),
          fromRanges: [Range(project.positions["7️⃣"])]
        ),
      ]
    )
    assertEqual(
      try await incomingCalls(at: project.positions["2️⃣"]),
      [
        CallHierarchyIncomingCall(
          from: item("b(x:)", .function, usr: bUsr, at: project.positions["2️⃣"]),
          fromRanges: [Range(project.positions["5️⃣"])]
        )
      ]
    )
    assertEqual(
      try await incomingCalls(at: project.positions["🔟"]),
      [
        CallHierarchyIncomingCall(
          from: item("c()", .function, usr: cUsr, at: project.positions["6️⃣"]),
          fromRanges: [Range(project.positions["8️⃣"])]
        )
      ]
    )
  }

  func testReportSingleItemInPrepareCallHierarchy() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/lib.h": """
        struct FilePathIndex {
          void 1️⃣foo();
        };
        """,
        "MyLibrary/lib.cpp": """
        #include "lib.h"
        void FilePathIndex::2️⃣foo() {}
        """,
      ],
      enableBackgroundIndexing: true
    )
    let (uri, positions) = try project.openDocument("lib.h", language: .cpp)
    let result = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    // Test that we don't provide both the definition in .cpp and the declaration on .h
    XCTAssertEqual(
      result,
      [
        CallHierarchyItem(
          name: "FilePathIndex::foo",
          kind: .method,
          tags: nil,
          uri: try project.uri(for: "lib.cpp"),
          range: try Range(project.position(of: "2️⃣", in: "lib.cpp")),
          selectionRange: try Range(project.position(of: "2️⃣", in: "lib.cpp")),
          data: LSPAny.dictionary([
            "usr": .string("c:@S@FilePathIndex@F@foo#"),
            "uri": .string(try project.uri(for: "lib.cpp").stringValue),
          ])
        )
      ]
    )
  }

  func testIncomingCallHierarchyShowsSurroundingFunctionCall() async throws {
    // We used to show `myVar` as the caller here
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      func 2️⃣testFunc(x: String) {
        let myVar = 3️⃣foo()
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "testFunc(x:)",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test0A4Func1xySS_tF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testIncomingCallHierarchyFromComputedProperty() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      var testVar: Int {
        2️⃣get {
          let myVar = 3️⃣foo()
          return 2
        }
      }

      func 4️⃣testFunc() {
        _ = 5️⃣testVar
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "getter:testVar",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test0A3VarSivg"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )

    let testVarItem = try XCTUnwrap(calls?.first?.from)

    let callsToTestVar = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: testVarItem))
    XCTAssertEqual(
      callsToTestVar,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "testFunc()",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["4️⃣"]),
            selectionRange: Range(project.positions["4️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test0A4FuncyyF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["5️⃣"])]
        )
      ]
    )
  }

  func testIncomingCallHierarchyShowsAccessToVariables() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      var 1️⃣foo: Int
      func 2️⃣testFunc() {
        _ = 3️⃣foo
        4️⃣foo = 2
      }

      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "testFunc()",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test0A4FuncyyF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"]), Range(project.positions["4️⃣"])]
        )
      ]
    )
  }

  func testOutgoingCallHierarchyShowsAccessesToVariable() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      var 1️⃣foo: Int
      func 2️⃣testFunc() {
        _ = 3️⃣foo
      }

      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyOutgoingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyOutgoingCall(
          to: CallHierarchyItem(
            name: "getter:foo",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["1️⃣"]),
            selectionRange: Range(project.positions["1️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test3fooSivg"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testOutgoingCallHierarchyFromVariableAccessor() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣testFunc() -> Int { 0 }
      var 2️⃣foo: Int {
        3️⃣testFunc()
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyOutgoingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyOutgoingCall(
          to: CallHierarchyItem(
            name: "testFunc()",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["1️⃣"]),
            selectionRange: Range(project.positions["1️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test0A4FuncSiyF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testIncomingCallHierarchyLooksThroughProtocols() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      protocol MyProtocol {
        func foo()
      }
      struct MyStruct: MyProtocol {
        func 1️⃣foo() {}
      }
      struct Unrelated: MyProtocol {
        func foo() {}
      }
      func 2️⃣test(proto: MyProtocol) {
        proto.3️⃣foo()
        Unrelated().foo() // should not be considered a call to MyStruct.foo
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "test(proto:)",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4testAA5protoyAA10MyProtocol_p_tF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testIncomingCallHierarchyLooksThroughSuperclasses() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      class Base {
        func foo() {}
      }
      class Inherited: Base {
        override func 1️⃣foo() {}
      }
      class Unrelated: Base {
        override func foo() {}
      }
      func 2️⃣test(base: Base) {
        base.3️⃣foo()
        Unrelated().foo() // should not be considered a call to MyStruct.foo
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "test(base:)",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4testAA4baseyAA4BaseC_tF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testCallHierarchyContainsContainerNameAsDetail() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      class MyClass {
        func 1️⃣foo() {
          2️⃣bar()
        }
      }
      func 3️⃣bar() {
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["3️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "MyClass.foo()",
            kind: .method,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["1️⃣"]),
            selectionRange: Range(project.positions["1️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test7MyClassC3fooyyF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["2️⃣"])]
        )
      ]
    )
  }

  func testUnappliedFunctionReferenceInIncomingCallHierarchy() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      func 2️⃣testFunc(x: String) {
        let myVar = 3️⃣foo
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "testFunc(x:)",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test0A4Func1xySS_tF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testUnappliedFunctionReferenceInOutgoingCallHierarchy() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      func 2️⃣testFunc(x: String) {
        let myVar = 3️⃣foo
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyOutgoingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyOutgoingCall(
          to: CallHierarchyItem(
            name: "foo()",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["1️⃣"]),
            selectionRange: Range(project.positions["1️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test3fooyyF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testIncomingCallHierarchyForPropertyInitializedWithClosure() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() -> Int {}

      let 2️⃣myVar: Int = {
        3️⃣foo()
      }()
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "myVar",
            kind: .variable,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test5myVarSivp"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testOutgoingCallHierarchyForPropertyInitializedWithClosure() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() -> Int {}

      let 2️⃣myVar: Int = {
        3️⃣foo()
      }()
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyOutgoingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyOutgoingCall(
          to: CallHierarchyItem(
            name: "foo()",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["1️⃣"]),
            selectionRange: Range(project.positions["1️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test3fooSiyF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testInitializerInCallHierarchy() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      struct Bar {
        2️⃣init() {
          3️⃣foo()
        }
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "Bar.init()",
            kind: .constructor,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test3BarVACycfc"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testCallHierarchyOfNestedClass() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      struct Outer {
        struct Bar {
          2️⃣init() {
            3️⃣foo()
          }
        }
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "Outer.Bar.init()",
            kind: .constructor,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test5OuterV3BarVAEycfc"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testIncomingCallHierarchyFromComputedMember() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        func 1️⃣foo() {}

        var testVar: Int {
          2️⃣get {
            let myVar = 3️⃣foo()
            return 2
          }
        }
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "Foo.getter:testVar",
            kind: .method,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test3FooV0A3VarSivg"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["3️⃣"])]
        )
      ]
    )
  }

  func testOnlyConsiderCallsAsIncomingCallOccurrences() async throws {
    // extension MyTask: AnyTask {} includes an occurrence of `MyTask.cancel` to mark it as an override of
    // `AnyTask.cancel` but we shouldn't show the extension in the call hierarchy.
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct MyTask {
        func cancel() {}
      }

      protocol AnyTask {
        func cancel()
      }

      extension MyTask: AnyTask {}

      func 2️⃣foo(task: MyTask)3️⃣ {
        task.1️⃣cancel()
      }
      """
    )
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "foo(task:)",
            kind: .function,
            tags: nil,
            uri: project.fileURI,
            range: Range(project.positions["2️⃣"]),
            selectionRange: Range(project.positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:4test3foo4taskyAA6MyTaskV_tF"),
              "uri": .string(project.fileURI.stringValue),
            ])
          ),
          fromRanges: [Range(project.positions["1️⃣"])]
        )
      ]
    )
  }
}
