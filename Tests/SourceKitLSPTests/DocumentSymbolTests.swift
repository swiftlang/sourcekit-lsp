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
import LSPTestSupport
import SKTestSupport
import SourceKitLSP
import XCTest

final class DocumentSymbolTest: XCTestCase {
  typealias DocumentSymbolCapabilities = TextDocumentClientCapabilities.DocumentSymbol

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

override func tearDown() {
  sk = nil
  connection = nil
}

func initialize(capabilities: DocumentSymbolCapabilities) {
    connection = TestSourceKitServer()
    sk = connection.client
    var documentCapabilities = TextDocumentClientCapabilities()
    documentCapabilities.documentSymbol = capabilities
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil, textDocument: documentCapabilities),
      trace: .off,
      workspaceFolders: nil))
  }

  func performDocumentSymbolRequest(text: String) -> DocumentSymbolResponse {
    let url = URL(fileURLWithPath: "/\(#function)/a.swift")

    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: .swift,
      version: 17,
      text: text
    )))

    let request = DocumentSymbolRequest(textDocument: TextDocumentIdentifier(url))
    return try! sk.sendSync(request)!
  }

  func range(from startTuple: (Int, Int), to endTuple: (Int, Int)) -> Range<Position> {
    let startPos = Position(line: startTuple.0, utf16index: startTuple.1)
    let endPos = Position(line: endTuple.0, utf16index: endTuple.1)
    return startPos..<endPos
  }

  func testEmpty() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = ""
    let symbols = performDocumentSymbolRequest(text: text)
    XCTAssertEqual(symbols, .documentSymbols([]))
  }

  func testStruct() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = """
    struct Foo { }
    """
    let symbols = performDocumentSymbolRequest(text: text)

    XCTAssertEqual(symbols, .documentSymbols([
      DocumentSymbol(
        name: "Foo",
        detail: nil,
        kind: .struct,
        deprecated: nil,
        range: range(from: (0, 0), to: (0, 14)),
        selectionRange: range(from: (0, 7), to: (0, 10)),
        children: []
      ),
    ]))
  }

  func testUnicode() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = """
    struct Żółć { }
    struct 🍰 { }
    """
    let symbols = performDocumentSymbolRequest(text: text)

    // while not ascii, these are still single code unit
    let żółćRange = range(from: (0, 0), to: (0, 15))
    let żółćSelectionRange = range(from: (0, 7), to: (0, 11))
    // but cake is two utf-16 code units
    let cakeRange = range(from: (1, 0), to: (1, 13))
    let cakeSelectionRange = range(from: (1, 7), to: (1, 9))
    XCTAssertEqual(symbols, .documentSymbols([
      DocumentSymbol(
        name: "Żółć",
        detail: nil,
        kind: .struct,
        deprecated: nil,
        range: żółćRange,
        selectionRange: żółćSelectionRange,
        children: []
      ),
      DocumentSymbol(
        name: "🍰",
        detail: nil,
        kind: .struct,
        deprecated: nil,
        range: cakeRange,
        selectionRange: cakeSelectionRange,
        children: []
      ),
    ]))
  }

  func testEnum() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = """
    enum Foo {
      case first
      case second, third
      case fourth(Int), fifth
      func notACase() { }; case sixth
      case seventh, eight(Int, String)
      enum SubEnum {
        case a, b
      }
      case ninth(someName: Int)
    }
    """
    let symbols = performDocumentSymbolRequest(text: text)

    XCTAssertEqual(symbols, .documentSymbols([
      DocumentSymbol(
        name: "Foo",
        detail: nil,
        kind: .enum,
        deprecated: nil,
        range: range(from: (0, 0), to: (10, 1)),
        selectionRange: range(from: (0, 5), to: (0, 8)),
        children: [
          DocumentSymbol(
            name: "first",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (1, 7), to: (1, 12)),
            selectionRange: range(from: (1, 7), to: (1, 12)),
            children: []
          ),
          DocumentSymbol(
            name: "second",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (2, 7), to: (2, 13)),
            selectionRange: range(from: (2, 7), to: (2, 13)),
            children: []
          ),
          DocumentSymbol(
            name: "third",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (2, 15), to: (2, 20)),
            selectionRange: range(from: (2, 15), to: (2, 20)),
            children: []
          ),
          DocumentSymbol(
            name: "fourth(_:)",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (3, 7), to: (3, 18)),
            selectionRange: range(from: (3, 7), to: (3, 18)),
            children: []
          ),
          DocumentSymbol(
            name: "fifth",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (3, 20), to: (3, 25)),
            selectionRange: range(from: (3, 20), to: (3, 25)),
            children: []
          ),
          DocumentSymbol(
              name: "notACase()",
              detail: nil,
              kind: .method,
              deprecated: nil,
              range: range(from: (4, 2), to: (4, 21)),
              selectionRange: range(from: (4, 7), to: (4, 17)),
              children: []
          ),
          DocumentSymbol(
              name: "sixth",
              detail: nil,
              kind: .enumMember,
              deprecated: nil,
              range: range(from: (4, 28), to: (4, 33)),
              selectionRange: range(from: (4, 28), to: (4, 33)),
              children: []
          ),
          DocumentSymbol(
            name: "seventh",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (5, 7), to: (5, 14)),
            selectionRange: range(from: (5, 7), to: (5, 14)),
            children: []
          ),
          DocumentSymbol(
            name: "eight(_:_:)",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (5, 16), to: (5, 34)),
            selectionRange: range(from: (5, 16), to: (5, 34)),
            children: []
          ),
          DocumentSymbol(
            name: "SubEnum",
            detail: nil,
            kind: .enum,
            deprecated: nil,
            range: range(from: (6, 2), to: (8, 3)),
            selectionRange: range(from: (6, 7), to: (6, 14)),
            children: [
              DocumentSymbol(
                name: "a",
                detail: nil,
                kind: .enumMember,
                deprecated: nil,
                range: range(from: (7, 9), to: (7, 10)),
                selectionRange: range(from: (7, 9), to: (7, 10)),
                children: []
              ),
              DocumentSymbol(
                name: "b",
                detail: nil,
                kind: .enumMember,
                deprecated: nil,
                range: range(from: (7, 12), to: (7, 13)),
                selectionRange: range(from: (7, 12), to: (7, 13)),
                children: []
              )
            ]
          ),
          DocumentSymbol(
            name: "ninth(someName:)",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (9, 7), to: (9, 27)),
            selectionRange: range(from: (9, 7), to: (9, 27)),
            children: []
          )
        ]
      )
    ]))
  }

  func testAll() {
    let capabilities = DocumentSymbolCapabilities()
    initialize(capabilities: capabilities)

    let text = """
    // struct ThisIsCommentedOut { }
    /* struct ThisOneToo { } */
    extension Int { }
    struct Struct { }
    class Class { }
    enum Enum { case enumMember }
    protocol Interface { func f() }
    func function() { }
    var variable = 0
    let constant = 0
    var computedVariable: Int { return 0 }
    func +(lhs: Struct, rhs: Struct) { }
    prefix func -(rhs: Struct) { }
    func f<TypeParameter>(type: TypeParameter.Type) { }
    struct S<TypeParameter> { }
    class Foo {
      func method() { }
      static func staticMethod() { }
      class func classMethod() { }
      var property = 0
      let constantProperty = 0
      var computedProperty: Int { return 0 }
      init() { }
      static var staticProperty = 0
      static let staticConstantProperty = 0
      static var staticComputedProperty: Int { return 0 }
      class var classProperty: Int { return 0 }
      func f() {
        let localConstant = 0
        var localVariable = 0
        var localComputedVariable: Int { return 0 }
        func localFunction() { }
      }
    }
    """
    let symbols = performDocumentSymbolRequest(text: text)

    XCTAssertEqual(symbols, .documentSymbols([
      DocumentSymbol(
        name: "Int",
        detail: nil,
        kind: .namespace,
        deprecated: nil,
        range: range(from: (2, 0), to: (2, 17)),
        selectionRange: range(from: (2, 10), to: (2, 13)),
        children: []
      ),
      DocumentSymbol(
        name: "Struct",
        detail: nil,
        kind: .struct,
        deprecated: nil,
        range: range(from: (3, 0), to: (3, 17)),
        selectionRange: range(from: (3, 7), to: (3, 13)),
        children: []
      ),
      DocumentSymbol(
        name: "Class",
        detail: nil,
        kind: .class,
        deprecated: nil,
        range: range(from: (4, 0), to: (4, 15)),
        selectionRange: range(from: (4, 6), to: (4, 11)),
        children: []
      ),
      DocumentSymbol(
        name: "Enum",
        detail: nil,
        kind: .enum,
        deprecated: nil,
        range: range(from: (5, 0), to: (5, 29)),
        selectionRange: range(from: (5, 5), to: (5, 9)),
        children: [
          DocumentSymbol(
            name: "enumMember",
            detail: nil,
            kind: .enumMember,
            deprecated: nil,
            range: range(from: (5, 17), to: (5, 27)),
            selectionRange: range(from: (5, 17), to: (5, 27)),
            children: []
          )
        ]
      ),
      DocumentSymbol(
        name: "Interface",
        detail: nil,
        kind: .interface,
        deprecated: nil,
        range: range(from: (6, 0), to: (6, 31)),
        selectionRange: range(from: (6, 9), to: (6, 18)),
        children: [
          DocumentSymbol(
            name: "f()",
            detail: nil,
            kind: .method,
            deprecated: nil,
            range: range(from: (6, 21), to: (6, 29)),
            selectionRange: range(from: (6, 26), to: (6, 29)),
            children: []
          )
        ]
      ),
      DocumentSymbol(
        name: "function()",
        detail: nil,
        kind: .function,
        deprecated: nil,
        range: range(from: (7, 0), to: (7, 19)),
        selectionRange: range(from: (7, 5), to: (7, 15)),
        children: []
      ),
      DocumentSymbol(
        name: "variable",
        detail: nil,
        kind: .variable,
        deprecated: nil,
        range: range(from: (8, 0), to: (8, 16)),
        selectionRange: range(from: (8, 4), to: (8, 12)),
        children: []
      ),
      DocumentSymbol(
        name: "constant",
        detail: nil,
        kind: .variable,
        deprecated: nil,
        range: range(from: (9, 0), to: (9, 16)),
        selectionRange: range(from: (9, 4), to: (9, 12)),
        children: []
      ),
      DocumentSymbol(
        name: "computedVariable",
        detail: nil,
        kind: .variable,
        deprecated: nil,
        range: range(from: (10, 0), to: (10, 38)),
        selectionRange: range(from: (10, 4), to: (10, 20)),
        children: []
      ),
      DocumentSymbol(
        name: "+(_:_:)",
        detail: nil,
        kind: .function,
        deprecated: nil,
        range: range(from: (11, 0), to: (11, 36)),
        selectionRange: range(from: (11, 5), to: (11, 32)),
        children: []
      ),
      DocumentSymbol(
        name: "-(_:)",
        detail: nil,
        kind: .function,
        deprecated: nil,
        range: range(from: (12, 7), to: (12, 30)),
        selectionRange: range(from: (12, 12), to: (12, 26)),
        children: []
      ),
      DocumentSymbol(
        name: "f(type:)",
        detail: nil,
        kind: .function,
        deprecated: nil,
        range: range(from: (13, 0), to: (13, 51)),
        selectionRange: range(from: (13, 5), to: (13, 47)),
        children: [
          DocumentSymbol(
            name: "TypeParameter",
            detail: nil,
            kind: .typeParameter,
            deprecated: nil,
            range: range(from: (13, 7), to: (13, 20)),
            selectionRange: range(from: (13, 7), to: (13, 20)),
            children: []
          )
        ]
      ),
      DocumentSymbol(
        name: "S",
        detail: nil,
        kind: .struct,
        deprecated: nil,
        range: range(from: (14, 0), to: (14, 27)),
        selectionRange: range(from: (14, 7), to: (14, 8)),
        children: [
          DocumentSymbol(
            name: "TypeParameter",
            detail: nil,
            kind: .typeParameter,
            deprecated: nil,
            range: range(from: (14, 9), to: (14, 22)),
            selectionRange: range(from: (14, 9), to: (14, 22)),
            children: []
          )
        ]
      ),
      DocumentSymbol(
        name: "Foo",
        detail: nil,
        kind: .class,
        deprecated: nil,
        range: range(from: (15, 0), to: (33, 1)),
        selectionRange: range(from: (15, 6), to: (15, 9)),
        children: [
          DocumentSymbol(
            name: "method()",
            detail: nil,
            kind: .method,
            deprecated: nil,
            range: range(from: (16, 2), to: (16, 19)),
            selectionRange: range(from: (16, 7), to: (16, 15)),
            children: []
          ),
          DocumentSymbol(
            name: "staticMethod()",
            detail: nil,
            kind: .method,
            deprecated: nil,
            range: range(from: (17, 2), to: (17, 32)),
            selectionRange: range(from: (17, 14), to: (17, 28)),
            children: []
          ),
          DocumentSymbol(
            name: "classMethod()",
            detail: nil,
            kind: .method,
            deprecated: nil,
            range: range(from: (18, 2), to: (18, 30)),
            selectionRange: range(from: (18, 13), to: (18, 26)),
            children: []
          ),
          DocumentSymbol(
            name: "property",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (19, 2), to: (19, 18)),
            selectionRange: range(from: (19, 6), to: (19, 14)),
            children: []
          ),
          DocumentSymbol(
            name: "constantProperty",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (20, 2), to: (20, 26)),
            selectionRange: range(from: (20, 6), to: (20, 22)),
            children: []
          ),
          DocumentSymbol(
            name: "computedProperty",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (21, 2), to: (21, 40)),
            selectionRange: range(from: (21, 6), to: (21, 22)),
            children: []
          ),
          DocumentSymbol(
            name: "init()",
            detail: nil,
            kind: .method,
            deprecated: nil,
            range: range(from: (22, 2), to: (22, 12)),
            selectionRange: range(from: (22, 2), to: (22, 8)),
            children: []
          ),
          DocumentSymbol(
            name: "staticProperty",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (23, 2), to: (23, 31)),
            selectionRange: range(from: (23, 13), to: (23, 27)),
            children: []
          ),
          DocumentSymbol(
            name: "staticConstantProperty",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (24, 2), to: (24, 39)),
            selectionRange: range(from: (24, 13), to: (24, 35)),
            children: []
          ),
          DocumentSymbol(
            name: "staticComputedProperty",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (25, 2), to: (25, 53)),
            selectionRange: range(from: (25, 13), to: (25, 35)),
            children: []
          ),
          DocumentSymbol(
            name: "classProperty",
            detail: nil,
            kind: .property,
            deprecated: nil,
            range: range(from: (26, 2), to: (26, 43)),
            selectionRange: range(from: (26, 12), to: (26, 25)),
            children: []
          ),
          DocumentSymbol(
            name: "f()",
            detail: nil,
            kind: .method,
            deprecated: nil,
            range: range(from: (27, 2), to: (32, 3)),
            selectionRange: range(from: (27, 7), to: (27, 10)),
            children: [
              DocumentSymbol(
                name: "localConstant",
                detail: nil,
                kind: .variable,
                deprecated: nil,
                range: range(from: (28, 4), to: (28, 25)),
                selectionRange: range(from: (28, 8), to: (28, 21)),
                children: []
              ),
              DocumentSymbol(
                name: "localVariable",
                detail: nil,
                kind: .variable,
                deprecated: nil,
                range: range(from: (29, 4), to: (29, 25)),
                selectionRange: range(from: (29, 8), to: (29, 21)),
                children: []
              ),
              DocumentSymbol(
                name: "localComputedVariable",
                detail: nil,
                kind: .variable,
                deprecated: nil,
                range: range(from: (30, 4), to: (30, 47)),
                selectionRange: range(from: (30, 8), to: (30, 29)),
                children: []
              ),
              DocumentSymbol(
                name: "localFunction()",
                detail: nil,
                kind: .function,
                deprecated: nil,
                range: range(from: (31, 4), to: (31, 28)),
                selectionRange: range(from: (31, 9), to: (31, 24)),
                children: []
              )
            ]
          )
        ]
      )
    ]))
  }
}
