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
import ISDBTestSupport
import LanguageServerProtocol
import SKLogging
import SKSupport
import SKTestSupport
import SourceKitLSP
import XCTest

final class SwiftInterfaceTests: XCTestCase {
  func testSystemModuleInterface() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    testClient.openDocument("import Foundation", uri: uri)

    let _resp = try await testClient.send(
      DefinitionRequest(
        textDocument: TextDocumentIdentifier(url),
        position: Position(line: 0, utf16index: 10)
      )
    )
    let resp = try XCTUnwrap(_resp)
    guard case .locations(let locations) = resp else {
      XCTFail("Unexpected response: \(resp)")
      return
    }
    let location = try XCTUnwrap(locations.only)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("/Foundation.swiftinterface"))
    let fileContents = try XCTUnwrap(location.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
    // Sanity-check that the generated Swift Interface contains Swift code
    XCTAssert(
      fileContents.hasPrefix("import "),
      "Expected that the foundation swift interface starts with 'import ' but got '\(fileContents.prefix(100))'"
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
      swiftInterfaceFile: "/Swift.String.swiftinterface",
      linePrefix: "@frozen public struct String"
    )
    // Test stdlib with two submodules
    try await assertSystemSwiftInterface(
      uri: project.fileURI,
      position: project.positions["2️⃣"],
      testClient: project.testClient,
      swiftInterfaceFile: "/Swift.Math.Integers.swiftinterface",
      linePrefix: "@frozen public struct Int"
    )
    // Test concurrency
    try await assertSystemSwiftInterface(
      uri: project.fileURI,
      position: project.positions["3️⃣"],
      testClient: project.testClient,
      swiftInterfaceFile: "/_Concurrency.swiftinterface",
      linePrefix: "@inlinable public func withTaskGroup"
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
    let _resp =
      try await project.testClient.send(
        DefinitionRequest(
          textDocument: TextDocumentIdentifier(mainUri),
          position: mainPositions["1️⃣"]
        )
      )
    let resp = try XCTUnwrap(_resp)
    guard case .locations(let locations) = resp else {
      XCTFail("Unexpected response: \(resp)")
      return
    }
    let location = try XCTUnwrap(locations.only)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("/MyLibrary.swiftinterface"))
    let fileContents = try XCTUnwrap(location.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
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
      swiftInterfaceFile: "/Swift.Collection.Array.swiftinterface",
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
      swiftInterfaceFile: "/Swift.Collection.Array.swiftinterface",
      linePrefix: "@inlinable public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Element]"
    )
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
  let definition = try await testClient.send(
    DefinitionRequest(
      textDocument: TextDocumentIdentifier(uri),
      position: position
    )
  )
  guard case .locations(let jump) = definition else {
    XCTFail("Response is not locations", line: line)
    return
  }
  let location = try XCTUnwrap(jump.only)
  XCTAssertTrue(
    location.uri.pseudoPath.hasSuffix(swiftInterfaceFile),
    "Path was: '\(location.uri.pseudoPath)'",
    line: line
  )
  // load contents of swiftinterface
  let contents = try XCTUnwrap(location.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
  let lineTable = LineTable(contents)
  let destinationLine = lineTable[location.range.lowerBound.line].trimmingCharacters(in: .whitespaces)
  XCTAssert(destinationLine.hasPrefix(linePrefix), "Full line was: '\(destinationLine)'", line: line)
}
