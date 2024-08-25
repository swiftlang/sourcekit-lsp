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
@_spi(Testing) import SKLogging
import SKTestSupport
import XCTest

import enum PackageLoading.Platform

class DefinitionTests: XCTestCase {
  func testJumpToDefinitionAtEndOfIdentifier() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

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
    let project = try await IndexedSingleSwiftFileTestProject(
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

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["3️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(
      locations,
      [
        Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
        Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
      ]
    )
  }

  func testJumpToDefinitionFiltersByReceiver() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
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

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["3️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(
      locations,
      [
        Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
        Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
      ]
    )
  }

  func testDynamicJumpToDefinitionInClang() async throws {
    let project = try await SwiftPMTestProject(
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
      enableBackgroundIndexing: true
    )
    let (uri, positions) = try project.openDocument("test.cpp")

    let response = try await project.testClient.send(
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
    let project = try await SwiftPMTestProject(
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
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .target(name: "MySwiftLibrary", dependencies: ["MyLibrary"])
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("main.swift")

    let response = try await project.testClient.send(
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
      Location(uri: try project.uri(for: "test.c"), range: Range(try project.position(of: "1️⃣", in: "test.c")))
    )
  }

  func testReportInitializerOnDefinitionForType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
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
    try await SkipUnless.solverBasedCursorInfoWorksForMemoryOnlyFiles()
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      func 1️⃣foo() -> Int { 1 }
      func 2️⃣foo() -> String { "" }
      func test() {
        _ = 3️⃣foo()
      }
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

  func testDefinitionOfClassBetweenModulesObjC() async throws {
    try SkipUnless.platformIsDarwin("@import in Objective-C is not enabled on non-Darwin")
    let project = try await SwiftPMTestProject(
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
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "LibA"),
            .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
    )
    let (uri, positions) = try project.openDocument("LibB.m")
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )

    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }

    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertEqual(location, try project.location(from: "1️⃣", to: "2️⃣", in: "LibA.h"))
  }

  func testDefinitionOfMethodBetweenModulesObjC() async throws {
    try SkipUnless.platformIsDarwin("@import in Objective-C is not enabled on non-Darwin")
    let project = try await SwiftPMTestProject(
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
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "LibA"),
            .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
    )
    let (uri, positions) = try project.openDocument("LibB.m")
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["3️⃣"])
    )

    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }

    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertEqual(location, try project.location(from: "1️⃣", to: "2️⃣", in: "LibA.h"))
  }

  func testDefinitionOfImplicitInitializer() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      class 1️⃣Foo {}

      func test() {
        2️⃣Foo()
      }
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
    XCTAssertEqual(
      locations,
      [Location(uri: uri, range: Range(positions["1️⃣"]))]
    )
  }

  func testFileDependencyUpdatedWithinSameModule() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "",
        "FileB.swift": """
        func test() {
          1️⃣sayHello()
        }
        """,
      ],
      enableBackgroundIndexing: true
    )

    let (bUri, bPositions) = try project.openDocument("FileB.swift")
    let beforeChangingFileA = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["1️⃣"])
    )
    XCTAssertNil(beforeChangingFileA)

    let updatedAMarkedCode = "func 2️⃣sayHello() {}"
    let updatedACode = extractMarkers(updatedAMarkedCode).textWithoutMarkers
    let updatedAPositions = DocumentPositions(markedText: updatedAMarkedCode)

    let aUri = try project.uri(for: "FileA.swift")
    try updatedACode.write(to: try XCTUnwrap(aUri.fileURL), atomically: true, encoding: .utf8)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: aUri, type: .changed)])
    )

    // Wait until SourceKit-LSP has handled the `DidChangeWatchedFilesNotification` (which it only does after a delay
    // because it debounces these notifications), indicated by it telling us that we should refresh diagnostics.
    let diagnosticRefreshRequestReceived = self.expectation(description: "DiagnosticsRefreshRequest received")
    project.testClient.handleSingleRequest { (request: DiagnosticsRefreshRequest) in
      diagnosticRefreshRequestReceived.fulfill()
      return VoidResponse()
    }
    try await fulfillmentOfOrThrow([diagnosticRefreshRequestReceived])

    let afterChangingFileA = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["1️⃣"])
    )
    XCTAssertEqual(
      afterChangingFileA,
      .locations([Location(uri: aUri, range: Range(updatedAPositions["2️⃣"]))])
    )

    let afterChange = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["1️⃣"])
    )
    XCTAssertEqual(
      afterChange,
      .locations([Location(uri: aUri, range: Range(updatedAPositions["2️⃣"]))])
    )
  }

  func testDependentModuleGotBuilt() async throws {
    try SkipUnless.longTestsEnabled()
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣sayHello() {}
        """,
        "LibB/LibB.swift": """
        import LibA

        func test() {
          2️⃣sayHello()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "LibA"),
            .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
    )

    let (bUri, bPositions) = try project.openDocument("LibB.swift")
    let beforeBuilding = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["2️⃣"])
    )
    XCTAssertNil(beforeBuilding)

    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    project.testClient.send(
      DidChangeWatchedFilesNotification(
        changes:
          FileManager.default.findFiles(withExtension: "swiftmodule", in: project.scratchDirectory).map {
            FileEvent(uri: DocumentURI($0), type: .created)
          }
      )
    )

    // Wait until SourceKit-LSP has handled the `DidChangeWatchedFilesNotification` (which it only does after a delay
    // because it debounces these notifications), indicated by it telling us that we should refresh diagnostics.
    let diagnosticRefreshRequestReceived = self.expectation(description: "DiagnosticsRefreshRequest received")
    project.testClient.handleSingleRequest { (request: DiagnosticsRefreshRequest) in
      diagnosticRefreshRequestReceived.fulfill()
      return VoidResponse()
    }
    try await fulfillmentOfOrThrow([diagnosticRefreshRequestReceived])

    let afterBuilding = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["2️⃣"])
    )
    XCTAssertEqual(
      afterBuilding,
      .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "LibA.swift")])
    )
  }

  func testIndexBasedDefinitionAfterFileMove() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "definition.swift": """
        class MyClass {
          func 1️⃣foo() {}
        }
        """,
        "caller.swift": """
        func test(myClass: MyClass) {
          myClass.2️⃣foo()
        }
        """,
      ],
      enableBackgroundIndexing: true
    )

    let definitionUri = try project.uri(for: "definition.swift")
    let (callerUri, callerPositions) = try project.openDocument("caller.swift")

    // Validate that we get correct rename results before moving the definition file.
    let resultBeforeFileMove = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(callerUri), position: callerPositions["2️⃣"])
    )
    XCTAssertEqual(
      resultBeforeFileMove,
      .locations([
        Location(uri: definitionUri, range: Range(try project.position(of: "1️⃣", in: "definition.swift")))
      ])
    )

    let movedDefinitionUri =
      DocumentURI(
        definitionUri.fileURL!
          .deletingLastPathComponent()
          .appendingPathComponent("movedDefinition.swift")
      )

    try FileManager.default.moveItem(at: XCTUnwrap(definitionUri.fileURL), to: XCTUnwrap(movedDefinitionUri.fileURL))

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: definitionUri, type: .deleted), FileEvent(uri: movedDefinitionUri, type: .created),
      ])
    )

    // Ensure that the DidChangeWatchedFilesNotification is handled before we continue.
    try await project.testClient.send(PollIndexRequest())

    let resultAfterFileMove = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(callerUri), position: callerPositions["2️⃣"])
    )
    XCTAssertEqual(
      resultAfterFileMove,
      .locations([
        Location(uri: movedDefinitionUri, range: Range(try project.position(of: "1️⃣", in: "definition.swift")))
      ])
    )
  }

  func testJumpToDefinitionOnProtocolImplementationJumpsToRequirement() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      protocol TestProtocol {
        func 1️⃣doThing()
      }

      struct TestImpl: TestProtocol {
        func 2️⃣do3️⃣Thing() { }
      }
      """
    )

    let definitionFromBaseName = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      definitionFromBaseName,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )

    let definitionFromInsideBaseName = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["3️⃣"])
    )
    XCTAssertEqual(
      definitionFromInsideBaseName,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  func testJumpToDefinitionOnProtocolImplementationShowsAllFulfilledRequirements() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      protocol TestProtocol {
        func 1️⃣doThing()
      }

      protocol OtherProtocol {
        func 2️⃣doThing()
      }

      struct TestImpl: TestProtocol, OtherProtocol {
        func 3️⃣doThing() { }
      }
      """
    )

    let result = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["3️⃣"])
    )
    XCTAssertEqual(
      result,
      .locations([
        Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
        Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
      ])
    )
  }

  func testJumpToSatisfiedProtocolRequirementInExtension() async throws {
    try await SkipUnless.sourcekitdReportsOverridableFunctionDefinitionsAsDynamic()

    let project = try await IndexedSingleSwiftFileTestProject(
      """
      protocol TestProtocol {
        func 1️⃣doThing()
      }

      struct TestImpl: TestProtocol {}
      extension TestImpl {
        func 2️⃣doThing() { }
      }
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
    )
    guard case .locations(let locations) = response else {
      XCTFail("Expected locations response")
      return
    }
    XCTAssertEqual(locations, [Location(uri: project.fileURI, range: Range(project.positions["2️⃣"]))])
  }
}
