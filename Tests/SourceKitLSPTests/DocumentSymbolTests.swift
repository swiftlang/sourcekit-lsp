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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import XCTest

final class DocumentSymbolTests: XCTestCase {
  override func setUp() async throws {
    LoggingScope.configureDefaultLoggingSubsystem("org.swift.sourcekit-lsp-tests")
  }

  // MARK: - Tests

  func testEmpty() async throws {
    try await assertDocumentSymbols("") { positions in [] }
  }

  func testUnicode1() async throws {
    try await assertDocumentSymbols("1️⃣struct 2️⃣Żółć3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "Żółć",
          detail: nil,
          kind: .struct,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testUnicode2() async throws {
    try await assertDocumentSymbols("1️⃣struct 2️⃣🍰3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "🍰",
          detail: nil,
          kind: .struct,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testEnumCase() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣enum 2️⃣Foo3️⃣ {
        case 4️⃣first5️⃣, 6️⃣second7️⃣
      }8️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .enum,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["8️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "first",
              detail: nil,
              kind: .enumMember,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            ),
            DocumentSymbol(
              name: "second",
              detail: nil,
              kind: .enumMember,
              deprecated: nil,
              range: positions["6️⃣"]..<positions["7️⃣"],
              selectionRange: positions["6️⃣"]..<positions["7️⃣"],
              children: []
            ),
          ]
        )
      ]
    }
  }

  func testEnumCaseWithAssociatedValue() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣enum 2️⃣Foo3️⃣ {
        case 4️⃣first(Int)5️⃣
      }6️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .enum,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["6️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "first(_:)",
              detail: nil,
              kind: .enumMember,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testEnumCaseWithNamedAssociatedValue() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣enum 2️⃣Foo3️⃣ {
        case 4️⃣first(someName: Int)5️⃣
      }6️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .enum,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["6️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "first(someName:)",
              detail: nil,
              kind: .enumMember,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testExtension() async throws {
    try await assertDocumentSymbols(
      """
      // struct ThisIsCommentedOut { }
      /* struct ThisOneToo { } */
      1️⃣extension 2️⃣Int3️⃣ { }4️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Int",
          detail: nil,
          kind: .namespace,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testStruct() async throws {
    try await assertDocumentSymbols("1️⃣struct 2️⃣Struct3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "Struct",
          detail: nil,
          kind: .struct,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testClass() async throws {
    try await assertDocumentSymbols("1️⃣class 2️⃣Class3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "Class",
          detail: nil,
          kind: .class,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testEnum() async throws {
    try await assertDocumentSymbols("1️⃣enum 2️⃣Enum3️⃣ { case 4️⃣enumMember5️⃣ }6️⃣") { positions in
      [
        DocumentSymbol(
          name: "Enum",
          detail: nil,
          kind: .enum,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["6️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "enumMember",
              detail: nil,
              kind: .enumMember,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testProtocol() async throws {
    try await assertDocumentSymbols("1️⃣protocol 2️⃣Interface3️⃣ { 4️⃣func 5️⃣f()6️⃣ }7️⃣") { positions in
      [
        DocumentSymbol(
          name: "Interface",
          detail: nil,
          kind: .interface,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["7️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "f()",
              detail: nil,
              kind: .method,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["6️⃣"],
              selectionRange: positions["5️⃣"]..<positions["6️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testFunction() async throws {
    try await assertDocumentSymbols("1️⃣func 2️⃣function()3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "function()",
          detail: nil,
          kind: .function,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testVariable() async throws {
    try await assertDocumentSymbols("1️⃣var 2️⃣variable3️⃣ = 04️⃣") { positions in
      [
        DocumentSymbol(
          name: "variable",
          detail: nil,
          kind: .variable,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testMultiplePatternsInVariable() async throws {
    try await assertDocumentSymbols("var 1️⃣varA2️⃣: Int,3️⃣ 4️⃣varB5️⃣ = 06️⃣") { positions in
      [
        DocumentSymbol(
          name: "varA",
          detail: nil,
          kind: .variable,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["3️⃣"],
          selectionRange: positions["1️⃣"]..<positions["2️⃣"],
          children: []
        ),
        DocumentSymbol(
          name: "varB",
          detail: nil,
          kind: .variable,
          deprecated: nil,
          range: positions["4️⃣"]..<positions["6️⃣"],
          selectionRange: positions["4️⃣"]..<positions["5️⃣"],
          children: []
        ),
      ]
    }
  }

  func testConstant() async throws {
    try await assertDocumentSymbols("1️⃣let 2️⃣constant3️⃣ = 04️⃣") { positions in
      [
        DocumentSymbol(
          name: "constant",
          detail: nil,
          kind: .variable,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testComputedVariable() async throws {
    try await assertDocumentSymbols("1️⃣var 2️⃣computedVariable3️⃣: Int { return 0 }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "computedVariable",
          detail: nil,
          kind: .variable,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testOperatorFunc() async throws {
    try await assertDocumentSymbols("1️⃣func 2️⃣+(lhs: Struct, rhs: Struct)3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "+(lhs:rhs:)",
          detail: nil,
          kind: .operator,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testPrefixOperatorFunc() async throws {
    try await assertDocumentSymbols("1️⃣prefix func 2️⃣-(rhs: Struct)3️⃣ { }4️⃣") { positions in
      [
        DocumentSymbol(
          name: "-(rhs:)",
          detail: nil,
          kind: .operator,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testGenericFunc() async throws {
    try await assertDocumentSymbols("1️⃣func 2️⃣f<3️⃣TypeParameter4️⃣>(type: TypeParameter.Type)5️⃣ { }6️⃣") { positions in
      [
        DocumentSymbol(
          name: "f(type:)",
          detail: nil,
          kind: .function,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["6️⃣"],
          selectionRange: positions["2️⃣"]..<positions["5️⃣"],
          children: [
            DocumentSymbol(
              name: "TypeParameter",
              detail: nil,
              kind: .typeParameter,
              deprecated: nil,
              range: positions["3️⃣"]..<positions["4️⃣"],
              selectionRange: positions["3️⃣"]..<positions["4️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testGenericStruct() async throws {
    try await assertDocumentSymbols("1️⃣struct 2️⃣S3️⃣<4️⃣TypeParameter5️⃣> { }6️⃣") { positions in
      [
        DocumentSymbol(
          name: "S",
          detail: nil,
          kind: .struct,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["6️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "TypeParameter",
              detail: nil,
              kind: .typeParameter,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testClassFunction() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣class 2️⃣Foo3️⃣ {
        4️⃣func 5️⃣method()6️⃣ { }7️⃣
      }8️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .class,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["8️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "method()",
              detail: nil,
              kind: .method,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["7️⃣"],
              selectionRange: positions["5️⃣"]..<positions["6️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testStaticClassFunction() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣class 2️⃣Foo3️⃣ {
        4️⃣static func 5️⃣staticMethod()6️⃣ { }7️⃣
      }8️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .class,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["8️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "staticMethod()",
              detail: nil,
              kind: .method,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["7️⃣"],
              selectionRange: positions["5️⃣"]..<positions["6️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testStaticClassProperty() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣class 2️⃣Foo3️⃣ {
        4️⃣var 5️⃣property6️⃣ = 07️⃣
      }8️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .class,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["8️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "property",
              detail: nil,
              kind: .property,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["7️⃣"],
              selectionRange: positions["5️⃣"]..<positions["6️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testInitializer() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣class 2️⃣Foo3️⃣ {
        4️⃣init()5️⃣ { }6️⃣
      }7️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .class,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["7️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "init()",
              detail: nil,
              kind: .constructor,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["6️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testInitializerWithParameters() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣class 2️⃣Foo3️⃣ {
        4️⃣init(_ first: Int, second: Int)5️⃣ { }6️⃣
      }7️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          detail: nil,
          kind: .class,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["7️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "init(_:second:)",
              detail: nil,
              kind: .constructor,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["6️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testLocalVariable() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣func 2️⃣f()3️⃣ {
        let localConstant = 0
      }4️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "f()",
          detail: nil,
          kind: .function,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["4️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: []
        )
      ]
    }
  }

  func testLocalFunction() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣func 2️⃣f()3️⃣ {
        4️⃣func 5️⃣localFunction()6️⃣ { }7️⃣
      }8️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "f()",
          detail: nil,
          kind: .function,
          deprecated: nil,
          range: positions["1️⃣"]..<positions["8️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "localFunction()",
              detail: nil,
              kind: .function,
              deprecated: nil,
              range: positions["4️⃣"]..<positions["7️⃣"],
              selectionRange: positions["5️⃣"]..<positions["6️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }

  func testIncludeMarkComments() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣// MARK: Marker2️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Marker",
          kind: .namespace,
          range: positions["1️⃣"]..<positions["2️⃣"],
          selectionRange: positions["1️⃣"]..<positions["2️⃣"]
        )
      ]
    }

    try await assertDocumentSymbols(
      """
      1️⃣// MARK: - Marker2️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "- Marker",
          kind: .namespace,
          range: positions["1️⃣"]..<positions["2️⃣"],
          selectionRange: positions["1️⃣"]..<positions["2️⃣"]
        )
      ]
    }

    try await assertDocumentSymbols(
      """
      1️⃣/* MARK: Marker */2️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Marker",
          kind: .namespace,
          range: positions["1️⃣"]..<positions["2️⃣"],
          selectionRange: positions["1️⃣"]..<positions["2️⃣"]
        )
      ]
    }
  }

  func testNestedMarkComment() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣struct 2️⃣Foo3️⃣ {
        4️⃣// MARK: Marker5️⃣
      }6️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          kind: .struct,
          range: positions["1️⃣"]..<positions["6️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "Marker",
              kind: .namespace,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"]
            )
          ]
        )
      ]
    }
  }

  func testNestedMarkCommentFollowedAttachedToChild() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣struct 2️⃣Foo3️⃣ {
        4️⃣// MARK: Marker5️⃣
        6️⃣func 7️⃣myFunc()8️⃣  { }9️⃣
      }🔟
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          kind: .struct,
          range: positions["1️⃣"]..<positions["🔟"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "Marker",
              kind: .namespace,
              range: positions["4️⃣"]..<positions["5️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"]
            ),
            DocumentSymbol(
              name: "myFunc()",
              kind: .method,
              range: positions["6️⃣"]..<positions["9️⃣"],
              selectionRange: positions["7️⃣"]..<positions["8️⃣"],
              children: []
            ),
          ]
        )
      ]
    }
  }

  func testShowDeinit() async throws {
    try await assertDocumentSymbols(
      """
      1️⃣class 2️⃣Foo3️⃣ {
        4️⃣deinit5️⃣ {
        }6️⃣
      }7️⃣
      """
    ) { positions in
      [
        DocumentSymbol(
          name: "Foo",
          kind: .class,
          range: positions["1️⃣"]..<positions["7️⃣"],
          selectionRange: positions["2️⃣"]..<positions["3️⃣"],
          children: [
            DocumentSymbol(
              name: "deinit",
              kind: .constructor,
              range: positions["4️⃣"]..<positions["6️⃣"],
              selectionRange: positions["4️⃣"]..<positions["5️⃣"],
              children: []
            )
          ]
        )
      ]
    }
  }
}

private func assertDocumentSymbols(
  _ markedText: String,
  _ expectedDocumentSymbols: (DocumentPositions) -> [DocumentSymbol],
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: .swift)

  let positions = testClient.openDocument(markedText, uri: uri)
  let symbols = try unwrap(try await testClient.send(DocumentSymbolRequest(textDocument: TextDocumentIdentifier(uri))))

  XCTAssertEqual(symbols, .documentSymbols(expectedDocumentSymbols(positions)), file: file, line: line)
}
