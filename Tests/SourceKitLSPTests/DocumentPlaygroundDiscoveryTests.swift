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
import SourceKitLSP
import XCTest

final class DocumentPlaygroundDiscoveryTests: XCTestCase {
  func testParsePlaygrounds() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLib.swift": """
        import Playgrounds

        public func foo() -> String {
          "bar"
        }

        1️⃣#Playground("foo") {
          print(foo())
        }2️⃣

        3️⃣#Playground {
          print(foo())
        }4️⃣

        public func bar(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        5️⃣#Playground("bar") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }6️⃣
        """
      ],
    )

    let (uri, positions) = try project.openDocument("MyLib.swift")
    let playgrounds = try await project.testClient.send(
      DocumentPlaygroundsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      playgrounds,
      [
        PlaygroundItem(
          id: "MyLibrary/MyLib.swift:7",
          label: "foo",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
        ),
        PlaygroundItem(
          id: "MyLibrary/MyLib.swift:11",
          label: nil,
          location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"]),
        ),
        PlaygroundItem(
          id: "MyLibrary/MyLib.swift:19",
          label: "bar",
          location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"]),
        ),
      ]
    )
  }

  func testNoImportPlaygrounds() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLib.swift": """
        public func foo() -> String {
          "bar"
        }

        #Playground("foo") {
          print(foo())
        }

        #Playground {
          print(foo())
        }

        public func bar(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        #Playground("bar") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }
        """
      ],
    )

    let (uri, _) = try project.openDocument("MyLib.swift")
    let playgrounds = try await project.testClient.send(
      DocumentPlaygroundsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(playgrounds, [])
  }

  func testParseNoPlaygrounds() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLib.swift": """
        import Playgrounds

        public func Playground(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        @Playground
        struct MyPlayground {
          public var playground: String = ""
        }
        """
      ],
    )

    let (uri, _) = try project.openDocument("MyLib.swift")
    let playgrounds = try await project.testClient.send(
      DocumentPlaygroundsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(playgrounds, [])
  }
}
