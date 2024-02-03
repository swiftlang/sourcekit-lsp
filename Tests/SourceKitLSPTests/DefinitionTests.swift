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

import enum PackageLoading.Platform

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

  func testReportInitializerOnDefinitionForType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)
    let positions = testClient.openDocument(
      """
      struct 1️⃣Foo {
        2️⃣init() {}
      }
      _ = 3️⃣Foo()
      """,
      uri: uri
    )

    let response = try await testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([
        Location(uri: uri, range: Range(positions["1️⃣"])),
        Location(uri: uri, range: Range(positions["2️⃣"])),
      ])
    )
  }

  func testAmbiguousDefinition() async throws {
    // FIXME: This shouldn't have to be an indexed workspace but solver-based cursor info currently fails if the file
    // does not exist on disk.
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      func 1️⃣foo() -> Int { 1 }
      func 2️⃣foo() -> String { "" }
      func test() {
        _ = 3️⃣foo()
      }
      """,
      allowBuildFailure: true
    )

    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(ws.fileURI), position: ws.positions["3️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([
        Location(uri: ws.fileURI, range: Range(ws.positions["1️⃣"])),
        Location(uri: ws.fileURI, range: Range(ws.positions["2️⃣"])),
      ])
    )
  }

  func testDefinitionOfClassBetweenModulesObjC() async throws {
    try SkipUnless.platformIsDarwin("@import in Objective-C is not enabled on non-Darwin")
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "LibA/include/LibA.h": """
        @interface 1️⃣LibAClass2️⃣
        - (void)doSomething;
        @end
        """,
        "LibB/include/dummy.h": "",
        "LibB/LibB.m": """
        @import LibA;
        @interface Test
        @end

        @implementation Test
        - (void)test:(3️⃣LibAClass *)libAClass {
          [libAClass doSomething];
        }
        @end
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "LibA"),
            .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
    )
    let (uri, positions) = try ws.openDocument("LibB.m")
    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )

    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }

    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertEqual(
      location,
      Location(
        uri: try ws.uri(for: "LibA.h"),
        range: try ws.position(of: "1️⃣", in: "LibA.h")..<ws.position(of: "2️⃣", in: "LibA.h")
      )
    )
  }

  func testDefinitionOfMethodBetweenModulesObjC() async throws {
    try SkipUnless.platformIsDarwin("@import in Objective-C is not enabled on non-Darwin")
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "LibA/include/LibA.h": """
        @interface LibAClass
        - (void)1️⃣doSomething2️⃣;
        @end
        """,
        "LibB/include/dummy.h": "",
        "LibB/LibB.m": """
        @import LibA;
        @interface Test
        @end

        @implementation Test
        - (void)test:(LibAClass *)libAClass {
          [libAClass 3️⃣doSomething];
        }
        @end
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "LibA"),
            .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
    )
    let (uri, positions) = try ws.openDocument("LibB.m")
    let response = try await ws.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )

    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }

    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertEqual(
      location,
      Location(
        uri: try ws.uri(for: "LibA.h"),
        range: try ws.position(of: "1️⃣", in: "LibA.h")..<ws.position(of: "2️⃣", in: "LibA.h")
      )
    )
  }
}
