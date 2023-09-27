//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import LSPTestSupport
import SKTestSupport
import SourceKitLSP
import XCTest

private typealias Token = SyntaxHighlightingToken

final class SemanticTokensTests: XCTestCase {
  /// Connection and lifetime management for the service.
  private var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  private var sk: TestClient! = nil

  private var version: Int = 0

  private var uri: DocumentURI!
  private var textDocument: TextDocumentIdentifier { TextDocumentIdentifier(uri) }

  override func tearDown() {
    sk = nil
    connection = nil
  }

  override func setUp() {
    version = 0
    uri = DocumentURI(URL(fileURLWithPath: "/SemanticTokensTests/\(UUID()).swift"))
    connection = TestSourceKitServer()
    sk = connection.client
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(
        workspace: .init(
          semanticTokens: .init(
            refreshSupport: true
          )
        ),
        textDocument: .init(
          semanticTokens: .init(
            dynamicRegistration: true,
            requests: .init(
              range: .bool(true),
              full: .bool(true)
            ),
            tokenTypes: Token.Kind.allCases.map(\._lspName),
            tokenModifiers: Token.Modifiers.allModifiers.map { $0._lspName! },
            formats: [.relative]
          )
        )
      ),
      trace: .off,
      workspaceFolders: nil
    ))
  }

  private func expectSemanticTokensRefresh() -> XCTestExpectation {
    let refreshExpectation = expectation(description: "\(#function) - refresh received")
    sk.appendOneShotRequestHandler { (req: Request<WorkspaceSemanticTokensRefreshRequest>) in
      req.reply(VoidResponse())
      refreshExpectation.fulfill()
    }
    return refreshExpectation
  }

  private func openDocument(text: String) {
    // We will wait for the server to dynamically register semantic tokens

    let registerCapabilityExpectation = expectation(description: "\(#function) - register semantic tokens capability")
    sk.appendOneShotRequestHandler { (req: Request<RegisterCapabilityRequest>) in
      let registrations = req.params.registrations
      XCTAssert(registrations.contains { reg in
        reg.method == SemanticTokensRegistrationOptions.method
      })
      req.reply(VoidResponse())
      registerCapabilityExpectation.fulfill()
    }

    // We will wait for the first refresh request to make sure that the semantic tokens are ready

    let refreshExpectation = expectSemanticTokensRefresh()

    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: uri,
      language: .swift,
      version: version,
      text: text
    )))
    version += 1

    wait(for: [registerCapabilityExpectation, refreshExpectation], timeout: defaultTimeout)
  }

  private func editDocument(changes: [TextDocumentContentChangeEvent], expectRefresh: Bool = true) {
    // We wait for the semantic tokens again
    // Note that we assume to already have called openDocument before

    var expectations: [XCTestExpectation] = []

    if expectRefresh {
      expectations.append(expectSemanticTokensRefresh())
    }

    sk.send(DidChangeTextDocumentNotification(
      textDocument: VersionedTextDocumentIdentifier(
        uri,
        version: version
      ),
      contentChanges: changes
    ))
    version += 1

    wait(for: expectations, timeout: defaultTimeout)
  }

  private func editDocument(range: Range<Position>, text: String, expectRefresh: Bool = true) {
    editDocument(changes: [
      TextDocumentContentChangeEvent(
        range: range,
        text: text
      )
    ], expectRefresh: expectRefresh)
  }

  private func performSemanticTokensRequest(range: Range<Position>? = nil) throws -> [Token] {
    let response: DocumentSemanticTokensResponse!

    if let range = range {
      response = try sk.sendSync(DocumentSemanticTokensRangeRequest(textDocument: textDocument, range: range))
    } else {
      response = try sk.sendSync(DocumentSemanticTokensRequest(textDocument: textDocument))
    }

    return [Token](lspEncodedTokens: response.data)
  }

  private func openAndPerformSemanticTokensRequest(text: String, range: Range<Position>? = nil) throws -> [Token] {
    openDocument(text: text)
    return try performSemanticTokensRequest(range: range)
  }

  func testIntArrayCoding() {
    let tokens = [
      Token(
        start: Position(line: 2, utf16index: 3),
        utf16length: 5,
        kind: .string
      ),
      Token(
        start: Position(line: 4, utf16index: 2),
        utf16length: 1,
        kind: .interface,
        modifiers: [.deprecated, .definition]
      ),
    ]

    let encoded = tokens.lspEncoded
    XCTAssertEqual(encoded, [
      2, // line delta
      3, // char delta
      5, // length
      Token.Kind.string.rawValue, // kind
      0, // modifiers

      2, // line delta
      2, // char delta
      1, // length
      Token.Kind.interface.rawValue, // kind
      Token.Modifiers.deprecated.rawValue | Token.Modifiers.definition.rawValue, // modifiers
    ])

    let decoded = [Token](lspEncodedTokens: encoded)
    XCTAssertEqual(decoded, tokens)
  }

  func testRangeSplitting() async {
    let text = """
    struct X {
      let x: Int
      let y: String


    }
    """
    openDocument(text: text)

    guard let snapshot = await connection.server?._documentManager.latestSnapshot(uri) else {
      fatalError("Could not fetch document snapshot for \(#function)")
    }

    let empty = Position(line: 0, utf16index: 1)..<Position(line: 0, utf16index: 1)
    XCTAssertEqual(empty._splitToSingleLineRanges(in: snapshot), [])

    let multiLine = Position(line: 1, utf16index: 6)..<Position(line: 2, utf16index: 7)
    XCTAssertEqual(multiLine._splitToSingleLineRanges(in: snapshot), [
      Position(line: 1, utf16index: 6)..<Position(line: 1, utf16index: 12),
      Position(line: 2, utf16index: 0)..<Position(line: 2, utf16index: 7),
    ])

    let emptyLines = Position(line: 2, utf16index: 14)..<Position(line: 5, utf16index: 1)
    XCTAssertEqual(emptyLines._splitToSingleLineRanges(in: snapshot), [
      Position(line: 2, utf16index: 14)..<Position(line: 2, utf16index: 15),
      Position(line: 5, utf16index: 0)..<Position(line: 5, utf16index: 1),
    ])
  }

  func testEmpty() throws {
    let text = ""
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [])
  }

  func testRanged() throws {
    let text = """
    let x = 1
    let test = 20
    let abc = 333
    let y = 4
    """
    let start = Position(line: 1, utf16index: 0)
    let end = Position(line: 2, utf16index: 5)
    let tokens = try openAndPerformSemanticTokensRequest(text: text, range: start..<end)
    XCTAssertEqual(tokens, [
      Token(line: 1, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 1, utf16index: 4, length: 4, kind: .identifier),
      Token(line: 1, utf16index: 11, length: 2, kind: .number),
      Token(line: 2, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 2, utf16index: 4, length: 3, kind: .identifier),
    ])
  }

  func testLexicalTokens() throws {
    let text = """
    let x = 3
    var y = "test"
    /* abc */ // 123
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      // let x = 3
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 8, length: 1, kind: .number),
      // var y = "test"
      Token(line: 1, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 1, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 1, utf16index: 8, length: 6, kind: .string),
      // /* abc */ // 123
      Token(line: 2, utf16index: 0, length: 9, kind: .comment),
      Token(line: 2, utf16index: 10, length: 6, kind: .comment),
    ])
  }

  func testLexicalTokensForMultiLineComments() throws {
    let text = """
    let x = 3 /*
    let x = 12
    */
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 8, length: 1, kind: .number),
      // Multi-line comments are split into single-line tokens
      Token(line: 0, utf16index: 10, length: 2, kind: .comment),
      Token(line: 1, utf16index: 0, length: 10, kind: .comment),
      Token(line: 2, utf16index: 0, length: 2, kind: .comment),
    ])
  }

  func testLexicalTokensForDocComments() throws {
    let text = """
    /** abc */
      /// def
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 10, kind: .comment, modifiers: [.documentation]),
      Token(line: 1, utf16index: 2, length: 7, kind: .comment, modifiers: [.documentation]),
    ])
  }

  func testLexicalTokensForBackticks() throws {
    let text = """
    var `if` = 20
    let `else` = 3
    let `onLeft = ()
    let onRight` = ()
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      // var `if` = 20
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 4, kind: .identifier),
      Token(line: 0, utf16index: 11, length: 2, kind: .number),
      // let `else` = 3
      Token(line: 1, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 1, utf16index: 4, length: 6, kind: .identifier),
      Token(line: 1, utf16index: 13, length: 1, kind: .number),
      // let `onLeft = ()
      Token(line: 2, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 2, utf16index: 5, length: 6, kind: .identifier),
      // let onRight` = ()
      Token(line: 3, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 3, utf16index: 4, length: 7, kind: .identifier),
    ])
  }

  func testSemanticTokens() throws {
    let text = """
    struct X {}

    let x = X()
    let y = x + x

    func a() {}
    let b = {}

    a()
    b()
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      // struct X {}
      Token(line: 0, utf16index: 0, length: 6, kind: .keyword),
      Token(line: 0, utf16index: 7, length: 1, kind: .identifier),
      // let x = X()
      Token(line: 2, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 2, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 2, utf16index: 8, length: 1, kind: .struct),
      // let y = x + x
      Token(line: 3, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 3, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 3, utf16index: 8, length: 1, kind: .variable),
      Token(line: 3, utf16index: 10, length: 1, kind: .operator),
      Token(line: 3, utf16index: 12, length: 1, kind: .variable),
      // func a() {}
      Token(line: 5, utf16index: 0, length: 4, kind: .keyword),
      Token(line: 5, utf16index: 5, length: 1, kind: .identifier),
      // let b = {}
      Token(line: 6, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 6, utf16index: 4, length: 1, kind: .identifier),
      // a()
      Token(line: 8, utf16index: 0, length: 1, kind: .function),
      // b()
      Token(line: 9, utf16index: 0, length: 1, kind: .variable),
    ])
  }

  func testSemanticTokensForProtocols() throws {
    let text = """
    protocol X {}
    class Y: X {}

    let y: Y = X()

    func f<T: X>() {}
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      // protocol X {}
      Token(line: 0, utf16index: 0, length: 8, kind: .keyword),
      Token(line: 0, utf16index: 9, length: 1, kind: .identifier),
      // class Y: X {}
      Token(line: 1, utf16index: 0, length: 5, kind: .keyword),
      Token(line: 1, utf16index: 6, length: 1, kind: .identifier),
      Token(line: 1, utf16index: 9, length: 1, kind: .interface),
      // let y: Y = X()
      Token(line: 3, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 3, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 3, utf16index: 7, length: 1, kind: .class),
      Token(line: 3, utf16index: 11, length: 1, kind: .interface),
      // func f<T: X>() {}
      Token(line: 5, utf16index: 0, length: 4, kind: .keyword),
      Token(line: 5, utf16index: 5, length: 1, kind: .identifier),
      Token(line: 5, utf16index: 7, length: 1, kind: .identifier),
      Token(line: 5, utf16index: 10, length: 1, kind: .interface),
    ])
  }

  func testSemanticTokensForFunctionSignatures() throws {
    let text = "func f(x: Int, _ y: String) {}"
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 4, kind: .keyword),
      Token(line: 0, utf16index: 5, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 7, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 10, length: 3, kind: .struct, modifiers: .defaultLibrary),
      Token(line: 0, utf16index: 17, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 20, length: 6, kind: .struct, modifiers: .defaultLibrary),
    ])
  }

  func testSemanticTokensForFunctionSignaturesWithEmoji() throws {
    let text = "func x👍y() {}"
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 4, kind: .keyword),
      Token(line: 0, utf16index: 5, length: 4, kind: .identifier),
    ])
  }

  func testSemanticTokensForStaticMethods() throws {
    let text = """
    class X {
      deinit {}
      static func f() {}
      class func g() {}
    }
    X.f()
    X.g()
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      // class X
      Token(line: 0, utf16index: 0, length: 5, kind: .keyword),
      Token(line: 0, utf16index: 6, length: 1, kind: .identifier),
      // deinit {}
      Token(line: 1, utf16index: 2, length: 6, kind: .keyword),
      // static func f() {}
      Token(line: 2, utf16index: 2, length: 6, kind: .keyword),
      Token(line: 2, utf16index: 9, length: 4, kind: .keyword),
      Token(line: 2, utf16index: 14, length: 1, kind: .identifier),
      // class func g() {}
      Token(line: 3, utf16index: 2, length: 5, kind: .keyword),
      Token(line: 3, utf16index: 8, length: 4, kind: .keyword),
      Token(line: 3, utf16index: 13, length: 1, kind: .identifier),
      // X.f()
      Token(line: 5, utf16index: 0, length: 1, kind: .class),
      Token(line: 5, utf16index: 2, length: 1, kind: .method, modifiers: [.static]),
      // X.g()
      Token(line: 6, utf16index: 0, length: 1, kind: .class),
      Token(line: 6, utf16index: 2, length: 1, kind: .method, modifiers: [.static]),
    ])
  }

  func testSemanticTokensForEnumMembers() throws {
    let text = """
    enum Maybe<T> {
      case none
      case some(T)
    }

    let x = Maybe<String>.none
    let y: Maybe = .some(42)
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      // enum Maybe<T>
      Token(line: 0, utf16index: 0, length: 4, kind: .keyword),
      Token(line: 0, utf16index: 5, length: 5, kind: .identifier),
      Token(line: 0, utf16index: 11, length: 1, kind: .identifier),
      // case none
      Token(line: 1, utf16index: 2, length: 4, kind: .keyword),
      Token(line: 1, utf16index: 7, length: 4, kind: .identifier),
      // case some
      Token(line: 2, utf16index: 2, length: 4, kind: .keyword),
      Token(line: 2, utf16index: 7, length: 4, kind: .identifier),
      Token(line: 2, utf16index: 12, length: 1, kind: .typeParameter),
      // let x = Maybe<String>.none
      Token(line: 5, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 5, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 5, utf16index: 8, length: 5, kind: .enum),
      Token(line: 5, utf16index: 14, length: 6, kind: .struct, modifiers: .defaultLibrary),
      Token(line: 5, utf16index: 22, length: 4, kind: .enumMember),
      // let y: Maybe = .some(42)
      Token(line: 6, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 6, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 6, utf16index: 7, length: 5, kind: .enum),
      Token(line: 6, utf16index: 16, length: 4, kind: .enumMember),
      Token(line: 6, utf16index: 21, length: 2, kind: .number),
    ])
  }

  func testRegexSemanticTokens() throws {
    let text = """
      let r = /a[bc]*/
      """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 8, length: 8, kind: .regexp),
    ])
  }

  func testOperatorDeclaration() throws {
    let text = """
    infix operator ?= :ComparisonPrecedence
    """
    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 5, kind: .keyword),
      Token(line: 0, utf16index: 6, length: 8, kind: .keyword),
      Token(line: 0, utf16index: 15, length: 2, kind: .operator),
      Token(line: 0, utf16index: 19, length: 20, kind: .identifier),
    ])
  }

  func testEmptyEdit() throws {
    let text = """
    let x: String = "test"
    var y = 123
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()

    let pos = Position(line: 0, utf16index: 1)
    editDocument(range: pos..<pos, text: "", expectRefresh: false)

    let after = try performSemanticTokensRequest()
    XCTAssertEqual(before, after)
  }

  func testReplaceUntilMiddleOfToken() throws {
    let text = """
    var test = 4567
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()
    let expectedLeading = [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 4, kind: .identifier),
    ]
    XCTAssertEqual(before, expectedLeading + [
      Token(line: 0, utf16index: 11, length: 4, kind: .number),
    ])

    let start = Position(line: 0, utf16index: 10)
    let end = Position(line: 0, utf16index: 13)
    editDocument(range: start..<end, text: " 1")

    let after = try performSemanticTokensRequest()
    XCTAssertEqual(after, expectedLeading + [
      Token(line: 0, utf16index: 11, length: 3, kind: .number),
    ])
  }

  func testReplaceUntilEndOfToken() throws {
    let text = """
    fatalError("xyz")
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()
    XCTAssertEqual(before, [
      Token(line: 0, utf16index: 0, length: 10, kind: .function, modifiers: .defaultLibrary),
      Token(line: 0, utf16index: 11, length: 5, kind: .string),
    ])

    let start = Position(line: 0, utf16index: 10)
    let end = Position(line: 0, utf16index: 16)
    editDocument(range: start..<end, text: "(\"test\"")

    let after = try performSemanticTokensRequest()
    XCTAssertEqual(after, [
      Token(line: 0, utf16index: 0, length: 10, kind: .function, modifiers: .defaultLibrary),
      Token(line: 0, utf16index: 11, length: 6, kind: .string),
    ])
  }

  func testInsertSpaceBeforeToken() throws {
    let text = """
    let x: String = "test"
    """
    openDocument(text: text)

    let expectedBefore = [
      SyntaxHighlightingToken(line: 0, utf16index: 0, length: 3, kind: .keyword),
      SyntaxHighlightingToken(line: 0, utf16index: 4, length: 1, kind: .identifier),
      SyntaxHighlightingToken(line: 0, utf16index: 7, length: 6, kind: .struct, modifiers: [.defaultLibrary]),
      SyntaxHighlightingToken(line: 0, utf16index: 16, length: 6, kind: .string)
    ]
    let before = try performSemanticTokensRequest()
    XCTAssertEqual(before, expectedBefore)

    let pos = Position(line: 0, utf16index: 0)
    let editText = " "
    editDocument(range: pos..<pos, text: editText, expectRefresh: false)

    let after = try performSemanticTokensRequest()
    let expectedAfter = [
      SyntaxHighlightingToken(line: 0, utf16index: 1, length: 3, kind: .keyword),
      SyntaxHighlightingToken(line: 0, utf16index: 5, length: 1, kind: .identifier),
      SyntaxHighlightingToken(line: 0, utf16index: 8, length: 6, kind: .struct, modifiers: [.defaultLibrary]),
      SyntaxHighlightingToken(line: 0, utf16index: 17, length: 6, kind: .string)
    ]
    XCTAssertEqual(after, expectedAfter)
  }

  func testInsertSpaceAfterToken() throws {
    let text = """
    var x = 0
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()

    let pos = Position(line: 0, utf16index: 9)
    let editText = " "
    editDocument(range: pos..<pos, text: editText, expectRefresh: false)

    let after = try performSemanticTokensRequest()
    XCTAssertEqual(before, after)
  }

  func testInsertNewline() throws {
    let text = """
    fatalError("123")
    """
    openDocument(text: text)

    let expectedBefore = [
      SyntaxHighlightingToken(line: 0, utf16index: 0, length: 10, kind: .function, modifiers: [.defaultLibrary]),
      SyntaxHighlightingToken(line: 0, utf16index: 11, length: 5, kind: .string)
    ]
    let before = try performSemanticTokensRequest()
    XCTAssertEqual(before, expectedBefore)

    let pos = Position(line: 0, utf16index: 0)
    editDocument(range: pos..<pos, text: "\n", expectRefresh: false)

    let after = try performSemanticTokensRequest()
    let expectedAfter = [
      SyntaxHighlightingToken(line: 1, utf16index: 0, length: 10, kind: .function, modifiers: [.defaultLibrary]),
      SyntaxHighlightingToken(line: 1, utf16index: 11, length: 5, kind: .string)
    ]
    XCTAssertEqual(after, expectedAfter)
  }

  func testRemoveNewline() throws {
    let text = """
    let x =
            "abc"
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()
    let expectedBefore = [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 1, utf16index: 8, length: 5, kind: .string),
    ]
    XCTAssertEqual(before, expectedBefore)

    let start = Position(line: 0, utf16index: 7)
    let end = Position(line: 1, utf16index: 7)
    editDocument(range: start..<end, text: "", expectRefresh: false)

    let after = try performSemanticTokensRequest()
    let expectedAfter = [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 8, length: 5, kind: .string),
    ]
    XCTAssertEqual(after, expectedAfter)
  }

  func testInsertTokens() throws {
    let text = """
    let x =
            "abc"
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()
    let expectedBefore = [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 1, utf16index: 8, length: 5, kind: .string),
    ]
    XCTAssertEqual(before, expectedBefore)

    let start = Position(line: 0, utf16index: 7)
    let end = Position(line: 1, utf16index: 7)
    editDocument(range: start..<end, text: " \"test\" +", expectRefresh: true)

    let after = try performSemanticTokensRequest()
    let expectedAfter: [Token] = [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 8, length: 6, kind: .string),
      Token(line: 0, utf16index: 15, length: 1, kind: .method, modifiers: [.defaultLibrary, .static]),
      Token(line: 0, utf16index: 17, length: 5, kind: .string),
    ]
    XCTAssertEqual(after, expectedAfter)
  }

  func testSemanticMultiEdit() throws {
    let text = """
    let x = "abc"
    let y = x
    """
    openDocument(text: text)

    let before = try performSemanticTokensRequest()
    XCTAssertEqual(before, [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 0, utf16index: 8, length: 5, kind: .string),
      Token(line: 1, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 1, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 1, utf16index: 8, length: 1, kind: .variable),
    ])

    let newName = "renamed"
    editDocument(changes: [
      TextDocumentContentChangeEvent(
        range: Position(line: 0, utf16index: 4)..<Position(line: 0, utf16index: 5),
        text: newName
      ),
      TextDocumentContentChangeEvent(
        range: Position(line: 1, utf16index: 8)..<Position(line: 1, utf16index: 9),
        text: newName
      ),
    ], expectRefresh: true)

    let after = try performSemanticTokensRequest()
    XCTAssertEqual(after, [
      Token(line: 0, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 0, utf16index: 4, length: 7, kind: .identifier),
      Token(line: 0, utf16index: 14, length: 5, kind: .string),
      Token(line: 1, utf16index: 0, length: 3, kind: .keyword),
      Token(line: 1, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 1, utf16index: 8, length: 7, kind: .variable),
    ])
  }
  
  func testActor() throws {
    let text = """
    actor MyActor {}

    struct MyStruct {}

    func t(
        x: MyActor,
        y: MyStruct
    ) {}
    """

    let tokens = try openAndPerformSemanticTokensRequest(text: text)
    XCTAssertEqual(tokens, [
      Token(line: 0, utf16index: 0, length: 5, kind: .keyword),
      Token(line: 0, utf16index: 6, length: 7, kind: .identifier),
      Token(line: 2, utf16index: 0, length: 6, kind: .keyword),
      Token(line: 2, utf16index: 7, length: 8, kind: .identifier),
      Token(line: 4, utf16index: 0, length: 4, kind: .keyword),
      Token(line: 4, utf16index: 5, length: 1, kind: .identifier),
      Token(line: 5, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 5, utf16index: 7, length: 7, kind: .actor),
      Token(line: 6, utf16index: 4, length: 1, kind: .identifier),
      Token(line: 6, utf16index: 7, length: 8, kind: .struct)
    ])
  }
}

extension Token {
  fileprivate init(
    line: Int,
    utf16index: Int,
    length: Int,
    kind: Token.Kind,
    modifiers: Token.Modifiers = []
  ) {
    self.init(
      start: Position(line: line, utf16index: utf16index),
      utf16length: length,
      kind: kind,
      modifiers: modifiers
    )
  }
}
