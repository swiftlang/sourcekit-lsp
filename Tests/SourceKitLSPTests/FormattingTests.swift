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
import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import class TSCBasic.Process

extension SourceKitLSPTestCase {
  /// Runs the toolchain's `swift-format` executable on `source` via stdin with the given `arguments` (passed after
  /// `format -`) and returns its UTF-8 output.
  func runSwiftFormat(
    on source: String,
    arguments: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> String {
    let swiftFormatPath = try await unwrap(
      ToolchainRegistry.forTesting.default?.swiftFormat?.filePath,
      file: file,
      line: line
    )
    let process = Process(arguments: [swiftFormatPath, "format", "-"] + arguments)
    let writeStream = try process.launch()
    if let fileHandle = writeStream as? FileHandle {
      try fileHandle.write(contentsOf: Data(source.utf8))
    } else {
      writeStream.send(source.utf8)
    }
    try writeStream.close()
    let result = try await process.waitUntilExit()
    XCTAssertEqual(
      result.exitStatus,
      .terminated(code: 0),
      (try? result.utf8stderrOutput()) ?? "",
      file: file,
      line: line
    )
    return try result.utf8Output()
  }
}

final class FormattingTests: SourceKitLSPTestCase {
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
    let expected = try await runSwiftFormat(
      on: source,
      arguments: ["--configuration", #"{"version":1,"tabWidth":3,"indentation":{"spaces":3}}"#]
    )

    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })
    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, source)
    let fooLine = try XCTUnwrap(formattedSource.split(separator: "\n").first { $0.contains("foo") })
    XCTAssertEqual(fooLine.prefix { $0 == " " }.count, 3)

    let tabURI = DocumentURI(for: .swift)
    testClient.openDocument(source, uri: tabURI)

    let tabResponse = try await testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(tabURI),
        options: FormattingOptions(tabSize: 4, insertSpaces: false)
      )
    )

    let tabEdits = try XCTUnwrap(tabResponse)
    let tabFormattedSource = apply(edits: tabEdits, to: source)
    let tabExpected = try await runSwiftFormat(
      on: source,
      arguments: ["--configuration", #"{"version":1,"tabWidth":4,"indentation":{"tabs":1}}"#]
    )

    XCTAssert(tabEdits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })
    XCTAssertEqual(tabFormattedSource, tabExpected)
    XCTAssertNotEqual(tabExpected, source)
    let tabFooLine = try XCTUnwrap(tabFormattedSource.split(separator: "\n").first { $0.contains("foo") })
    XCTAssertTrue(tabFooLine.hasPrefix("\t"))
  }

  func testFormattingNoEdits() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let formattedSource = try await runSwiftFormat(
      on: """
        struct S {
        var foo: Int
        }
        """,
      arguments: ["--configuration", #"{"version":1,"tabWidth":2,"indentation":{"spaces":2}}"#]
    )
    testClient.openDocument(formattedSource, uri: uri)

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
    let source = """
      struct Root {
      var bar = 123
      }

      """
    let project = try await MultiFileTestProject(files: [
      ".swift-format": """
      {
        "version": 1,
        "indentation": {
          "spaces": 1
        },
        "rules": {}
      }
      """,
      "test.swift": source,
    ])
    let (uri, _) = try project.openDocument("test.swift")

    let response = try await project.testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )
    let formattedSource = apply(edits: try XCTUnwrap(response), to: source)
    let configPath = try project.scratchDirectory.appending(component: ".swift-format").filePath
    let expected = try await runSwiftFormat(on: source, arguments: ["--configuration", configPath])
    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, source)
    let barLine = try XCTUnwrap(formattedSource.split(separator: "\n").first { $0.contains("bar") })
    XCTAssertEqual(barLine.prefix { $0 == " " }.count, 1)
  }

  func testConfigFileInParentDirectory() async throws {
    let source = """
      struct Root {
      var bar = 123
      }

      """
    let project = try await MultiFileTestProject(files: [
      ".swift-format": """
      {
        "version": 1,
        "indentation": {
          "spaces": 1
        },
        "rules": {}
      }
      """,
      "sub/test.swift": source,
    ])
    let (uri, _) = try project.openDocument("test.swift")

    let response = try await project.testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )
    let formattedSource = apply(edits: try XCTUnwrap(response), to: source)
    let configPath = try project.scratchDirectory.appending(component: ".swift-format").filePath
    let expected = try await runSwiftFormat(on: source, arguments: ["--configuration", configPath])
    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, source)
    let barLine = try XCTUnwrap(formattedSource.split(separator: "\n").first { $0.contains("bar") })
    XCTAssertEqual(barLine.prefix { $0 == " " }.count, 1)
  }

  func testConfigFileInNestedDirectory() async throws {
    let source = """
      struct Root {
      var bar = 123
      }

      """
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
        },
        "rules": {}
      }
      """,
      "sub/test.swift": source,
    ])
    let (uri, _) = try project.openDocument("test.swift")

    let response = try await project.testClient.send(
      DocumentFormattingRequest(
        textDocument: TextDocumentIdentifier(uri),
        options: FormattingOptions(tabSize: 2, insertSpaces: true)
      )
    )
    let formattedSource = apply(edits: try XCTUnwrap(response), to: source)
    let configPath = try project.scratchDirectory.appending(components: "sub", ".swift-format").filePath
    let expected = try await runSwiftFormat(on: source, arguments: ["--configuration", configPath])
    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, source)
    let barLine = try XCTUnwrap(formattedSource.split(separator: "\n").first { $0.contains("bar") })
    XCTAssertEqual(barLine.prefix { $0 == " " }.count, 3)
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
      func function()   {}
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
    let expected = try await runSwiftFormat(
      on: source,
      arguments: ["--configuration", #"{"version":1,"tabWidth":2,"indentation":{"spaces":2}}"#]
    )

    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, source)
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
    let expected = try await runSwiftFormat(
      on: source,
      arguments: ["--configuration", #"{"version":1,"tabWidth":2,"indentation":{"spaces":2}}"#]
    )

    XCTAssert(edits.allSatisfy { $0.newText.allSatisfy(\.isWhitespace) })
    XCTAssertEqual(formattedSource, expected)
    XCTAssertNotEqual(expected, source)
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
