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

class DefinitionTests: XCTestCase {
  func testJumpToDefinitionAtEndOfIdentifier() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      let 1️⃣foo = 1
      _ = foo2️⃣
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(locations, [Location(uri: uri, range: Range(positions["1️⃣"]))])
  }

  func testJumpToDefinitionIncludesOverrides() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      protocol TestProtocol {
        func 1️⃣doThing()
      }

      struct TestImpl: TestProtocol { 
        func 2️⃣doThing() { }
      }

      func anyTestProtocol(value: any TestProtocol) {
        value.3️⃣doThing()
      }
      """
    )

    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(ws.fileURI), position: ws.positions["3️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(
      locations,
      [
        Location(uri: ws.fileURI, range: Range(ws.positions["1️⃣"])),
        Location(uri: ws.fileURI, range: Range(ws.positions["2️⃣"])),
      ]
    )
  }

  func testJumpToDefinitionFiltersByReceiver() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      class A {
        func 1️⃣doThing() {}
      }
      class B: A {}
      class C: B {
        override func 2️⃣doThing() {}
      }
      class D: A {
        override func doThing() {}
      }

      func test(value: B) {
        value.3️⃣doThing()
      }
      """
    )

    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(ws.fileURI), position: ws.positions["3️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(
      locations,
      [
        Location(uri: ws.fileURI, range: Range(ws.positions["1️⃣"])),
        Location(uri: ws.fileURI, range: Range(ws.positions["2️⃣"])),
      ]
    )
  }

  func testDynamicJumpToDefinitionInClang() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "Sources/MyLibrary/include/dummy.h": "",
        "test.cpp": """
        struct Base {
          virtual void 1️⃣doStuff() {}
        };

        struct Sub: Base {
          void 2️⃣doStuff() override {}
        };

        void test(Base base) {
          base.3️⃣doStuff();
        }
        """,
      ],
      build: true
    )
    let (uri, positions) = try ws.openDocument("test.cpp")

    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(
      locations,
      [
        Location(uri: uri, range: Range(positions["1️⃣"])),
        Location(uri: uri, range: Range(positions["2️⃣"])),
      ]
    )
  }

  func testJumpToCDefinitionFromSwift() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "Sources/MyLibrary/include/test.h": """
        void myFunc(void);
        """,
        "Sources/MyLibrary/test.c": """
        #include "test.h"

        void 1️⃣myFunc(void) {}
        """,
        "Sources/MySwiftLibrary/main.swift":
          """
        import MyLibrary

        2️⃣myFunc()
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .target(name: "MySwiftLibrary", dependencies: ["MyLibrary"])
          ]
        )
        """,
      build: true
    )

    let (uri, positions) = try ws.openDocument("main.swift")

    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }

    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertEqual(
      location,
      Location(uri: try ws.uri(for: "test.c"), range: Range(try ws.position(of: "1️⃣", in: "test.c")))
    )
  }
}
