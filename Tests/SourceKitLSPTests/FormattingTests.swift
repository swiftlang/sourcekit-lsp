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

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKTestSupport
import SKUtilities
import SourceKitLSP
import SwiftExtensions
import SwiftLanguageService
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import class TSCBasic.Process

private func makeSnapshot(_ text: String, uri: DocumentURI = DocumentURI(for: .swift)) -> DocumentSnapshot {
  DocumentSnapshot(
    uri: uri,
    language: .swift,
    version: 0,
    lineTable: LineTable(text),
    origin: .openDocument
  )
}

final class FormattingTests: SourceKitLSPTestCase {
  /// End-to-end smoke test exercising the real `swift-format` executable without encoding specific formatting choices:
  /// formatting an unformatted document must preserve non-whitespace tokens and reach a fixed point (`[]` on a second
  /// formatting pass).
  func testFormatting() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let source = """
      struct S {
      var   foo:  Int
      var bar:Int
      }
      """
    testClient.openDocument(source, uri: uri)

    let options = FormattingOptions(tabSize: 3, insertSpaces: true)
    let response = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: options
      )
    )

    let edits = try XCTUnwrap(response)
    XCTAssertFalse(edits.isEmpty)
    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })

    let formattedSource = apply(edits: edits, to: source)
    XCTAssertEqual(
      formattedSource.filter { !$0.isWhitespace },
      source.filter { !$0.isWhitespace }
    )

    let secondURI = DocumentURI(for: .swift)
    testClient.openDocument(formattedSource, uri: secondURI)
    let secondResponse = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(secondURI),
        options: options
      )
    )
    XCTAssertEqual(secondResponse, [])
  }

  func testFormattingOptionsConfigurationJSON() throws {
    let snapshot = makeSnapshot("struct S {}\n")

    let spacesArgs = try swiftFormatArguments(
      snapshot: snapshot,
      textDocument: TextDocumentIdentifier(snapshot.uri),
      options: FormattingOptions(tabSize: 3, insertSpaces: true)
    )
    XCTAssertEqual(Array(spacesArgs.prefix(3)), ["format", "-", "--configuration"])
    let spacesConfig = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(spacesArgs[3].utf8)) as? [String: Any]
    )
    XCTAssertEqual(spacesConfig["version"] as? Int, 1)
    XCTAssertEqual(spacesConfig["tabWidth"] as? Int, 3)
    XCTAssertEqual(spacesConfig["indentation"] as? [String: Int], ["spaces": 3])

    let tabsArgs = try swiftFormatArguments(
      snapshot: snapshot,
      textDocument: TextDocumentIdentifier(snapshot.uri),
      options: FormattingOptions(tabSize: 4, insertSpaces: false)
    )
    let tabsConfig = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(tabsArgs[3].utf8)) as? [String: Any]
    )
    XCTAssertEqual(tabsConfig["version"] as? Int, 1)
    XCTAssertEqual(tabsConfig["tabWidth"] as? Int, 4)
    XCTAssertEqual(tabsConfig["indentation"] as? [String: Int], ["tabs": 1])
  }

  func testConfigFileOnDisk() async throws {
    try await withTestScratchDir { scratchDir in
      let configURL = scratchDir.appending(component: ".swift-format")
      let fileURL = scratchDir.appending(component: "test.swift")
      try await "{}".writeWithRetry(to: configURL)
      try await "struct Root {}\n".writeWithRetry(to: fileURL)

      let snapshot = makeSnapshot("struct Root {}\n", uri: DocumentURI(fileURL))
      let args = try swiftFormatArguments(
        snapshot: snapshot,
        textDocument: TextDocumentIdentifier(snapshot.uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
      XCTAssertEqual(args, ["format", "-", "--configuration", try configURL.filePath])
    }
  }

  func testConfigFileInParentDirectory() async throws {
    try await withTestScratchDir { scratchDir in
      let configURL = scratchDir.appending(component: ".swift-format")
      let subDir = scratchDir.appending(component: "sub")
      try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
      let fileURL = subDir.appending(component: "test.swift")
      try await "{}".writeWithRetry(to: configURL)
      try await "struct Root {}\n".writeWithRetry(to: fileURL)

      let snapshot = makeSnapshot("struct Root {}\n", uri: DocumentURI(fileURL))
      let args = try swiftFormatArguments(
        snapshot: snapshot,
        textDocument: TextDocumentIdentifier(snapshot.uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
      XCTAssertEqual(args, ["format", "-", "--configuration", try configURL.filePath])
    }
  }

  func testConfigFileInNestedDirectory() async throws {
    try await withTestScratchDir { scratchDir in
      let parentConfigURL = scratchDir.appending(component: ".swift-format")
      let subDir = scratchDir.appending(component: "sub")
      try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
      let nestedConfigURL = subDir.appending(component: ".swift-format")
      let fileURL = subDir.appending(component: "test.swift")
      try await "{}".writeWithRetry(to: parentConfigURL)
      try await "{}".writeWithRetry(to: nestedConfigURL)
      try await "struct Root {}\n".writeWithRetry(to: fileURL)

      let snapshot = makeSnapshot("struct Root {}\n", uri: DocumentURI(fileURL))
      let args = try swiftFormatArguments(
        snapshot: snapshot,
        textDocument: TextDocumentIdentifier(snapshot.uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
      XCTAssertEqual(args, ["format", "-", "--configuration", try nestedConfigURL.filePath])
    }
  }

  func testInvalidConfigurationFile() async throws {
    let project = try await MultiFileTestProject(files: [
      ".swift-format": "",
      "test.swift": """
      struct Root {
      var bar = 123
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

  func testInsertAndRemove() {
    let source = """
      public extension Example {
        func function() {}
      }

      """
    let target = """
      extension Example {
        public func function() {}
      }

      """

    let edits = formattingEdits(from: makeSnapshot(source), to: target)
    XCTAssertFalse(edits.isEmpty)
    XCTAssertEqual(apply(edits: edits, to: source), target)
  }

  func testMultiLineStringInsertion() {
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
    let target = #"""
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

    let edits = formattingEdits(from: makeSnapshot(source), to: target)
    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })
    XCTAssertEqual(apply(edits: edits, to: source), target)
  }

  func testFormattingEditsWithMultiByteUTF8Characters() {
    let source = "let 🎉 =   1\n"
    let target = "let 🎉 = 1\n"

    let edits = formattingEdits(from: makeSnapshot(source), to: target)
    XCTAssertFalse(edits.isEmpty)
    XCTAssertEqual(apply(edits: edits, to: source), target)
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
