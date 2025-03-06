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

class WorkspaceSymbolsTests: XCTestCase {
  func testWorkspaceSymbolsAcrossPackages() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "packageA/Sources/PackageALib/PackageALib.swift": """
        public func 1️⃣afuncFromA() {}
        """,
        "packageA/Package.swift": """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "PackageA",
          products: [
            .library(name: "PackageALib", targets: ["PackageALib"])
          ],
          targets: [
            .target(name: "PackageALib"),
          ]
        )
        """,
        "packageB/Sources/PackageBLib/PackageBLib.swift": """
        public func 2️⃣funcFromB() {}
        """,
        "packageB/Package.swift": """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "PackageB",
          dependencies: [
            .package(path: "../packageA"),
          ],
          targets: [
            .target(
              name: "PackageBLib",
              dependencies: [.product(name: "PackageALib", package: "PackageA")]
            ),
          ]
        )
        """,
      ],
      workspaces: {
        return [WorkspaceFolder(uri: DocumentURI($0.appendingPathComponent("packageB")))]
      },
      enableBackgroundIndexing: true
    )

    try await project.testClient.send(PollIndexRequest())
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "funcFrom"))

    // Ideally, the item from the current package (PackageB) should be returned before the item from PackageA
    // https://github.com/swiftlang/sourcekit-lsp/issues/1094
    XCTAssertEqual(
      response,
      [
        .symbolInformation(
          SymbolInformation(
            name: "afuncFromA()",
            kind: .function,
            location: try project.location(from: "1️⃣", to: "1️⃣", in: "PackageALib.swift")
          )
        ),
        .symbolInformation(
          SymbolInformation(
            name: "funcFromB()",
            kind: .function,
            location: try project.location(from: "2️⃣", to: "2️⃣", in: "PackageBLib.swift")
          )
        ),
      ]
    )
  }

  func testContainerNameOfFunctionInExtension() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        struct Bar {}
      }

      extension Foo.Bar {
        func 1️⃣barMethod() {}
      }
      """
    )
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "barMethod"))
    XCTAssertEqual(
      response,
      [
        .symbolInformation(
          SymbolInformation(
            name: "barMethod()",
            kind: .method,
            location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
            containerName: "Foo.Bar"
          )
        )
      ]
    )
  }

  func testHideSymbolsFromExcludedFiles() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "func 1️⃣doThingA() {}",
        "FileB.swift": "func 2️⃣doThingB() {}",
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary")]
        )
        """,
      enableBackgroundIndexing: true
    )
    let symbolsBeforeDeletion = try await project.testClient.send(WorkspaceSymbolsRequest(query: "doThing"))
    XCTAssertEqual(
      symbolsBeforeDeletion,
      [
        .symbolInformation(
          SymbolInformation(
            name: "doThingA()",
            kind: .function,
            location: try project.location(from: "1️⃣", to: "1️⃣", in: "FileA.swift")
          )
        ),
        .symbolInformation(
          SymbolInformation(
            name: "doThingB()",
            kind: .function,
            location: try project.location(from: "2️⃣", to: "2️⃣", in: "FileB.swift")
          )
        ),
      ]
    )

    try """
    // swift-tools-version: 5.7

    import PackageDescription

    let package = Package(
      name: "MyLibrary",
      targets: [.target(name: "MyLibrary", exclude: ["FileA.swift"])]
    )
    """.write(to: XCTUnwrap(project.uri(for: "Package.swift").fileURL), atomically: true, encoding: .utf8)

    // Test that we exclude FileB.swift from the index after it has been removed from the package's target.
    project.testClient.send(
      DidChangeWatchedFilesNotification(
        changes: [FileEvent(uri: try project.uri(for: "Package.swift"), type: .changed)]
      )
    )
    try await repeatUntilExpectedResult {
      let symbolsAfterDeletion = try await project.testClient.send(WorkspaceSymbolsRequest(query: "doThing"))
      if symbolsAfterDeletion?.count == 2 {
        // The exclusion hasn't been processed yet, try again.
        return false
      }
      XCTAssertEqual(
        symbolsAfterDeletion,
        [
          .symbolInformation(
            SymbolInformation(
              name: "doThingB()",
              kind: .function,
              location: try project.location(from: "2️⃣", to: "2️⃣", in: "FileB.swift")
            )
          )
        ]
      )
      return true
    }
  }
}
