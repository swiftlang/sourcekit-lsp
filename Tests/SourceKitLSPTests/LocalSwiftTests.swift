//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPLogging
import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import SwiftParser
import SwiftSyntax
import XCTest

// Workaround ambiguity with Foundation.
typealias Notification = LanguageServerProtocol.Notification

final class LocalSwiftTests: XCTestCase {

  /// The mock client used to communicate with the SourceKit-LSP server.
  ///
  /// - Note: Set before each test run in `setUp`.
  private var testClient: TestSourceKitLSPClient! = nil

  override func setUp() async throws {
    testClient = TestSourceKitLSPClient()
    _ = try await self.testClient.send(
      InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURI: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(
          workspace: nil,
          textDocument: TextDocumentClientCapabilities(
            codeAction: .init(
              codeActionLiteralSupport: .init(
                codeActionKind: .init(valueSet: [.quickFix])
              )
            ),
            publishDiagnostics: .init(codeDescriptionSupport: true)
          )
        ),
        trace: .off,
        workspaceFolders: nil
      )
    )
  }

  override func tearDown() {
    testClient = nil
  }

  // MARK: - Tests

  func testEditing() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    let documentManager = await testClient.server._documentManager

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func
            """
        )
      )
    )
    let syntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(syntacticDiags.version, 12)
    XCTAssertEqual(syntacticDiags.diagnostics.count, 1)
    XCTAssertEqual("func", documentManager.latestSnapshot(uri)!.text)
    let semanticOpenDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticOpenDiags.version, 12)
    XCTAssertEqual(semanticOpenDiags.diagnostics.count, 1)
    XCTAssertEqual(
      semanticOpenDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 4)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 13),
        contentChanges: [
          .init(range: Range(Position(line: 0, utf16index: 4)), text: " foo() {}\n")
        ]
      )
    )
    let edit1SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    // 1 = remaining semantic error
    XCTAssertEqual(edit1SyntacticDiags.version, 13)
    XCTAssertLessThanOrEqual(edit1SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual("func foo() {}\n", documentManager.latestSnapshot(uri)!.text)

    let edit1SemanticDiags = try await testClient.nextDiagnosticsNotification()
    // 0 = semantic update finished already
    XCTAssertEqual(edit1SemanticDiags.version, 13)
    XCTAssertEqual(edit1SemanticDiags.diagnostics.count, 0)

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 14),
        contentChanges: [
          .init(range: Range(Position(line: 1, utf16index: 0)), text: "bar()")
        ]
      )
    )
    let edit2SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit2SyntacticDiags.version, 14)
    // 0 = only syntactic
    XCTAssertLessThanOrEqual(edit2SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func foo() {}
      bar()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit2SemanticDiags = try await testClient.nextDiagnosticsNotification()
    // 1 = semantic update finished already
    XCTAssertEqual(edit2SemanticDiags.version, 14)
    XCTAssertEqual(edit2SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      edit2SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 1, utf16index: 0)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 14),
        contentChanges: [
          .init(range: Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 3), text: "foo")
        ]
      )
    )
    let edit3SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    // 1 = remaining semantic error
    XCTAssertEqual(edit3SyntacticDiags.version, 14)
    XCTAssertLessThanOrEqual(edit3SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func foo() {}
      foo()
      """,
      documentManager.latestSnapshot(uri)!.text
    )

    let edit3SemanticDiags = try await testClient.nextDiagnosticsNotification()
    // 0 = semantic update finished already
    XCTAssertEqual(edit3SemanticDiags.version, 14)
    XCTAssertEqual(edit3SemanticDiags.diagnostics.count, 0)

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 15),
        contentChanges: [
          .init(range: Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 3), text: "fooTypo")
        ]
      )
    )
    let edit4SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit4SyntacticDiags.version, 15)
    // 1 = semantic update finished already
    XCTAssertLessThanOrEqual(edit4SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func foo() {}
      fooTypo()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit4SemanticDiags = try await testClient.nextDiagnosticsNotification()
    // 0 = only syntactic
    XCTAssertEqual(edit4SemanticDiags.version, 15)
    XCTAssertEqual(edit4SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      edit4SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 1, utf16index: 0)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 16),
        contentChanges: [
          .init(
            range: nil,
            text: """
              func bar() {}
              foo()
              """
          )
        ]
      )
    )
    let edit5SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit5SyntacticDiags.version, 16)
    // Could be remaining semantic error or new one.
    XCTAssertEqual(edit5SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func bar() {}
      foo()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit5SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit5SemanticDiags.version, 16)
    XCTAssertEqual(edit5SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      edit5SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 1, utf16index: 0)
    )
  }

  func testEditingNonURL() async throws {
    let uri = DocumentURI(string: "urn:uuid:A1B08909-E791-469E-BF0F-F5790977E051")

    let documentManager = await testClient.server._documentManager

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func
            """
        )
      )
    )
    let openSyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openSyntacticDiags.version, 12)
    XCTAssertEqual(openSyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual("func", documentManager.latestSnapshot(uri)!.text)

    let openSemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openSemanticDiags.version, 12)
    XCTAssertEqual(openSemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openSemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 4)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 13),
        contentChanges: [
          .init(range: Range(Position(line: 0, utf16index: 4)), text: " foo() {}\n")
        ]
      )
    )
    let edit1SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit1SyntacticDiags.version, 13)
    // 1 = remaining semantic error
    // 0 = semantic update finished already
    XCTAssertLessThanOrEqual(edit1SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual("func foo() {}\n", documentManager.latestSnapshot(uri)!.text)

    let edit1SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit1SemanticDiags.version, 13)
    XCTAssertEqual(edit1SemanticDiags.diagnostics.count, 0)

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 14),
        contentChanges: [
          .init(range: Range(Position(line: 1, utf16index: 0)), text: "bar()")
        ]
      )
    )
    let edit2SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit2SyntacticDiags.version, 14)
    // 1 = semantic update finished already
    // 0 = only syntactic
    XCTAssertLessThanOrEqual(edit2SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func foo() {}
      bar()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit2SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit2SemanticDiags.version, 14)
    XCTAssertEqual(edit2SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      edit2SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 1, utf16index: 0)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 14),
        contentChanges: [
          .init(range: Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 3), text: "foo")
        ]
      )
    )
    let edit3SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit3SyntacticDiags.version, 14)
    // 1 = remaining semantic error
    // 0 = semantic update finished already
    XCTAssertLessThanOrEqual(edit3SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func foo() {}
      foo()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit3SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit3SemanticDiags.version, 14)
    XCTAssertEqual(edit3SemanticDiags.diagnostics.count, 0)

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 15),
        contentChanges: [
          .init(range: Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 3), text: "fooTypo")
        ]
      )
    )
    let edit4SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit4SyntacticDiags.version, 15)
    // 1 = semantic update finished already
    // 0 = only syntactic
    XCTAssertLessThanOrEqual(edit4SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func foo() {}
      fooTypo()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit4SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit4SemanticDiags.version, 15)
    XCTAssertEqual(edit4SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      edit4SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 1, utf16index: 0)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 16),
        contentChanges: [
          .init(
            range: nil,
            text: """
              func bar() {}
              foo()
              """
          )
        ]
      )
    )
    let edit5SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit5SyntacticDiags.version, 16)
    // Could be remaining semantic error or new one.
    XCTAssertEqual(edit5SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      """
      func bar() {}
      foo()
      """,
      documentManager.latestSnapshot(uri)!.text
    )
    let edit5SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(edit5SemanticDiags.version, 16)
    XCTAssertEqual(edit5SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      edit5SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 1, utf16index: 0)
    )
  }

  func testExcludedDocumentSchemeDiagnostics() async throws {
    let includedURL = URL(fileURLWithPath: "/a.swift")
    let includedURI = DocumentURI(includedURL)

    let excludedURI = DocumentURI(string: "git:/a.swift")

    let text = """
      func
      """

    // Open the excluded URI first so our later notification handlers can confirm
    // that no diagnostics were emitted for this excluded URI.
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: excludedURI,
          language: .swift,
          version: 1,
          text: text
        )
      )
    )

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: includedURI,
          language: .swift,
          version: 1,
          text: text
        )
      )
    )
    let syntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(syntacticDiags.uri, includedURI)
    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.uri, includedURI)
  }

  func testCrossFileDiagnostics() async throws {
    let urlA = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let urlB = URL(fileURLWithPath: "/\(UUID())/b.swift")
    let uriA = DocumentURI(urlA)
    let uriB = DocumentURI(urlB)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uriA,
          language: .swift,
          version: 12,
          text: """
            foo()
            """
        )
      )
    )
    let openASyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openASyntacticDiags.version, 12)
    // 1 = semantic update finished already
    // 0 = only syntactic
    XCTAssertLessThanOrEqual(openASyntacticDiags.diagnostics.count, 1)

    let openASemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openASemanticDiags.version, 12)
    XCTAssertEqual(openASemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openASemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 0)
    )

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uriB,
          language: .swift,
          version: 12,
          text: """
            bar()
            """
        )
      )
    )
    let openBSyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openBSyntacticDiags.version, 12)
    // 1 = semantic update finished already
    // 0 = only syntactic
    XCTAssertLessThanOrEqual(openBSyntacticDiags.diagnostics.count, 1)

    let openBSemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openBSemanticDiags.version, 12)
    XCTAssertEqual(openBSemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openBSemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 0)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uriA, version: 13),
        contentChanges: [
          .init(range: nil, text: "foo()\n")
        ]
      )
    )
    let editASyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editASyntacticDiags.version, 13)
    XCTAssertEqual(editASyntacticDiags.diagnostics.count, 1)

    let editASemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editASemanticDiags.version, 13)
    XCTAssertEqual(editASemanticDiags.diagnostics.count, 1)
  }

  func testDiagnosticsReopen() async throws {
    let urlA = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uriA = DocumentURI(urlA)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uriA,
          language: .swift,
          version: 12,
          text: """
            foo()
            """
        )
      )
    )

    let open1SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(open1SyntacticDiags.version, 12)
    // 1 = semantic update finished already
    // 0 = only syntactic
    XCTAssertLessThanOrEqual(open1SyntacticDiags.diagnostics.count, 1)

    let open1SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(open1SemanticDiags.version, 12)
    XCTAssertEqual(open1SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      open1SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 0)
    )

    testClient.send(DidCloseTextDocumentNotification(textDocument: .init(urlA)))

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uriA,
          language: .swift,
          version: 13,
          text: """
            var
            """
        )
      )
    )

    let open2SyntacticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(open2SyntacticDiags.version, 13)
    // 1 = syntactic, no cached semantic diagnostic from previous version
    XCTAssertEqual(open2SyntacticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      open2SyntacticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 3)
    )

    let open2SemanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(open2SemanticDiags.version, 13)
    XCTAssertEqual(open2SemanticDiags.diagnostics.count, 1)
    XCTAssertEqual(
      open2SemanticDiags.diagnostics.first?.range.lowerBound,
      Position(line: 0, utf16index: 3)
    )
  }

  func testEducationalNotesAreUsedAsDiagnosticCodes() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: "@propertyWrapper struct Bar {}"
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()

    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    let diag = semanticDiags.diagnostics.first!
    XCTAssertEqual(diag.code, .string("property-wrapper-requirements"))
    XCTAssertEqual(diag.codeDescription?.href.fileURL?.lastPathComponent, "property-wrapper-requirements.md")
  }

  func testFixitsAreIncludedInPublishDiagnostics() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func foo() {
              let a = 2
            }
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()

    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    let diag = semanticDiags.diagnostics.first!
    XCTAssertNotNil(diag.codeActions)
    XCTAssertEqual(diag.codeActions!.count, 1)
    let fixit = diag.codeActions!.first!

    // Expected Fix-it: Replace `let a` with `_` because it's never used
    let expectedTextEdit = TextEdit(
      range: Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 7),
      newText: "_"
    )
    XCTAssertEqual(
      fixit,
      CodeAction(
        title: "Replace 'let a' with '_'",
        kind: .quickFix,
        diagnostics: nil,
        edit: WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil),
        command: nil
      )
    )
  }

  func testFixitsAreIncludedInPublishDiagnosticsNotes() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func foo(a: Int?) {
              _ = a.bigEndian
            }
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()

    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    let diag = semanticDiags.diagnostics.first!
    XCTAssertEqual(diag.relatedInformation?.count, 2)
    if let note1 = diag.relatedInformation?.first(where: { $0.message.contains("'?'") }) {
      XCTAssertEqual(note1.codeActions?.count, 1)
      if let fixit = note1.codeActions?.first {
        // Expected Fix-it: Replace `let a` with `_` because it's never used
        let expectedTextEdit = TextEdit(
          range: Position(line: 1, utf16index: 7)..<Position(line: 1, utf16index: 7),
          newText: "?"
        )
        XCTAssertEqual(
          fixit,
          CodeAction(
            title: "chain the optional using '?' to access member 'bigEndian' only for non-'nil' base values",
            kind: .quickFix,
            diagnostics: nil,
            edit: WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil),
            command: nil
          )
        )
      }
    } else {
      XCTFail("missing '?' note")
    }
    if let note2 = diag.relatedInformation?.first(where: { $0.message.contains("'!'") }) {
      XCTAssertEqual(note2.codeActions?.count, 1)
      if let fixit = note2.codeActions?.first {
        // Expected Fix-it: Replace `let a` with `_` because it's never used
        let expectedTextEdit = TextEdit(
          range: Position(line: 1, utf16index: 7)..<Position(line: 1, utf16index: 7),
          newText: "!"
        )
        XCTAssertEqual(
          fixit,
          CodeAction(
            title: "force-unwrap using '!' to abort execution if the optional value contains 'nil'",
            kind: .quickFix,
            diagnostics: nil,
            edit: WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil),
            command: nil
          )
        )
      }
    } else {
      XCTFail("missing '!' note")
    }
  }

  func testFixitInsert() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func foo() {
              print("")print("")
            }
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()
    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    let diag = semanticDiags.diagnostics.first!
    XCTAssertNotNil(diag.codeActions)
    XCTAssertEqual(diag.codeActions!.count, 1)
    let fixit = diag.codeActions!.first!

    // Expected Fix-it: Insert `;`
    let expectedTextEdit = TextEdit(
      range: Position(line: 1, utf16index: 11)..<Position(line: 1, utf16index: 11),
      newText: ";"
    )
    XCTAssertEqual(
      fixit,
      CodeAction(
        title: "Insert ';'",
        kind: .quickFix,
        diagnostics: nil,
        edit: WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil),
        command: nil
      )
    )
  }

  func testFixitTitle() {
    XCTAssertEqual("Insert ';'", CodeAction.fixitTitle(replace: "", with: ";"))
    XCTAssertEqual("Replace 'let a' with '_'", CodeAction.fixitTitle(replace: "let a", with: "_"))
    XCTAssertEqual("Remove 'foo ='", CodeAction.fixitTitle(replace: "foo =", with: ""))
  }

  func testFixitsAreReturnedFromCodeActions() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    var diagnostic: Diagnostic? = nil
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func foo() {
              let a = 2
            }
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()
    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    diagnostic = semanticDiags.diagnostics.first

    let request = CodeActionRequest(
      range: Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 11),
      context: CodeActionContext(
        diagnostics: [try XCTUnwrap(diagnostic, "expected diagnostic to be available")],
        only: nil
      ),
      textDocument: TextDocumentIdentifier(uri)
    )
    let response = try await testClient.send(request)

    XCTAssertNotNil(response)
    guard case .codeActions(let codeActions) = response else {
      XCTFail("Expected code actions as response")
      return
    }
    let quickFixes = codeActions.filter { $0.kind == .quickFix }
    XCTAssertEqual(quickFixes.count, 1)
    let fixit = quickFixes.first!

    // Diagnostic returned by code actions cannot be recursive
    var expectedDiagnostic = try XCTUnwrap(diagnostic, "expected diagnostic to be available")
    expectedDiagnostic.codeActions = nil

    // Expected Fix-it: Replace `let a` with `_` because it's never used
    let expectedTextEdit = TextEdit(
      range: Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 7),
      newText: "_"
    )
    XCTAssertEqual(
      fixit,
      CodeAction(
        title: "Replace 'let a' with '_'",
        kind: .quickFix,
        diagnostics: [expectedDiagnostic],
        edit: WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil),
        command: nil
      )
    )
  }

  func testFixitsAreReturnedFromCodeActionsNotes() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    var diagnostic: Diagnostic?
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            func foo(a: Int?) {
              _ = a.bigEndian
            }
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()

    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    diagnostic = semanticDiags.diagnostics.first

    let request = CodeActionRequest(
      range: Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 11),
      context: CodeActionContext(
        diagnostics: [try XCTUnwrap(diagnostic, "expected diagnostic to be available")],
        only: nil
      ),
      textDocument: TextDocumentIdentifier(uri)
    )
    let response = try await testClient.send(request)

    XCTAssertNotNil(response)
    guard case .codeActions(let codeActions) = response else {
      XCTFail("Expected code actions as response")
      return
    }
    let quickFixes = codeActions.filter { $0.kind == .quickFix }
    XCTAssertEqual(quickFixes.count, 2)

    var expectedTextEdit = TextEdit(
      range: Position(line: 1, utf16index: 7)..<Position(line: 1, utf16index: 7),
      newText: "_"
    )

    for fixit in quickFixes {
      if fixit.title.contains("!") {
        XCTAssert(fixit.title.starts(with: "force-unwrap using '!'"))
        expectedTextEdit.newText = "!"
        XCTAssertEqual(fixit.edit, WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil))
      } else {
        XCTAssert(fixit.title.starts(with: "chain the optional using '?'"))
        expectedTextEdit.newText = "?"
        XCTAssertEqual(fixit.edit, WorkspaceEdit(changes: [uri: [expectedTextEdit]], documentChanges: nil))
      }
      XCTAssertEqual(fixit.kind, .quickFix)
      XCTAssertEqual(fixit.diagnostics?.count, 1)
      XCTAssertEqual(fixit.diagnostics?.first?.severity, .error)
      XCTAssertEqual(fixit.diagnostics?.first?.range, Range(Position(line: 1, utf16index: 6)))
      XCTAssert(fixit.diagnostics?.first?.message.starts(with: "value of optional type") == true)
    }
  }

  func testMuliEditFixitCodeActionPrimary() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    var diagnostic: Diagnostic?
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            @available(*, introduced: 10, deprecated: 11)
            func foo() {}
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()

    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    diagnostic = semanticDiags.diagnostics.first

    let request = CodeActionRequest(
      range: Position(line: 0, utf16index: 1)..<Position(line: 0, utf16index: 10),
      context: CodeActionContext(
        diagnostics: [try XCTUnwrap(diagnostic, "expected diagnostic to be available")],
        only: nil
      ),
      textDocument: TextDocumentIdentifier(uri)
    )
    let response = try await testClient.send(request)

    XCTAssertNotNil(response)
    guard case .codeActions(let codeActions) = response else {
      XCTFail("Expected code actions as response")
      return
    }
    let quickFixes = codeActions.filter { $0.kind == .quickFix }
    XCTAssertEqual(quickFixes.count, 1)
    guard let fixit = quickFixes.first else { return }

    XCTAssertEqual(fixit.title, "Remove ': 10'...")
    XCTAssertEqual(fixit.diagnostics?.count, 1)
    XCTAssertEqual(
      fixit.edit?.changes?[uri],
      [
        TextEdit(range: Position(line: 0, utf16index: 24)..<Position(line: 0, utf16index: 28), newText: ""),
        TextEdit(range: Position(line: 0, utf16index: 40)..<Position(line: 0, utf16index: 44), newText: ""),
      ]
    )
  }

  func testMuliEditFixitCodeActionNote() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    var diagnostic: Diagnostic?
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 12,
          text: """
            @available(*, deprecated, renamed: "new(_:hotness:)")
            func old(and: Int, busted: Int) {}
            func test() {
              old(and: 1, busted: 2)
            }
            """
        )
      )
    )
    // syntactic diags
    _ = try await testClient.nextDiagnosticsNotification()
    let semanticDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(semanticDiags.diagnostics.count, 1)
    diagnostic = semanticDiags.diagnostics.first!

    let request = CodeActionRequest(
      range: Position(line: 3, utf16index: 2)..<Position(line: 3, utf16index: 2),
      context: CodeActionContext(
        diagnostics: [try XCTUnwrap(diagnostic, "expected diagnostic to be available")],
        only: nil
      ),
      textDocument: TextDocumentIdentifier(uri)
    )
    let response = try await testClient.send(request)

    XCTAssertNotNil(response)
    guard case .codeActions(let codeActions) = response else {
      XCTFail("Expected code actions as response")
      return
    }
    let quickFixes = codeActions.filter { $0.kind == .quickFix }
    XCTAssertEqual(quickFixes.count, 1)
    guard let fixit = quickFixes.first else { return }

    XCTAssertEqual(fixit.title, "use 'new(_:hotness:)' instead")
    XCTAssertEqual(fixit.diagnostics?.count, 1)
    XCTAssert(fixit.diagnostics?.first?.message.contains("is deprecated") == true)
    XCTAssertEqual(
      fixit.edit?.changes?[uri],
      [
        TextEdit(range: Position(line: 3, utf16index: 2)..<Position(line: 3, utf16index: 5), newText: "new"),
        TextEdit(range: Position(line: 3, utf16index: 6)..<Position(line: 3, utf16index: 11), newText: ""),
        TextEdit(range: Position(line: 3, utf16index: 14)..<Position(line: 3, utf16index: 20), newText: "hotness"),
      ]
    )
  }

  func testXMLToMarkdownDeclaration() {
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Declaration>func foo(_ bar: <Type usr="fake">Baz</Type>)</Declaration>
        """
      ),
      """
      ```swift
      func foo(_ bar: Baz)
      ```

      ---

      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Declaration>func foo() -&gt; <Type>Bar</Type></Declaration>
        """
      ),
      """
      ```swift
      func foo() -> Bar
      ```

      ---

      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Link href="https://example.com">My Link</Link>
        """
      ),
      """
      [My Link](https://example.com)
      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Link>My Invalid Link</Link>
        """
      ),
      """
      My Invalid Link
      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Declaration>func replacingOccurrences&lt;Target, Replacement&gt;(of target: Target, with replacement: Replacement, options: <Type usr="s:SS">String</Type>.<Type usr="s:SS10FoundationE14CompareOptionsa">CompareOptions</Type> = default, range searchRange: <Type usr="s:Sn">Range</Type>&lt;<Type usr="s:SS">String</Type>.<Type usr="s:SS5IndexV">Index</Type>&gt;? = default) -&gt; <Type usr="s:SS">String</Type> where Target : <Type usr="s:Sy">StringProtocol</Type>, Replacement : <Type usr="s:Sy">StringProtocol</Type></Declaration>
        """
      ),
      """
      ```swift
      func replacingOccurrences<Target, Replacement>(of target: Target, with replacement: Replacement, options: String.CompareOptions = default, range searchRange: Range<String.Index>? = default) -> String where Target : StringProtocol, Replacement : StringProtocol
      ```

      ---

      """
    )
  }

  func testXMLToMarkdownComment() {
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><Declaration>var foo</Declaration></Class>
        """
      ),
      """
      ```swift
      var foo
      ```

      ---

      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><Name>foo</Name><Declaration>var foo</Declaration></Class>
        """
      ),
      """
      ```swift
      var foo
      ```

      ---

      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><USR>asdf</USR><Declaration>var foo</Declaration><Name>foo</Name></Class>
        """
      ),
      """
      ```swift
      var foo
      ```

      ---

      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><Abstract>FOO</Abstract></Class>
        """
      ),
      """
      FOO
      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><Abstract>FOO</Abstract><Declaration>var foo</Declaration></Class>
        """
      ),
      """
      FOO

      ```swift
      var foo
      ```

      ---

      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><Abstract>FOO</Abstract><Discussion>BAR</Discussion></Class>
        """
      ),
      """
      FOO

      ### Discussion

      BAR
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><Para>A</Para><Para>B</Para><Para>C</Para></Class>
        """
      ),
      """
      A

      B

      C
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <CodeListing>a</CodeListing>
        """
      ),
      """
      ```
      a
      ```


      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <CodeListing><zCodeLineNumbered>a</zCodeLineNumbered></CodeListing>
        """
      ),
      """
      ```
      1.\ta
      ```


      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <CodeListing><zCodeLineNumbered>a</zCodeLineNumbered><zCodeLineNumbered>b</zCodeLineNumbered></CodeListing>
        """
      ),
      """
      ```
      1.\ta
      2.\tb
      ```


      """
    )
    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Class><CodeListing><zCodeLineNumbered>a</zCodeLineNumbered><zCodeLineNumbered>b</zCodeLineNumbered></CodeListing><CodeListing><zCodeLineNumbered>c</zCodeLineNumbered><zCodeLineNumbered>d</zCodeLineNumbered></CodeListing></Class>
        """
      ),
      """
      ```
      1.\ta
      2.\tb
      ```

      ```
      1.\tc
      2.\td
      ```


      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Para>a b c <codeVoice>d e f</codeVoice> g h i</Para>
        """
      ),
      """
      a b c `d e f` g h i
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Para>a b c <emphasis>d e f</emphasis> g h i</Para>
        """
      ),
      """
      a b c *d e f* g h i
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Para>a b c <bold>d e f</bold> g h i</Para>
        """
      ),
      """
      a b c **d e f** g h i
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Para>a b c<h1>d e f</h1>g h i</Para>
        """
      ),
      """
      a b c

      # d e f

      g h i
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <Para>a b c<h3>d e f</h3>g h i</Para>
        """
      ),
      """
      a b c

      ### d e f

      g h i
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        "<Class>" + "<Name>String</Name>" + "<USR>s:SS</USR>" + "<Declaration>struct String</Declaration>"
          + "<CommentParts>" + "<Abstract>" + "<Para>A Unicode s</Para>" + "</Abstract>" + "<Discussion>"
          + "<Para>A string is a series of characters, such as <codeVoice>&quot;Swift&quot;</codeVoice>, that forms a collection. "
          + "The <codeVoice>String</codeVoice> type bridges with the Objective-C class <codeVoice>NSString</codeVoice> and offers"
          + "</Para>" + "<Para>You can create new strings A <emphasis>string literal</emphasis> i" + "</Para>"
          + "<CodeListing language=\"swift\">"
          + "<zCodeLineNumbered><![CDATA[let greeting = \"Welcome!\"]]></zCodeLineNumbered>"
          + "<zCodeLineNumbered></zCodeLineNumbered>" + "</CodeListing>" + "<Para>...</Para>"
          + "<CodeListing language=\"swift\">"
          + "<zCodeLineNumbered><![CDATA[let greeting = \"Welcome!\"]]></zCodeLineNumbered>"
          + "<zCodeLineNumbered></zCodeLineNumbered>" + "</CodeListing>" + "</Discussion>" + "</CommentParts>"
          + "</Class>"
      ),
      """
      ```swift
      struct String
      ```

      ---
      A Unicode s

      ### Discussion

      A string is a series of characters, such as `"Swift"`, that forms a collection. The `String` type bridges with the Objective-C class `NSString` and offers

      You can create new strings A *string literal* i

      ```swift
      1.\tlet greeting = "Welcome!"
      2.\t
      ```

      ...

      ```swift
      1.\tlet greeting = "Welcome!"
      2.\t
      ```


      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        "<Function file=\"DocumentManager.swift\" line=\"92\" column=\"15\">" + "<CommentParts>"
          + "<Abstract><Para>Applies the given edits to the document.</Para></Abstract>" + "<Parameters>"
          + "<Parameter>" + "<Name>editCallback</Name>" + "<Direction isExplicit=\"0\">in</Direction>"
          + "<Discussion><Para>Optional closure to call for each edit.</Para></Discussion>" + "</Parameter>"
          + "<Parameter>" + "<Name>before</Name>" + "<Direction isExplicit=\"0\">in</Direction>"
          + "<Discussion><Para>The document contents <emphasis>before</emphasis> the edit is applied.</Para></Discussion>"
          + "</Parameter>" + "</Parameters>" + "</CommentParts>" + "</Function>"
      ),
      """
      Applies the given edits to the document.

      - Parameters:
          - editCallback: Optional closure to call for each edit.
          - before: The document contents *before* the edit is applied.
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <ResultDiscussion><Para>The contents of the file after all the edits are applied.</Para></ResultDiscussion>
        """
      ),
      """
      ### Returns

      The contents of the file after all the edits are applied.
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        """
        <ThrowsDiscussion><Para>Error.missingDocument if the document is not open.</Para></ThrowsDiscussion>
        """
      ),
      """
      ### Throws

      Error.missingDocument if the document is not open.
      """
    )

    XCTAssertEqual(
      try xmlDocumentationToMarkdown(
        "<Class>" + "<Name>S</Name>" + "<USR>s:1a1SV</USR>" + "<Declaration>struct S</Declaration>" + "<CommentParts>"
          + "<Discussion>" + #"<CodeListing language="swift">"# + "<zCodeLineNumbered>" + "<![CDATA[let S = 12456]]>"
          + "</zCodeLineNumbered>" + "<zCodeLineNumbered></zCodeLineNumbered>" + "</CodeListing>" + "<rawHTML>"
          + "<![CDATA[<h2>]]>" + "</rawHTML>Title<rawHTML>" + "<![CDATA[</h2>]]>" + "</rawHTML>"
          + "<Para>Details.</Para>" + "</Discussion>" + "</CommentParts>" + "</Class>"
      ),
      """
      ```swift
      struct S
      ```

      ---
      ### Discussion

      ```swift
      1.\tlet S = 12456
      2.\t
      ```

      <h2>Title</h2>

      Details.
      """
    )
  }

  func testSymbolInfo() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 1,
          text: """
            import Foundation
            struct S {
              func foo() {
                var local = 1
              }
            }
            """
        )
      )
    )

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 0, utf16index: 7)
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "Foundation")
        XCTAssertNil(sym.containerName)
        XCTAssertEqual(sym.usr, nil)
        XCTAssertEqual(sym.kind, .module)
        XCTAssertEqual(sym.bestLocalDeclaration?.uri, nil)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.line, nil)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.utf16index, nil)
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 1, utf16index: 7)
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "S")
        XCTAssertNil(sym.containerName)
        XCTAssertEqual(sym.usr, "s:1a1SV")
        XCTAssertEqual(sym.bestLocalDeclaration?.uri, uri)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.line, 1)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.utf16index, 7)
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 2, utf16index: 7)
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "foo()")
        XCTAssertNil(sym.containerName)
        XCTAssertEqual(sym.usr, "s:1a1SV3fooyyF")
        XCTAssertEqual(sym.bestLocalDeclaration?.uri, uri)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.line, 2)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.utf16index, 7)
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 3, utf16index: 8)
        )
      )

      XCTAssertEqual(resp.count, 1)
      if let sym = resp.first {
        XCTAssertEqual(sym.name, "local")
        XCTAssertNil(sym.containerName)
        XCTAssertEqual(sym.usr, "s:1a1SV3fooyyF5localL_Sivp")
        XCTAssertEqual(sym.bestLocalDeclaration?.uri, uri)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.line, 3)
        XCTAssertEqual(sym.bestLocalDeclaration?.range.lowerBound.utf16index, 8)
      }
    }

    do {
      let resp = try await testClient.send(
        SymbolInfoRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 3, utf16index: 0)
        )
      )

      XCTAssertEqual(resp.count, 0)
    }
  }

  func testHover() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 1,
          text: """
            /// This is a doc comment for S.
            ///
            /// Details.
            struct S {}
            """
        )
      )
    )

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 3, utf16index: 7)
        )
      )

      XCTAssertNotNil(resp)
      if let hover = resp {
        XCTAssertNil(hover.range)
        guard case .markupContent(let content) = hover.contents else {
          XCTFail("hover.contents is not .markupContents")
          return
        }
        XCTAssertEqual(content.kind, .markdown)
        XCTAssertEqual(
          content.value,
          """
          S
          ```swift
          struct S
          ```

          ---
          This is a doc comment for S.

          ### Discussion

          Details.
          """
        )
      }
    }

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 0, utf16index: 7)
        )
      )

      XCTAssertNil(resp)
    }
  }

  func testHoverNameEscaping() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: DocumentURI(url),
          language: .swift,
          version: 1,
          text: """
            /// this is **bold** documentation
            func test(_ a: Int, _ b: Int) { }
            /// this is *italic* documentation
            func *%*(lhs: String, rhs: String) { }
            """
        )
      )
    )

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 1, utf16index: 7)
        )
      )

      XCTAssertNotNil(resp)
      if let hover = resp {
        XCTAssertNil(hover.range)
        guard case .markupContent(let content) = hover.contents else {
          XCTFail("hover.contents is not .markupContents")
          return
        }
        XCTAssertEqual(content.kind, .markdown)
        XCTAssertEqual(
          content.value,
          ##"""
          test(\_:\_:)
          ```swift
          func test(_ a: Int, _ b: Int)
          ```

          ---
          this is **bold** documentation
          """##
        )
      }
    }

    do {
      let resp = try await testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 3, utf16index: 7)
        )
      )

      XCTAssertNotNil(resp)
      if let hover = resp {
        XCTAssertNil(hover.range)
        guard case .markupContent(let content) = hover.contents else {
          XCTFail("hover.contents is not .markupContents")
          return
        }
        XCTAssertEqual(content.kind, .markdown)
        XCTAssertEqual(
          content.value,
          ##"""
          \*%\*(\_:\_:)
          ```swift
          func *%* (lhs: String, rhs: String)
          ```

          ---
          this is *italic* documentation
          """##
        )
      }
    }
  }

  func testDocumentSymbolHighlight() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 1,
          text: """
            func test() {
              let a = 1
              let b = 2
              let ccc = 3
              _ = b
              _ = ccc + ccc
            }
            """
        )
      )
    )

    do {
      let resp = try await testClient.send(
        DocumentHighlightRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 0, utf16index: 0)
        )
      )
      XCTAssertEqual(resp?.count, 0)
    }

    do {
      let resp = try await testClient.send(
        DocumentHighlightRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 1, utf16index: 6)
        )
      )
      XCTAssertEqual(resp?.count, 1)
      if let highlight = resp?.first {
        XCTAssertEqual(highlight.range.lowerBound.line, 1)
        XCTAssertEqual(highlight.range.lowerBound.utf16index, 6)
        XCTAssertEqual(highlight.range.upperBound.line, 1)
        XCTAssertEqual(highlight.range.upperBound.utf16index, 7)
      }
    }

    do {
      let resp = try await testClient.send(
        DocumentHighlightRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 2, utf16index: 6)
        )
      )
      XCTAssertEqual(resp?.count, 2)
      if let highlight = resp?.first {
        XCTAssertEqual(highlight.range.lowerBound.line, 2)
        XCTAssertEqual(highlight.range.lowerBound.utf16index, 6)
        XCTAssertEqual(highlight.range.upperBound.line, 2)
        XCTAssertEqual(highlight.range.upperBound.utf16index, 7)
      }
      if let highlight = resp?.dropFirst().first {
        XCTAssertEqual(highlight.range.lowerBound.line, 4)
        XCTAssertEqual(highlight.range.lowerBound.utf16index, 6)
        XCTAssertEqual(highlight.range.upperBound.line, 4)
        XCTAssertEqual(highlight.range.upperBound.utf16index, 7)
      }
    }

    do {
      let resp = try await testClient.send(
        DocumentHighlightRequest(
          textDocument: TextDocumentIdentifier(url),
          position: Position(line: 3, utf16index: 6)
        )
      )
      XCTAssertEqual(resp?.count, 3)
      if let highlight = resp?.first {
        XCTAssertEqual(highlight.range.lowerBound.line, 3)
        XCTAssertEqual(highlight.range.lowerBound.utf16index, 6)
        XCTAssertEqual(highlight.range.upperBound.line, 3)
        XCTAssertEqual(highlight.range.upperBound.utf16index, 9)
      }
      if let highlight = resp?.dropFirst().first {
        XCTAssertEqual(highlight.range.lowerBound.line, 5)
        XCTAssertEqual(highlight.range.lowerBound.utf16index, 6)
        XCTAssertEqual(highlight.range.upperBound.line, 5)
        XCTAssertEqual(highlight.range.upperBound.utf16index, 9)
      }
      if let highlight = resp?.dropFirst(2).first {
        XCTAssertEqual(highlight.range.lowerBound.line, 5)
        XCTAssertEqual(highlight.range.lowerBound.utf16index, 12)
        XCTAssertEqual(highlight.range.upperBound.line, 5)
        XCTAssertEqual(highlight.range.upperBound.utf16index, 15)
      }
    }
  }

  func testEditorPlaceholderParsing() {
    var text = "<#basic placeholder" + "#>"  // Need to end this in another line so Xcode doesn't treat it as a real placeholder
    var data = EditorPlaceholder(text)
    XCTAssertNotNil(data)
    if let data = data {
      XCTAssertEqual(data, .basic("basic placeholder"))
      XCTAssertEqual(data.displayName, "basic placeholder")
    }
    text = "<#T##x: Int##Int" + "#>"
    data = EditorPlaceholder(text)
    XCTAssertNotNil(data)
    if let data = data {
      XCTAssertEqual(data, .typed(displayName: "x: Int", type: "Int", typeForExpansion: "Int"))
      XCTAssertEqual(data.displayName, "x: Int")
    }
    text = "<#T##x: Int##Blah##()->Int" + "#>"
    data = EditorPlaceholder(text)
    XCTAssertNotNil(data)
    if let data = data {
      XCTAssertEqual(data, .typed(displayName: "x: Int", type: "Blah", typeForExpansion: "()->Int"))
      XCTAssertEqual(data.displayName, "x: Int")
    }
    text = "<#T##Int" + "#>"
    data = EditorPlaceholder(text)
    XCTAssertNotNil(data)
    if let data = data {
      XCTAssertEqual(data, .typed(displayName: "Int", type: "Int", typeForExpansion: "Int"))
      XCTAssertEqual(data.displayName, "Int")
    }
    text = "<#foo"
    data = EditorPlaceholder(text)
    XCTAssertNil(data)
    text = " <#foo"
    data = EditorPlaceholder(text)
    XCTAssertNil(data)
    text = "foo"
    data = EditorPlaceholder(text)
    XCTAssertNil(data)
    text = "foo#>"
    data = EditorPlaceholder(text)
    XCTAssertNil(data)
    text = "<#foo#"
    data = EditorPlaceholder(text)
    XCTAssertNil(data)
    text = " <#foo" + "#>"
    data = EditorPlaceholder(text)
    XCTAssertNil(data)
  }

  func testIncrementalParse() async throws {
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    let reusedNodeCallback = self.expectation(description: "reused node callback called")
    var reusedNodes: [Syntax] = []
    let swiftLanguageServer =
      await testClient.server._languageService(for: uri, .swift, in: testClient.server.workspaceForDocument(uri: uri)!)
      as! SwiftLanguageServer
    await swiftLanguageServer.setReusedNodeCallback {
      reusedNodes.append($0)
      reusedNodeCallback.fulfill()
    }

    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: uri,
          language: .swift,
          version: 0,
          text: """
            func foo() {
            }
            class bar {
            }
            """
        )
      )
    )

    // Send a request that triggers a syntax tree to be built.
    _ = try await testClient.send(FoldingRangeRequest(textDocument: .init(uri)))

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: .init(uri, version: 1),
        contentChanges: [
          .init(range: Range(Position(line: 2, utf16index: 7)), text: "a")
        ]
      )
    )
    try await fulfillmentOfOrThrow([reusedNodeCallback])

    XCTAssertEqual(reusedNodes.count, 1)

    let firstNode = try XCTUnwrap(reusedNodes.first)
    XCTAssertEqual(
      firstNode.description,
      """
      func foo() {
      }
      """
    )
    XCTAssertEqual(firstNode.kind, .codeBlockItem)
  }
}
