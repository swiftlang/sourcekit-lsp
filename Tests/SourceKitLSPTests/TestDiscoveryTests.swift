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
import SKTestSupport
import XCTest

final class TestDiscoveryTests: XCTestCase {
  func testWorkspaceTests() async throws {
    try XCTSkipIf(longTestsDisabled)

    let ws = try await SwiftPMTestWorkspace(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class 1️⃣MyTests: XCTestCase {
          func 2️⃣testMyLibrary() {}
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }
        """
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      build: true
    )

    let tests = try await ws.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        WorkspaceSymbolItem.symbolInformation(
          SymbolInformation(
            name: "MyTests",
            kind: .class,
            location: Location(
              uri: try ws.uri(for: "MyTests.swift"),
              range: Range(try ws.position(of: "1️⃣", in: "MyTests.swift"))
            )
          )
        ),
        WorkspaceSymbolItem.symbolInformation(
          SymbolInformation(
            name: "testMyLibrary()",
            kind: .method,
            location: Location(
              uri: try ws.uri(for: "MyTests.swift"),
              range: Range(try ws.position(of: "2️⃣", in: "MyTests.swift"))
            ),
            containerName: "MyTests"
          )
        ),
      ]
    )
  }

  func testDocumentTests() async throws {
    try XCTSkipIf(longTestsDisabled)

    let ws = try await SwiftPMTestWorkspace(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class 1️⃣MyTests: XCTestCase {
          func 2️⃣testMyLibrary() {}
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }
        """,
        "Tests/MyLibraryTests/MoreTests.swift": """
        import XCTest

        class MoreTests: XCTestCase {
          func testSomeMore() {}
        }
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      build: true
    )

    let (uri, positions) = try ws.openDocument("MyTests.swift")
    let tests = try await ws.testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        WorkspaceSymbolItem.symbolInformation(
          SymbolInformation(
            name: "MyTests",
            kind: .class,
            location: Location(
              uri: uri,
              range: Range(positions["1️⃣"])
            )
          )
        ),
        WorkspaceSymbolItem.symbolInformation(
          SymbolInformation(
            name: "testMyLibrary()",
            kind: .method,
            location: Location(
              uri: try ws.uri(for: "MyTests.swift"),
              range: Range(positions["2️⃣"])
            ),
            containerName: "MyTests"
          )
        ),
      ]
    )
  }
}
