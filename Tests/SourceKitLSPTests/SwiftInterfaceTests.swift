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

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKTestSupport
import SKUtilities
import SourceKitLSP
import SwiftExtensions
import XCTest

final class SwiftInterfaceTests: SourceKitLSPTestCase {
  func testSystemModuleInterface() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    testClient.openDocument("import Foundation", uri: uri)

    let resp = try await testClient.send(
      DefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 0, utf16index: 10)
      )
    )
    let location = try XCTUnwrap(resp?.locations?.only)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("Foundation.swiftinterface"))
    let fileContents = try XCTUnwrap(String(contentsOf: try XCTUnwrap(location.uri.fileURL), encoding: .utf8))
    // Smoke test that the generated Swift Interface contains Swift code
    XCTAssert(
      fileContents.hasPrefix("import "),
      "Expected that the foundation swift interface starts with 'import ' but got '\(fileContents.prefix(100))'"
    )
  }

  func testSystemModuleInterfaceReferenceDocument() async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(experimental: [
        GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])
      ])
    )
    let uri = DocumentURI(for: .swift)

    testClient.openDocument("import Foundation", uri: uri)

    let response = try await testClient.send(
      DefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: Position(line: 0, utf16index: 10)
      )
    )
    let location = try XCTUnwrap(response?.locations?.only)
    let referenceDocument = try await testClient.send(GetReferenceDocumentRequest(uri: location.uri))
    XCTAssert(
      referenceDocument.content.hasPrefix("import "),
      "Expected that the foundation swift interface starts with 'import ' but got '\(referenceDocument.content.prefix(100))'"
    )
  }

  func testDefinitionInSystemModuleInterface() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public func libFunc() async {
        let a: 1️⃣String = "test"
        let i: 2️⃣Int = 2
        await 3️⃣withTaskGroup(of: Void.self) { group in
          group.addTask {
            print(a)
            print(i)
          }
        }
      }
      """,
      indexSystemModules: true
    )

    // Test stdlib with one submodule
    try await assertSystemSwiftInterface(
      uri: project.fileURI,
      position: project.positions["1️⃣"],
      testClient: project.testClient,
      swiftInterfaceFile: "Swift.String.swiftinterface",
      linePrefix: "@frozen public struct String"
    )
    // Test stdlib with two submodules
    try await assertSystemSwiftInterface(
      uri: project.fileURI,
      position: project.positions["2️⃣"],
      testClient: project.testClient,
      swiftInterfaceFile: "Swift.Math.Integers.swiftinterface",
      linePrefix: "@frozen public struct Int"
    )
    // Test concurrency
    try await assertSystemSwiftInterface(
      uri: project.fileURI,
      position: project.positions["3️⃣"],
      testClient: project.testClient,
      swiftInterfaceFiles: ["Swift.swiftinterface", "_Concurrency.swiftinterface"],
      linePrefix: "@inlinable public func withTaskGroup"
    )
  }

  func testDefinitionInSystemModuleInterfaceWithReferenceDocument() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public func libFunc() async {
        let a: 1️⃣String = "test"
      }
      """,
      capabilities: ClientCapabilities(experimental: [
        GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])
      ]),
      indexSystemModules: true
    )

    let definition = try await project.testClient.send(
      DefinitionRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    let location = try XCTUnwrap(definition?.locations?.only)
    let referenceDocument = try await project.testClient.send(GetReferenceDocumentRequest(uri: location.uri))
    let contents = referenceDocument.content
    let lineTable = LineTable(contents)
    let destinationLine = try XCTUnwrap(lineTable.line(at: location.range.lowerBound.line))
      .trimmingCharacters(in: .whitespaces)
    XCTAssert(
      destinationLine.hasPrefix("@frozen public struct String"),
      "Full line was: '\(destinationLine)'"
    )
  }

  func testSwiftInterfaceAcrossModules() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyLibrary.swift": """
        public struct Lib {
          public func foo() {}
          public init() {}
        }
        """,
        "Exec/main.swift": "import 1️⃣MyLibrary",
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .executableTarget(name: "Exec", dependencies: ["MyLibrary"])
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (mainUri, mainPositions) = try project.openDocument("main.swift")
    let response =
      try await project.testClient.send(
        DefinitionRequest(
          textDocument: TextDocumentIdentifier(mainUri),
          position: mainPositions["1️⃣"]
        )
      )
    let location = try XCTUnwrap(response?.locations?.only)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("MyLibrary.swiftinterface"))
    let fileContents = try XCTUnwrap(String(contentsOf: try XCTUnwrap(location.uri.fileURL), encoding: .utf8))
    XCTAssertTrue(
      fileContents.contains(
        """
        public struct Lib {

            public func foo()

            public init()
        }
        """
      ),
      "Generated interface did not contain expected text.\n\(fileContents)"
    )
  }

  func testSemanticFunctionalityInGeneratedInterface() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyLibrary.swift": """
        public struct Lib {
          public func foo() -> String {}
          public init() {}
        }
        """,
        "Exec/main.swift": "import 1️⃣MyLibrary",
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .executableTarget(name: "Exec", dependencies: ["MyLibrary"])
          ]
        )
        """,
      capabilities: ClientCapabilities(experimental: [
        GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])
      ]),
      enableBackgroundIndexing: true
    )

    let (mainUri, mainPositions) = try project.openDocument("main.swift")
    let response =
      try await project.testClient.send(
        DefinitionRequest(
          textDocument: TextDocumentIdentifier(mainUri),
          position: mainPositions["1️⃣"]
        )
      )
    let referenceDocumentUri = try XCTUnwrap(response?.locations?.only).uri
    let referenceDocument = try await project.testClient.send(GetReferenceDocumentRequest(uri: referenceDocumentUri))
    let stringIndex = try XCTUnwrap(referenceDocument.content.firstRange(of: "-> String"))
    let (stringLine, stringColumn) = LineTable(referenceDocument.content)
      .lineAndUTF16ColumnOf(referenceDocument.content.index(stringIndex.lowerBound, offsetBy: 3))

    project.testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(
          uri: referenceDocumentUri,
          language: .swift,
          version: 0,
          text: referenceDocument.content
        )
      )
    )
    let hover = try await project.testClient.send(
      HoverRequest(
        textDocument: TextDocumentIdentifier(referenceDocumentUri),
        position: Position(line: stringLine, utf16index: stringColumn)
      )
    )
    XCTAssertNotNil(hover)
  }

  func testJumpToSynthesizedExtensionMethodInSystemModuleWithoutIndex() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func test(x: [String]) {
        let rows = x.1️⃣filter { !$0.isEmpty }
      }
      """,
      uri: uri
    )

    try await assertSystemSwiftInterface(
      uri: uri,
      position: positions["1️⃣"],
      testClient: testClient,
      swiftInterfaceFile: "Swift.Collection.Array.swiftinterface",
      linePrefix: "@inlinable public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Element]"
    )
  }

  func testJumpToSynthesizedExtensionMethodInSystemModuleWithIndex() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func test(x: [String]) {
        let rows = x.1️⃣filter { !$0.isEmpty }
      }
      """,
      indexSystemModules: true
    )

    try await assertSystemSwiftInterface(
      uri: project.fileURI,
      position: project.positions["1️⃣"],
      testClient: project.testClient,
      swiftInterfaceFile: "Swift.Collection.Array.swiftinterface",
      linePrefix: "@inlinable public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Element]"
    )
  }

  func testNoDiagnosticsInGeneratedInterface() async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(experimental: [
        GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])
      ])
    )
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func test(x: 1️⃣String) {}
      """,
      uri: uri
    )

    let definition = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let interfaceUri = try XCTUnwrap(definition?.locations?.only?.uri)
    let interfaceContents = try await testClient.send(GetReferenceDocumentRequest(uri: interfaceUri))
    testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(uri: interfaceUri, language: .swift, version: 0, text: interfaceContents.content)
      )
    )
    let diagnostics = try await testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(interfaceUri))
    )
    XCTAssertEqual(diagnostics.fullReport?.items, [])
  }

  func testFoundationImportNavigation() async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(experimental: [
        GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])
      ])
    )
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import 1️⃣Foundation
      """,
      uri: uri,
      language: .swift
    )

    // Test navigation to Foundation module
    let foundationDefinition = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let foundationLocation = try XCTUnwrap(foundationDefinition?.locations?.only)
    XCTAssertEqual(foundationLocation.uri.scheme, "sourcekit-lsp")
    assertContains(foundationLocation.uri.pseudoPath, "Foundation.swiftinterface")
  }

  func testFoundationSubmoduleNavigation() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't have Foundation submodules")

    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(experimental: [
        GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])
      ])
    )
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import 1️⃣Foundation.2️⃣NSAffineTransform
      """,
      uri: uri
    )

    let foundationDefinition = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let foundationLocation = try XCTUnwrap(foundationDefinition?.locations?.only)
    XCTAssertEqual(foundationLocation.uri.scheme, "sourcekit-lsp")
    assertContains(foundationLocation.uri.pseudoPath, "Foundation.swiftinterface")

    // Test navigation to NSAffineTransform
    let transformDefinition = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    let transformLocation = try XCTUnwrap(transformDefinition?.locations?.only)
    // Verify we can identify this as a swiftinterface file
    XCTAssertEqual(transformLocation.uri.scheme, "sourcekit-lsp")
    assertContains(transformLocation.uri.pseudoPath, "Foundation.NSAffineTransform.swiftinterface")
  }
}

private func assertSystemSwiftInterface(
  uri: DocumentURI,
  position: Position,
  testClient: TestSourceKitLSPClient,
  swiftInterfaceFile: String,
  linePrefix: String,
  line: UInt = #line
) async throws {
  try await assertSystemSwiftInterface(
    uri: uri,
    position: position,
    testClient: testClient,
    swiftInterfaceFiles: [swiftInterfaceFile],
    linePrefix: linePrefix,
    line: line
  )
}

#if compiler(>=6.4)
@available(
  *,
  deprecated,
  message: "temporary workaround for '_Concurrency.swiftinterface' should no longer be necessary"
)
#endif
private func assertSystemSwiftInterface(
  uri: DocumentURI,
  position: Position,
  testClient: TestSourceKitLSPClient,
  swiftInterfaceFiles: [String],
  linePrefix: String,
  line: UInt = #line
) async throws {
  let definition = try await testClient.send(
    DefinitionRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: position
    )
  )
  let location = try XCTUnwrap(definition?.locations?.only)
  assertContains(swiftInterfaceFiles, try XCTUnwrap(location.uri.fileURL?.lastPathComponent), line: line)
  // load contents of swiftinterface
  let contents = try XCTUnwrap(String(contentsOf: try XCTUnwrap(location.uri.fileURL), encoding: .utf8))
  let lineTable = LineTable(contents)
  let destinationLine = try XCTUnwrap(lineTable.line(at: location.range.lowerBound.line))
    .trimmingCharacters(in: .whitespaces)
  XCTAssert(destinationLine.hasPrefix(linePrefix), "Full line was: '\(destinationLine)'", line: line)
}
