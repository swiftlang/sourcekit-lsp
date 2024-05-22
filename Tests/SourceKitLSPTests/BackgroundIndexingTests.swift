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
import SKCore
import SKTestSupport
import SemanticIndex
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
    serverOptions.indexTestHooks.preparationTaskDidFinish = { taskDescription in
      XCTAssert(Task.currentPriority == .low, "\(taskDescription) ran with priority \(Task.currentPriority)")
    }
    serverOptions.indexTestHooks.updateIndexStoreTaskDidFinish = { taskDescription in
      XCTAssert(Task.currentPriority == .low, "\(taskDescription) ran with priority \(Task.currentPriority)")
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
        testClient.handleSingleRequest { (request: CreateWorkDoneProgressRequest) in
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
    for _ in 0..<5 {
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

  func testBackgroundIndexingReindexesHeader() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/Header.h": """
        void 1️⃣someFunc();
        """,
        "MyFile.c": """
        #include "Header.h"
        """,
      ],
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

      void 2️⃣test() {
        3️⃣someFunc();
      };
      """
    let newPositions = DocumentPositions(markedText: headerNewMarkedContents)

    try extractMarkers(headerNewMarkedContents).textWithoutMarkers.write(
      to: try XCTUnwrap(uri.fileURL),
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
            name: "test",
            kind: .function,
            tags: nil,
            uri: uri,
            range: Range(newPositions["2️⃣"]),
            selectionRange: Range(newPositions["2️⃣"]),
            data: .dictionary([
              "usr": .string("c:@F@test"),
              "uri": .string(uri.stringValue),
            ])
          ),
          fromRanges: [Range(newPositions["3️⃣"])]
        )
      ]
    )
  }

  func testPrepareTargetAfterEditToDependency() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    var serverOptions = backgroundIndexingOptions
    let expectedPreparationTracker = ExpectedIndexTaskTracker(expectedPreparations: [
      [
        ExpectedPreparation(targetID: "LibA", runDestinationID: "dummy"),
        ExpectedPreparation(targetID: "LibB", runDestinationID: "dummy"),
      ],
      [
        ExpectedPreparation(targetID: "LibB", runDestinationID: "dummy")
      ],
    ])
    serverOptions.indexTestHooks = expectedPreparationTracker.testHooks

    let project = try await SwiftPMTestProject(
      files: [
        "LibA/MyFile.swift": "",
        "LibB/MyOtherFile.swift": """
        import LibA
        func bar() {
          1️⃣foo2️⃣()
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
      cleanUp: { expectedPreparationTracker.keepAlive() }
    )

    let (uri, _) = try project.openDocument("MyOtherFile.swift")
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    guard case .full(let initialDiagnostics) = initialDiagnostics else {
      XCTFail("Expected full diagnostics")
      return
    }
    XCTAssertNotEqual(initialDiagnostics.items, [])

    try "public func foo() {}".write(
      to: try XCTUnwrap(project.uri(for: "MyFile.swift").fileURL),
      atomically: true,
      encoding: .utf8
    )

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: try project.uri(for: "MyFile.swift"), type: .changed)])
    )

    // Send a document request for `uri` to trigger re-preparation of its target. We don't actually care about the
    // response for this request. Instead, we wait until SourceKit-LSP sends us a `DiagnosticsRefreshRequest`,
    // indicating that the target of `uri` has been prepared.
    _ = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )

    let receivedEmptyDiagnostics = self.expectation(description: "Received diagnostic refresh request")

    project.testClient.handleSingleRequest { (_: DiagnosticsRefreshRequest) in
      Task {
        let updatedDiagnostics = try await project.testClient.send(
          DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
        )
        guard case .full(let updatedDiagnostics) = updatedDiagnostics else {
          XCTFail("Expected full diagnostics")
          return
        }
        if updatedDiagnostics.items.isEmpty {
          receivedEmptyDiagnostics.fulfill()
        }
      }
      return VoidResponse()
    }

    try await fulfillmentOfOrThrow([receivedEmptyDiagnostics])
  }

  func testDontStackTargetPreparationForEditorFunctionality() async throws {
    let allDocumentsOpened = self.expectation(description: "All documents opened")
    let libBStartedPreparation = self.expectation(description: "LibB started preparing")
    let libDPreparedForEditing = self.expectation(description: "LibD prepared for editing")

    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    var serverOptions = backgroundIndexingOptions
    let expectedPreparationTracker = ExpectedIndexTaskTracker(expectedPreparations: [
      // Preparation of targets during the initial of the target
      [
        ExpectedPreparation(targetID: "LibA", runDestinationID: "dummy"),
        ExpectedPreparation(targetID: "LibB", runDestinationID: "dummy"),
        ExpectedPreparation(targetID: "LibC", runDestinationID: "dummy"),
        ExpectedPreparation(targetID: "LibD", runDestinationID: "dummy"),
      ],
      // LibB's preparation has already started by the time we browse through the other files, so we finish its preparation
      [
        ExpectedPreparation(
          targetID: "LibB",
          runDestinationID: "dummy",
          didStart: { libBStartedPreparation.fulfill() },
          didFinish: { self.wait(for: [allDocumentsOpened], timeout: defaultTimeout) }
        )
      ],
      // And now we just want to prepare LibD, and not LibC
      [
        ExpectedPreparation(
          targetID: "LibD",
          runDestinationID: "dummy",
          didFinish: { libDPreparedForEditing.fulfill() }
        )
      ],
    ])
    serverOptions.indexTestHooks = expectedPreparationTracker.testHooks

    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": "",
        "LibB/LibB.swift": "",
        "LibC/LibC.swift": "",
        "LibD/LibD.swift": "",
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
           .target(name: "LibC", dependencies: ["LibA"]),
           .target(name: "LibD", dependencies: ["LibA"]),
          ]
        )
        """,
      serverOptions: serverOptions,
      cleanUp: { expectedPreparationTracker.keepAlive() }
    )

    // Clean the preparation status of all libraries
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: try project.uri(for: "LibA.swift"), type: .changed)])
    )

    // Quickly flip through all files
    _ = try project.openDocument("LibB.swift")
    try await self.fulfillmentOfOrThrow([libBStartedPreparation])

    _ = try project.openDocument("LibC.swift")

    // Ensure that LibC gets opened before LibD, so that LibD is the latest document. Two open requests don't have
    // dependencies between each other, so SourceKit-LSP is free to execute them in parallel or re-order them without
    // the barrier.
    _ = try await project.testClient.send(BarrierRequest())
    _ = try project.openDocument("LibD.swift")

    allDocumentsOpened.fulfill()
    try await self.fulfillmentOfOrThrow([libDPreparedForEditing])
  }

  public func testProduceIndexLog() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyFile.swift": ""
      ],
      serverOptions: backgroundIndexingOptions
    )
    let targetPrepareNotification = try await project.testClient.nextNotification(ofType: LogMessageNotification.self)
    XCTAssert(
      targetPrepareNotification.message.hasPrefix("Preparing MyLibrary"),
      "\(targetPrepareNotification.message) does not have the expected prefix"
    )
    let indexFileNotification = try await project.testClient.nextNotification(ofType: LogMessageNotification.self)
    XCTAssert(
      indexFileNotification.message.hasPrefix("Indexing \(try project.uri(for: "MyFile.swift").pseudoPath)"),
      "\(indexFileNotification.message) does not have the expected prefix"
    )
  }

  func testPreparationHappensInParallel() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()

    let fileAIndexingStarted = self.expectation(description: "FileA indexing started")
    let fileBIndexingStarted = self.expectation(description: "FileB indexing started")

    var serverOptions = backgroundIndexingOptions
    let expectedIndexTaskTracker = ExpectedIndexTaskTracker(
      expectedIndexStoreUpdates: [
        [
          ExpectedIndexStoreUpdate(
            sourceFileName: "FileA.swift",
            didStart: {
              fileAIndexingStarted.fulfill()
            },
            didFinish: {
              self.wait(for: [fileBIndexingStarted], timeout: defaultTimeout)
            }
          ),
          ExpectedIndexStoreUpdate(
            sourceFileName: "FileB.swift",
            didStart: {
              fileBIndexingStarted.fulfill()
            },
            didFinish: {
              self.wait(for: [fileAIndexingStarted], timeout: defaultTimeout)
            }
          ),
        ]
      ]
    )
    serverOptions.indexTestHooks = expectedIndexTaskTracker.testHooks

    _ = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "",
        "FileB.swift": "",
      ],
      serverOptions: serverOptions,
      cleanUp: { expectedIndexTaskTracker.keepAlive() }
    )
  }
}
