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
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry
import XCTest

import class TSCBasic.Process

final class FormattingTests: XCTestCase {
  func testFormatting() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      struct S {
      var foo:  Int
      var bar: Int
      }
      """
    testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 3, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let formattedSource = apply(edits: edits, to: source)

    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })
    XCTAssertEqual(
      formattedSource,
      """
      struct S {
         var foo: Int
         var bar: Int
      }

      """
    )
  }

  func testFormattingNoEdits() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """
      struct S {
        var foo: Int
      }

      """,
      uri: uri
    )

    let response = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertEqual(edits.count, 0)
  }

  func testConfigFileOnDisk() async throws {
    // We pick up an invalid swift-format configuration file and thus don't set the user-provided options.
    let project = try await MultiFileTestProject(files: [
      ".swift-format": """
      {
        "version": 1,
        "indentation": {
          "spaces": 1
        }
      }
      """,
      "test.swift": """
      struct Root {
      1️⃣var bar = 123
      }

      """,
    ])
    let (uri, positions) = try project.openDocument("test.swift")

    let response = try await project.testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )
    XCTAssertEqual(
      response,
      [
        TextEdit(range: Range(positions["1️⃣"]), newText: " ")
      ]
    )
  }

  func testConfigFileInParentDirectory() async throws {
    // We pick up an invalid swift-format configuration file and thus don't set the user-provided options.
    let project = try await MultiFileTestProject(files: [
      ".swift-format": """
      {
        "version": 1,
        "indentation": {
          "spaces": 1
        }
      }
      """,
      "sub/test.swift": """
      struct Root {
      1️⃣var bar = 123
      }

      """,
    ])
    let (uri, positions) = try project.openDocument("test.swift")

    let response = try await project.testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )
    XCTAssertEqual(
      response,
      [
        TextEdit(range: Range(positions["1️⃣"]), newText: " ")
      ]
    )
  }

  func testConfigFileInNestedDirectory() async throws {
    // We pick up an invalid swift-format configuration file and thus don't set the user-provided options.
    let project = try await MultiFileTestProject(files: [
      ".swift-format": """
      {
        "version": 1,
        "indentation": {
          "spaces": 1
        }
      },
      """,
      "sub/.swift-format": """
      {
        "version": 1,
        "indentation": {
          "spaces": 3
        }
      }
      """,
      "sub/test.swift": """
      struct Root {
      1️⃣var bar = 123
      }

      """,
    ])
    let (uri, positions) = try project.openDocument("test.swift")

    let response = try await project.testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )
    XCTAssertEqual(
      response,
      [
        TextEdit(range: Range(positions["1️⃣"]), newText: "   ")
      ]
    )
  }

  func testInvalidConfigurationFile() async throws {
    // We pick up an invalid swift-format configuration file and thus don't set the user-provided options.
    // The swift-format default is 2 spaces.
    let project = try await MultiFileTestProject(files: [
      ".swift-format": "",
      "test.swift": """
      struct Root {
      1️⃣var bar = 123
      }

      """,
    ])
    let (uri, _) = try project.openDocument("test.swift")

    await assertThrowsError(
      try await project.testClient.send(
        DocumentFormattingRequest(
          textDocument: TextDocumentIdentifier(uri),
          options: FormattingOptions(tabSize: 3, insertSpaces: true)
        )
      )
    )
  }

  func testInsertAndRemove() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      public extension Example {
        func function() {}
      }

      """
    testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let formattedSource = apply(edits: edits, to: source)

    XCTAssertEqual(
      formattedSource,
      """
      extension Example {
        public func function() {}
      }

      """
    )
  }

  func testMultiLineStringInsertion() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = #"""
      _ = [
        Node(
          documentation: """
          Some great documentation
          of an amazing
          syntax node
          """,
          children: [
            Child(
              documentation: """
              The one and only child
              \#("")
              """
            )
          ]
        )
      ]

      """#
    testClient.openDocument(source, uri: uri)

    let response = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )

    let edits = try XCTUnwrap(response)
    let formattedSource = apply(edits: edits, to: source)
    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })

    XCTAssertEqual(
      formattedSource,
      #"""
      _ = [
        Node(
          documentation: """
            Some great documentation
            of an amazing
            syntax node
            """,
          children: [
            Child(
              documentation: """
                The one and only child

                """
            )
          ]
        )
      ]

      """#
    )
  }

  func testSwiftFormatCrashing() async throws {
    try await withTestScratchDir { scratchDir in
      let toolchain = try await unwrap(ToolchainRegistry.forTesting.default)

      let crashingExecutablePath = scratchDir.appending(component: "crashing-executable")
      try await createBinary(
        """
        fatalError()
        """,
        at: crashingExecutablePath
      )

      let toolchainRegistry = ToolchainRegistry(toolchains: [
        Toolchain(
          identifier: "\(toolchain.identifier)-crashing-swift-format",
          displayName: "\(toolchain.identifier) with crashing swift-format",
          path: toolchain.path,
          clang: toolchain.clang,
          swift: toolchain.swift,
          swiftc: toolchain.swiftc,
          swiftFormat: crashingExecutablePath,
          clangd: toolchain.clangd,
          sourcekitd: toolchain.sourcekitd,
          sourceKitClientPlugin: toolchain.sourceKitClientPlugin,
          sourceKitServicePlugin: toolchain.sourceKitServicePlugin,
          libIndexStore: toolchain.libIndexStore
        )
      ])
      let testClient = try await TestSourceKitLSPClient(toolchainRegistry: toolchainRegistry)
      let uri = DocumentURI(for: .swift)
      testClient.openDocument(
        // Generate a large source file to increase the chance of the executable we substitute for swift-format
        // crashing before the entire input file is sent to it.
        String(repeating: "func foo() {}\n", count: 10_000),
        uri: uri
      )
      await assertThrowsError(
        try await testClient.send(
          DocumentFormattingRequest(
            textDocument: TextDocumentIdentifier(uri),
            options: FormattingOptions(tabSize: 2, insertSpaces: true)
          )
        ),
        expectedMessage: #/Running swift-format failed|Writing to swift-format stdin failed/#
      )
    }
  }
}
