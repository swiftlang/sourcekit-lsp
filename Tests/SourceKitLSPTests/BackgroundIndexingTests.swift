//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

fileprivate let backgroundIndexingOptions = SourceKitLSPServer.Options(
  indexOptions: IndexOptions(enableBackgroundIndexing: true)
)

final class BackgroundIndexingTests: XCTestCase {
  func testBackgroundIndexingOfSingleFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyFile.swift": """
        func 1️⃣foo() {}
        func 2️⃣bar() {
          3️⃣foo()
        }
        """
      ],
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("MyFile.swift")
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "bar()",
            kind: .function,
            tags: nil,
            uri: uri,
            range: Range(positions["2️⃣"]),
            selectionRange: Range(positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:9MyLibrary3baryyF"),
              "uri": .string(uri.stringValue),
            ])
          ),
          fromRanges: [Range(positions["3️⃣"])]
        )
      ]
    )
  }

  func testBackgroundIndexingOfMultiFileModule() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyFile.swift": """
        func 1️⃣foo() {}
        """,
        "MyOtherFile.swift": """
        func 2️⃣bar() {
          3️⃣foo()
        }
        """,
      ],
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("MyFile.swift")
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "bar()",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyOtherFile.swift"),
            range: Range(try project.position(of: "2️⃣", in: "MyOtherFile.swift")),
            selectionRange: Range(try project.position(of: "2️⃣", in: "MyOtherFile.swift")),
            data: .dictionary([
              "usr": .string("s:9MyLibrary3baryyF"),
              "uri": .string(try project.uri(for: "MyOtherFile.swift").stringValue),
            ])
          ),
          fromRanges: [Range(try project.position(of: "3️⃣", in: "MyOtherFile.swift"))]
        )
      ]
    )
  }

  func testBackgroundIndexingOfMultiModuleProject() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/MyFile.swift": """
        public func 1️⃣foo() {}
        """,
        "LibB/MyOtherFile.swift": """
        import LibA
        func 2️⃣bar() {
          3️⃣foo()
        }
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
        """,
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("MyFile.swift")
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let calls = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "bar()",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyOtherFile.swift"),
            range: Range(try project.position(of: "2️⃣", in: "MyOtherFile.swift")),
            selectionRange: Range(try project.position(of: "2️⃣", in: "MyOtherFile.swift")),
            data: .dictionary([
              "usr": .string("s:4LibB3baryyF"),
              "uri": .string(try project.uri(for: "MyOtherFile.swift").stringValue),
            ])
          ),
          fromRanges: [Range(try project.position(of: "3️⃣", in: "MyOtherFile.swift"))]
        )
      ]
    )
  }

  func testBackgroundIndexingHappensWithLowPriority() async throws {
    var serverOptions = backgroundIndexingOptions
    serverOptions.indexTaskDidFinish = {
      XCTAssert(
        Task.currentPriority == .low,
        "An index task ran with priority \(Task.currentPriority)"
      )
    }
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/MyFile.swift": """
        public func 1️⃣foo() {}
        """,
        "LibB/MyOtherFile.swift": """
        import LibA
        func 2️⃣bar() {
          3️⃣foo()
        }
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
        """,
      serverOptions: serverOptions,
      pollIndex: false
    )

    // Wait for indexing to finish without elevating the priority
    let semaphore = WrappedSemaphore()
    let testClient = project.testClient
    Task(priority: .low) {
      await assertNoThrow {
        try await testClient.send(PollIndexRequest())
      }
      semaphore.signal()
    }
    semaphore.wait()
  }

  func testBackgroundIndexingOfPackageDependency() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    let dependencyContents = """
      public func 1️⃣doSomething() {}
      """

    let dependencyProject = try await SwiftPMDependencyProject(files: [
      "Sources/MyDependency/MyDependency.swift": dependencyContents
    ])
    defer { dependencyProject.keepAlive() }

    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        import MyDependency

        func 2️⃣test() {
          3️⃣doSomething()
        }
        """
      ],
      manifest: """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          dependencies: [.package(url: "\(dependencyProject.packageDirectory)", from: "1.0.0")],
          targets: [
            .target(
              name: "MyLibrary",
              dependencies: [.product(name: "MyDependency", package: "MyDependency")]
            )
          ]
        )
        """,
      serverOptions: backgroundIndexingOptions
    )

    let dependencyUrl = try XCTUnwrap(
      FileManager.default.findFiles(named: "MyDependency.swift", in: project.scratchDirectory).only
    )
    let dependencyUri = DocumentURI(dependencyUrl)
    let testFileUri = try project.uri(for: "Test.swift")
    let positions = project.testClient.openDocument(dependencyContents, uri: dependencyUri)
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(dependencyUri), position: positions["1️⃣"])
    )

    let calls = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )

    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "test()",
            kind: .function,
            tags: nil,
            uri: testFileUri,
            range: try project.range(from: "2️⃣", to: "2️⃣", in: "Test.swift"),
            selectionRange: try project.range(from: "2️⃣", to: "2️⃣", in: "Test.swift"),
            data: .dictionary([
              "usr": .string("s:9MyLibrary4testyyF"),
              "uri": .string(testFileUri.stringValue),
            ])
          ),
          fromRanges: [try project.range(from: "3️⃣", to: "3️⃣", in: "Test.swift")]
        )
      ]
    )
  }

  func testIndexCFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/dummy.h": "",
        "MyFile.c": """
        void 1️⃣someFunc() {}

        void 2️⃣test() {
          3️⃣someFunc();
        }
        """,
      ],
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("MyFile.c")
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let calls = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(
      calls,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "test",
            kind: .function,
            tags: nil,
            uri: uri,
            range: Range(positions["2️⃣"]),
            selectionRange: Range(positions["2️⃣"]),
            data: .dictionary([
              "usr": .string("c:@F@test"),
              "uri": .string(uri.stringValue),
            ])
          ),
          fromRanges: [Range(positions["3️⃣"])]
        )
      ]
    )
  }

  func testBackgroundIndexingStatusWorkDoneProgress() async throws {
    let workDoneProgressCreated = self.expectation(description: "Work done progress created")
    let project = try await SwiftPMTestProject(
      files: [
        "MyFile.swift": """
        func foo() {}
        func bar() {
          foo()
        }
        """
      ],
      capabilities: ClientCapabilities(window: WindowClientCapabilities(workDoneProgress: true)),
      serverOptions: backgroundIndexingOptions,
      preInitialization: { testClient in
        testClient.handleNextRequest { (request: CreateWorkDoneProgressRequest) in
          workDoneProgressCreated.fulfill()
          return VoidResponse()
        }
      }
    )
    try await fulfillmentOfOrThrow([workDoneProgressCreated])
    let workBeginProgress = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self)
    guard case .begin = workBeginProgress.value else {
      XCTFail("Expected begin work done progress")
      return
    }
    var didGetEndWorkDoneProgress = false
    for _ in 0..<3 {
      let workEndProgress = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self)
      switch workEndProgress.value {
      case .begin:
        XCTFail("Unexpected begin work done progress")
      case .report:
        // Allow up to 2 work done progress reports.
        continue
      case .end:
        didGetEndWorkDoneProgress = true
      }
      break
    }
    XCTAssert(didGetEndWorkDoneProgress, "Expected end work done progress")

    withExtendedLifetime(project) {}
  }

  func testBackgroundIndexingReindexesWhenSwiftFileIsModified() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyFile.swift": """
        func 1️⃣foo() {}
        """,
        "MyOtherFile.swift": "",
      ],
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("MyFile.swift")
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let callsBeforeEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(callsBeforeEdit, [])

    let otherFileMarkedContents = """
      func 2️⃣bar() {
        3️⃣foo()
      }
      """

    let otherFileUri = try project.uri(for: "MyOtherFile.swift")
    let otherFileUrl = try XCTUnwrap(otherFileUri.fileURL)
    let otherFilePositions = DocumentPositions(markedText: otherFileMarkedContents)

    try extractMarkers(otherFileMarkedContents).textWithoutMarkers.write(
      to: otherFileUrl,
      atomically: true,
      encoding: .utf8
    )

    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: otherFileUri, type: .changed)]))
    _ = try await project.testClient.send(PollIndexRequest())

    let callsAfterEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(
      callsAfterEdit,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "bar()",
            kind: .function,
            tags: nil,
            uri: otherFileUri,
            range: Range(otherFilePositions["2️⃣"]),
            selectionRange: Range(otherFilePositions["2️⃣"]),
            data: .dictionary([
              "usr": .string("s:9MyLibrary3baryyF"),
              "uri": .string(otherFileUri.stringValue),
            ])
          ),
          fromRanges: [Range(otherFilePositions["3️⃣"])]
        )
      ]
    )
  }

  func testBackgroundIndexingReindexesMainFilesWhenHeaderIsModified() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/Header.h": """
        void 1️⃣someFunc();
        """,
        "MyFile.c": """
        #include "Header.h"

        void 2️⃣test() {
        #ifdef MY_FLAG
          3️⃣someFunc();
        #endif
        }
        """,
        "MyOtherFile.c": """
        #include "Header.h"

        void 4️⃣otherTest() {
        #ifdef MY_FLAG
          5️⃣someFunc();
        #endif
        }
        """,
      ],
      build: true,
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("Header.h", language: .c)
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let callsBeforeEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(callsBeforeEdit, [])

    let headerNewMarkedContents = """
      void someFunc();

      #define MY_FLAG 1
      """

    let headerFileUrl = try XCTUnwrap(uri.fileURL)

    try extractMarkers(headerNewMarkedContents).textWithoutMarkers.write(
      to: headerFileUrl,
      atomically: true,
      encoding: .utf8
    )

    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: uri, type: .changed)]))
    _ = try await project.testClient.send(PollIndexRequest())

    let callsAfterEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(
      callsAfterEdit,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "otherTest",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyOtherFile.c"),
            range: try project.range(from: "4️⃣", to: "4️⃣", in: "MyOtherFile.c"),
            selectionRange: try project.range(from: "4️⃣", to: "4️⃣", in: "MyOtherFile.c"),
            data: .dictionary([
              "usr": .string("c:@F@otherTest"),
              "uri": .string(try project.uri(for: "MyOtherFile.c").stringValue),
            ])
          ),
          fromRanges: [try project.range(from: "5️⃣", to: "5️⃣", in: "MyOtherFile.c")]
        ),
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "test",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyFile.c"),
            range: try project.range(from: "2️⃣", to: "2️⃣", in: "MyFile.c"),
            selectionRange: try project.range(from: "2️⃣", to: "2️⃣", in: "MyFile.c"),
            data: .dictionary([
              "usr": .string("c:@F@test"),
              "uri": .string(try project.uri(for: "MyFile.c").stringValue),
            ])
          ),
          fromRanges: [try project.range(from: "3️⃣", to: "3️⃣", in: "MyFile.c")]
        ),
      ]
    )
  }

  func testBackgroundIndexingReindexesMainFilesWhenTransitiveHeaderIsModified() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/OtherHeader.h": "",
        "MyLibrary/include/Header.h": """
        #include "OtherHeader.h"
        void 1️⃣someFunc();
        """,
        "MyFile.c": """
        #include "Header.h"

        void 2️⃣test() {
        #ifdef MY_FLAG
          3️⃣someFunc();
        #endif
        }
        """,
        "MyOtherFile.c": """
        #include "Header.h"

        void 4️⃣otherTest() {
        #ifdef MY_FLAG
          5️⃣someFunc();
        #endif
        }
        """,
      ],
      build: true,
      serverOptions: backgroundIndexingOptions
    )

    let (uri, positions) = try project.openDocument("Header.h", language: .c)
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let callsBeforeEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(callsBeforeEdit, [])

    let otherHeaderFileUrl = try XCTUnwrap(project.uri(for: "OtherHeader.h").fileURL)

    try "#define MY_FLAG 1".write(
      to: otherHeaderFileUrl,
      atomically: true,
      encoding: .utf8
    )

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: DocumentURI(otherHeaderFileUrl), type: .changed)])
    )
    _ = try await project.testClient.send(PollIndexRequest())

    let callsAfterEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(
      callsAfterEdit,
      [
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "otherTest",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyOtherFile.c"),
            range: try project.range(from: "4️⃣", to: "4️⃣", in: "MyOtherFile.c"),
            selectionRange: try project.range(from: "4️⃣", to: "4️⃣", in: "MyOtherFile.c"),
            data: .dictionary([
              "usr": .string("c:@F@otherTest"),
              "uri": .string(try project.uri(for: "MyOtherFile.c").stringValue),
            ])
          ),
          fromRanges: [try project.range(from: "5️⃣", to: "5️⃣", in: "MyOtherFile.c")]
        ),
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "test",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyFile.c"),
            range: try project.range(from: "2️⃣", to: "2️⃣", in: "MyFile.c"),
            selectionRange: try project.range(from: "2️⃣", to: "2️⃣", in: "MyFile.c"),
            data: .dictionary([
              "usr": .string("c:@F@test"),
              "uri": .string(try project.uri(for: "MyFile.c").stringValue),
            ])
          ),
          fromRanges: [try project.range(from: "3️⃣", to: "3️⃣", in: "MyFile.c")]
        ),
      ]
    )
  }
}
