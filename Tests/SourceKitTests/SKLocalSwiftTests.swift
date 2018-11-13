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

import LanguageServerProtocol
import SKSupport
import SKTestSupport
import XCTest

// Workaround ambiguity with Foundation.
typealias Notification = LanguageServerProtocol.Notification

@testable import SourceKit

final class SKLocalSwiftTests: XCTestCase {

  var connection: TestSourceKitServer! = nil
  var sk: TestClient! = nil

  /// The server's workspace data. Accessing this is unsafe if the server does so concurrently.
  var workspace: Workspace! = nil

  override func setUp() {
    connection = TestSourceKitServer()
    sk = connection.client
    _ = try! sk.sendSync(InitializeRequest(
        processId: nil,
        rootPath: nil,
        rootURL: nil,
        initializationOptions: nil,
        capabilities: ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))

    workspace = connection.server!.workspace!
  }

  override func tearDown() {
    workspace = nil
    sk = nil
    connection = nil
  }

  func testEditing() {

// FIXME: See comment on sendNoteSync.
#if os(macOS)
    let url = URL(fileURLWithPath: "/a.swift")

    sk.sendNoteSync(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: """
      func
      """
    )), { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for open - syntactic")
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual("func", self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for open - semantic")
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(
        note.params.diagnostics.first?.range.lowerBound,
        Position(line: 0, utf16index: 4))
    })

    sk.sendNoteSync(DidChangeTextDocument(textDocument: .init(url: url, version: 13), contentChanges: [
      .init(range: Range(Position(line: 0, utf16index: 4)), text: " foo() {}\n")
    ]), { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for edit 1 - syntactic")
      XCTAssertEqual(note.params.diagnostics.count, 0)
      XCTAssertEqual("func foo() {}\n", self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for edit 1 - semantic")
      XCTAssertEqual(note.params.diagnostics.count, 0)
    })

    sk.sendNoteSync(DidChangeTextDocument(textDocument: .init(url: url, version: 14), contentChanges: [
      .init(range: Range(Position(line: 1, utf16index: 0)), text: "_ = bar()")
      ]), { (note: Notification<PublishDiagnostics>) in
        log("Received diagnostics for edit 2 - syntactic")
        XCTAssertEqual(note.params.diagnostics.count, 0)
        XCTAssertEqual("""
        func foo() {}
        _ = bar()
        """, self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for edit 2 - semantic")
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(
        note.params.diagnostics.first?.range.lowerBound,
        Position(line: 1, utf16index: 4))
    })

    sk.sendNoteSync(DidChangeTextDocument(textDocument: .init(url: url, version: 14), contentChanges: [
      .init(range: Position(line: 1, utf16index: 4)..<Position(line: 1, utf16index: 7), text: "foo")
      ]), { (note: Notification<PublishDiagnostics>) in
        log("Received diagnostics for edit 3 - syntactic")
        XCTAssertEqual(note.params.diagnostics.count, 0)
        XCTAssertEqual("""
        func foo() {}
        _ = foo()
        """, self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for edit 3 - semantic")
      XCTAssertEqual(note.params.diagnostics.count, 0)
    })

    sk.sendNoteSync(DidChangeTextDocument(textDocument: .init(url: url, version: 15), contentChanges: [
      .init(range: Position(line: 1, utf16index: 4)..<Position(line: 1, utf16index: 7), text: "fooTypo")
      ]), { (note: Notification<PublishDiagnostics>) in
        log("Received diagnostics for edit 4 - syntactic")
        XCTAssertEqual(note.params.diagnostics.count, 0)
        XCTAssertEqual("""
        func foo() {}
        _ = fooTypo()
        """, self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for edit 4 - semantic")
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(
        note.params.diagnostics.first?.range.lowerBound,
        Position(line: 1, utf16index: 4))
    })

    sk.sendNoteSync(DidChangeTextDocument(textDocument: .init(url: url, version: 16), contentChanges: [
      .init(range: nil, text: """
      func bar() {}
      _ = foo()
      """)
      ]), { (note: Notification<PublishDiagnostics>) in
        log("Received diagnostics for edit 5 - syntactic")
        XCTAssertEqual(note.params.diagnostics.count, 0)
        XCTAssertEqual("""
        func bar() {}
        _ = foo()
        """, self.workspace.documentManager.latestSnapshot(url)!.text)
    }, { (note: Notification<PublishDiagnostics>) in
      log("Received diagnostics for edit 5 - semantic")
      XCTAssertEqual(note.params.diagnostics.count, 1)
      XCTAssertEqual(
        note.params.diagnostics.first?.range.lowerBound,
        Position(line: 1, utf16index: 4))
    })
#endif
  }

  func testCompletion() {
    let url = URL(fileURLWithPath: "/a.swift")
    sk.allowUnexpectedNotification = true

    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: .swift,
      version: 12,
      text: """
    struct S {
      var abc: Int

      func test(a: Int) {
        self.abc
      }
    }
    """)))

    let selfDot = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url: url),
      position: Position(line: 4, utf16index: 9)))

    XCTAssertEqual(selfDot.isIncomplete, false)
    XCTAssertGreaterThanOrEqual(selfDot.items.count, 2)
    let abc = selfDot.items.first { $0.label == "abc" }
    XCTAssertNotNil(abc)
    if let abc = abc {
      XCTAssertEqual(abc.kind, .property)
      XCTAssertNil(abc.detail)
      XCTAssertEqual(abc.filterText, "abc")
      // FIXME:
      XCTAssertNil(abc.textEdit)
      XCTAssertEqual(abc.insertText, "abc")
      XCTAssertEqual(abc.insertTextFormat, .snippet)
    }
    let test = selfDot.items.first { $0.label == "test(a: Int)" }
    XCTAssertNotNil(test)
    if let test = test {
      XCTAssertEqual(test.kind, .method)
      XCTAssertNil(test.detail)
      XCTAssertEqual(test.filterText, "test(a:)")
      // FIXME:
      XCTAssertNil(test.textEdit)
      // FIXME: should be "a" in the placeholder.
      XCTAssertEqual(test.insertText, "test(a: ${1:value})")
      XCTAssertEqual(test.insertTextFormat, .snippet)
    }

    for col in 10...12 {
      let inIdent = try! sk.sendSync(CompletionRequest(
        textDocument: TextDocumentIdentifier(url: url),
        position: Position(line: 4, utf16index: col)))
      // If we switch to server-side filtering this will change.
      XCTAssertEqual(inIdent, selfDot)
    }

    let after = try! sk.sendSync(CompletionRequest(
      textDocument: TextDocumentIdentifier(url: url),
      position: Position(line: 4, utf16index: 13)))
    XCTAssertNotEqual(after, selfDot)
  }

  func testXMLToMarkdownDeclaration() {
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Declaration>func foo(_ bar: <Type usr="fake">Baz</Type>)</Declaration>
      """), """
      ```
      func foo(_ bar: Baz)
      ```
      """)
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Declaration>func foo() -&gt; <Type>Bar</Type></Declaration>
      """), """
      ```
      func foo() -> Bar
      ```
      """)
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Declaration>func replacingOccurrences&lt;Target, Replacement&gt;(of target: Target, with replacement: Replacement, options: <Type usr="s:SS">String</Type>.<Type usr="s:SS10FoundationE14CompareOptionsa">CompareOptions</Type> = default, range searchRange: <Type usr="s:Sn">Range</Type>&lt;<Type usr="s:SS">String</Type>.<Type usr="s:SS5IndexV">Index</Type>&gt;? = default) -&gt; <Type usr="s:SS">String</Type> where Target : <Type usr="s:Sy">StringProtocol</Type>, Replacement : <Type usr="s:Sy">StringProtocol</Type></Declaration>
      """), """
      ```
      func replacingOccurrences<Target, Replacement>(of target: Target, with replacement: Replacement, options: String.CompareOptions = default, range searchRange: Range<String.Index>? = default) -> String where Target : StringProtocol, Replacement : StringProtocol
      ```
      """)
  }

  func testXMLToMarkdownComment() {
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><Declaration>var foo</Declaration></Class>
      """), """
      ```
      var foo
      ```
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><Name>foo</Name><Declaration>var foo</Declaration></Class>
      """), """
      ```
      var foo
      ```
      """)
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><USR>asdf</USR><Declaration>var foo</Declaration><Name>foo</Name></Class>
      """), """
      ```
      var foo
      ```
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><Abstract>FOO</Abstract></Class>
      """), """
      FOO
      """)
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><Abstract>FOO</Abstract><Declaration>var foo</Declaration></Class>
      """), """
      FOO

      ```
      var foo
      ```
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><Abstract>FOO</Abstract><Discussion>BAR</Discussion></Class>
      """), """
      FOO

      ### Discussion

      BAR
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><Para>A</Para><Para>B</Para><Para>C</Para></Class>
      """), """
      A

      B

      C
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <CodeListing>a</CodeListing>
      """), """
      ```
      a
      ```
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <CodeListing><zCodeLineNumbered>a</zCodeLineNumbered></CodeListing>
      """), """
      ```
      1.\ta
      ```
      """)
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <CodeListing><zCodeLineNumbered>a</zCodeLineNumbered><zCodeLineNumbered>b</zCodeLineNumbered></CodeListing>
      """), """
      ```
      1.\ta
      2.\tb
      ```
      """)
    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Class><CodeListing><zCodeLineNumbered>a</zCodeLineNumbered><zCodeLineNumbered>b</zCodeLineNumbered></CodeListing><CodeListing><zCodeLineNumbered>c</zCodeLineNumbered><zCodeLineNumbered>d</zCodeLineNumbered></CodeListing></Class>
      """), """
      ```
      1.\ta
      2.\tb
      ```

      ```
      1.\tc
      2.\td
      ```
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Para>a b c <codeVoice>d e f</codeVoice> g h i</Para>
      """), """
      a b c `d e f` g h i
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Para>a b c <emphasis>d e f</emphasis> g h i</Para>
      """), """
      a b c *d e f* g h i
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Para>a b c <bold>d e f</bold> g h i</Para>
      """), """
      a b c **d e f** g h i
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Para>a b c<h1>d e f</h1>g h i</Para>
      """), """
      a b c

      # d e f

      g h i
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <Para>a b c<h3>d e f</h3>g h i</Para>
      """), """
      a b c

      ### d e f

      g h i
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown(
      "<Class>" +
        "<Name>String</Name>" +
        "<USR>s:SS</USR>" +
        "<Declaration>struct String</Declaration>" +
        "<CommentParts>" +
          "<Abstract>" +
            "<Para>A Unicode s</Para>" +
          "</Abstract>" +
          "<Discussion>" +
            "<Para>A string is a series of characters, such as <codeVoice>&quot;Swift&quot;</codeVoice>, that forms a collection. " +
                  "The <codeVoice>String</codeVoice> type bridges with the Objective-C class <codeVoice>NSString</codeVoice> and offers" +
            "</Para>" +
            "<Para>You can create new strings A <emphasis>string literal</emphasis> i" +
            "</Para>" +
            "<CodeListing language=\"swift\">" +
              "<zCodeLineNumbered><![CDATA[let greeting = \"Welcome!\"]]></zCodeLineNumbered>" +
              "<zCodeLineNumbered></zCodeLineNumbered>" +
            "</CodeListing>" +
            "<Para>...</Para>" +
            "<CodeListing language=\"swift\">" +
              "<zCodeLineNumbered><![CDATA[let greeting = \"Welcome!\"]]></zCodeLineNumbered>" +
              "<zCodeLineNumbered></zCodeLineNumbered>" +
            "</CodeListing>" +
          "</Discussion>" +
        "</CommentParts>" +
      "</Class>"
      ), """
      ```
      struct String
      ```

      A Unicode s

      ### Discussion

      A string is a series of characters, such as `"Swift"`, that forms a collection. The `String` type bridges with the Objective-C class `NSString` and offers

      You can create new strings A *string literal* i

      ```
      1.\tlet greeting = "Welcome!"
      2.\t
      ```

      ...

      ```
      1.\tlet greeting = "Welcome!"
      2.\t
      ```
      """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown(
      "<Function file=\"DocumentManager.swift\" line=\"92\" column=\"15\">" +
        "<CommentParts>" +
          "<Abstract><Para>Applies the given edits to the document.</Para></Abstract>" +
          "<Parameters>" +
            "<Parameter>" +
              "<Name>editCallback</Name>" +
              "<Direction isExplicit=\"0\">in</Direction>" +
              "<Discussion><Para>Optional closure to call for each edit.</Para></Discussion>" +
            "</Parameter>" +
            "<Parameter>" +
              "<Name>before</Name>" +
              "<Direction isExplicit=\"0\">in</Direction>" +
              "<Discussion><Para>The document contents <emphasis>before</emphasis> the edit is applied.</Para></Discussion>" +
            "</Parameter>" +
          "</Parameters>" +
        "</CommentParts>" +
      "</Function>"), """
    Applies the given edits to the document.

    - Parameters:
        - editCallback: Optional closure to call for each edit.
        - before: The document contents *before* the edit is applied.
    """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <ResultDiscussion><Para>The contents of the file after all the edits are applied.</Para></ResultDiscussion>
      """), """
    ### Returns

    The contents of the file after all the edits are applied.
    """)

    XCTAssertEqual(try! xmlDocumentationToMarkdown("""
      <ThrowsDiscussion><Para>Error.missingDocument if the document is not open.</Para></ThrowsDiscussion>
      """), """
    ### Throws

    Error.missingDocument if the document is not open.
    """)
  }
}
