//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import XCTest

final class LocalClangTests: XCTestCase {
  // MARK: - Tests

  func testSymbolInfo() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .cpp)

    let locations = testClient.openDocument(
      """
      struct 1️⃣S {
        void 2️⃣foo() {
          int 3️⃣local = 1;
      4️⃣  }
      };
      """,
      uri: uri
    )

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: locations["1️⃣"]
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "S")
        XCTAssertNil(sym.containerName)
        XCTAssertEqual(sym.usr, "c:@S@S")
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: locations["2️⃣"]
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "foo")
        XCTAssertEqual(sym.containerName, "S::")
        XCTAssertEqual(sym.usr, "c:@S@S@F@foo#")
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: locations["3️⃣"]
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "local")
        XCTAssertEqual(sym.containerName, "S::foo")
        XCTAssertEqual(sym.usr, "c:test.cpp@30@S@S@F@foo#@local")
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: locations["4️⃣"]
        )
      )

      XCTAssertEqual(resp.count, 0)
    }
  }

  func testFoldingRange() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .cpp)

    testClient.openDocument(
      """
      struct S {
        void foo() {
          int local = 1;
        }
      };
      """,
      uri: uri
    )

    let resp = try await testClient.send(FoldingRangeRequest(textDocument: TextDocumentIdentifier(uri)))
    if let resp = resp {
      XCTAssertEqual(
        resp,
        [
          FoldingRange(startLine: 0, startUTF16Index: 10, endLine: 4, kind: .region),
          FoldingRange(startLine: 1, startUTF16Index: 14, endLine: 3, endUTF16Index: 2, kind: .region),
        ]
      )
    }
  }

  func testDocumentSymbols() async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(
        textDocument: TextDocumentClientCapabilities(
          documentSymbol: TextDocumentClientCapabilities.DocumentSymbol(
            dynamicRegistration: nil,
            symbolKind: nil,
            hierarchicalDocumentSymbolSupport: true
          )
        )
      )
    )
    let uri = DocumentURI(for: .cpp)

    testClient.openDocument(
      """
      struct S {
        void foo() {
          int local = 1;
        }
      };
      """,
      uri: uri
    )

    guard let resp = try await testClient.send(DocumentSymbolRequest(textDocument: TextDocumentIdentifier(uri))) else {
      XCTFail("Invalid document symbol response")
      return
    }
    guard case let .documentSymbols(syms) = resp else {
      XCTFail("Expected a [DocumentSymbol] but got \(resp)")
      return
    }
    XCTAssertEqual(syms.count, 1)
    XCTAssertEqual(syms.first?.name, "S")
    XCTAssertEqual(syms.first?.children?.first?.name, "foo")
  }

  func testCodeAction() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI(for: .cpp)
    let positions = testClient.openDocument(
      """
      enum Color { RED, GREEN, BLUE };

      void someFunction(Color color) {
      switch 1️⃣(color)2️⃣ {}
      }
      """,
      uri: uri
    )

    let diagnostics = try await testClient.nextDiagnosticsNotification().diagnostics
    // It seems we either get no diagnostics or a `-Wswitch` warning. Either is fine
    // as long as our code action works properly.
    XCTAssert(
      diagnostics.isEmpty || (diagnostics.count == 1 && diagnostics.first?.code == .string("-Wswitch")),
      "Unexpected diagnostics \(diagnostics)"
    )

    let codeAction = CodeActionRequest(
      range: positions["1️⃣"]..<positions["2️⃣"],
      context: CodeActionContext(),
      textDocument: TextDocumentIdentifier(uri)
    )
    guard let reply = try await testClient.send(codeAction) else {
      XCTFail("CodeActionRequest had nil reply")
      return
    }
    guard case let .commands(commands) = reply else {
      XCTFail("Expected [Command] but got \(reply)")
      return
    }
    guard let command = commands.first else {
      XCTFail("Expected a non-empty [Command]")
      return
    }
    XCTAssertEqual(command.command, "clangd.applyTweak")

    let applyEdit = XCTestExpectation(description: "applyEdit")
    testClient.handleSingleRequest { (request: ApplyEditRequest) -> ApplyEditResponse in
      XCTAssertNotNil(request.edit.changes)
      applyEdit.fulfill()
      return ApplyEditResponse(applied: true, failureReason: nil)
    }

    let executeCommand = ExecuteCommandRequest(
      command: command.command,
      arguments: command.arguments
    )
    _ = try await testClient.send(executeCommand)

    try await fulfillmentOfOrThrow([applyEdit])
  }

  func testClangStdHeaderCanary() async throws {
    // Note: tests generally should avoid including system headers
    // to keep them fast and portable. This test is specifically
    // ensuring clangd can find libc++ and builtin headers.
    let project = try await MultiFileTestProject(
      files: [
        "main.cpp": """
        #include <cstdint>

        void test() {
          uint64_t 1️⃣b2️⃣;
        }
        """,
        "compile_flags.txt": "-Wunused-variable",
      ],
      usePullDiagnostics: false
    )

    let (_, positions) = try project.openDocument("main.cpp")

    let diags = try await project.testClient.nextDiagnosticsNotification()
    // Don't use exact equality because of differences in recent clang.
    XCTAssertEqual(diags.diagnostics.count, 1)
    let diag = try XCTUnwrap(diags.diagnostics.first)
    XCTAssertEqual(diag.range, positions["1️⃣"]..<positions["2️⃣"])
    XCTAssertEqual(diag.severity, .warning)
    XCTAssertEqual(diag.message, "Unused variable 'b'")
  }

  func testClangModules() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "ClangModuleA.h": """
        #ifndef ClangModuleA_h
        #define ClangModuleA_h

        void func_ClangModuleA(void);

        #endif
        """,
        "ClangModules_main.m": """
        @import ClangModuleA;

        void test(void) {
          func_ClangModuleA();
        }
        """,
        "module.modulemap": """
        module ClangModuleA {
          header "ClangModuleA.h"
        }
        """,
        "compile_flags.txt": """
        -I
        $TEST_DIR
        -fmodules
        """,
      ],
      usePullDiagnostics: false
    )
    _ = try project.openDocument("ClangModules_main.m")

    let diags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 0)
  }

  func testSemanticHighlighting() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI(for: .c)

    testClient.openDocument(
      """
      int main(int argc, const char *argv[]) {
      }
      """,
      uri: uri
    )

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 0)

    let request = DocumentSemanticTokensRequest(textDocument: TextDocumentIdentifier(uri))
    let reply = try await testClient.send(request)
    let data = try XCTUnwrap(reply?.data)
    XCTAssertGreaterThanOrEqual(data.count, 0)
  }

  func testDocumentDependenciesUpdated() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "Object.h": """
        struct Object {
          int field;
        };

        struct Object * newObject();
        """,
        "main.c": """
        #include "Object.h"

        int main(int argc, const char *argv[]) {
          struct Object *obj = 1️⃣newObject();
        }
        """,
        "compile_flags.txt": "",
      ],
      usePullDiagnostics: false
    )

    let (mainUri, _) = try project.openDocument("main.c")
    let headerUri = try project.uri(for: "Object.h")

    // Initially the workspace should build fine.
    let initialDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssert(initialDiags.diagnostics.isEmpty)

    // We rename Object to MyObject in the header.
    try """
    struct MyObject {
      int field;
    };

    struct MyObject * newObject();
    """.write(to: headerUri.fileURL!, atomically: false, encoding: .utf8)

    let clangdServer = await project.testClient.server.languageService(
      for: mainUri,
      .c,
      in: project.testClient.server.workspaceForDocument(uri: mainUri)!
    )!

    await clangdServer.documentDependenciesUpdated(mainUri)

    // Now we should get a diagnostic in main.c file because `Object` is no longer defined.
    let editedDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertFalse(editedDiags.diagnostics.isEmpty)
  }
}
