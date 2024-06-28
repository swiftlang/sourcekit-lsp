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
            location: Location(
              uri: try project.uri(for: "PackageALib.swift"),
              range: Range(try project.position(of: "1️⃣", in: "PackageALib.swift"))
            )
          )
        ),
        .symbolInformation(
          SymbolInformation(
            name: "funcFromB()",
            kind: .function,
            location: Location(
              uri: try project.uri(for: "PackageBLib.swift"),
              range: Range(try project.position(of: "2️⃣", in: "PackageBLib.swift"))
            )
          )
        ),
      ]
    )
  }
}
