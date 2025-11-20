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

import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKTestSupport
import SemanticIndex
import SourceKitLSP
import SwiftExtensions
import TSCExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import class TSCBasic.Process

final class BackgroundIndexingTests: SourceKitLSPTestCase {
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
      enableBackgroundIndexing: true
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
      enableBackgroundIndexing: true
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
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """,
      enableBackgroundIndexing: true
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
    var testHooks = Hooks()
    testHooks.indexHooks.preparationTaskDidFinish = { taskDescription in
      XCTAssert(Task.currentPriority == .low, "\(taskDescription) ran with priority \(Task.currentPriority)")
    }
    testHooks.indexHooks.updateIndexStoreTaskDidFinish = { taskDescription in
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
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """,
      hooks: testHooks,
      enableBackgroundIndexing: true,
      pollIndex: false
    )

    // Wait for indexing to finish without elevating the priority
    let semaphore = WrappedSemaphore(name: "Indexing finished")
    let testClient = project.testClient
    Task(priority: .low) {
      await assertNoThrow {
        try await testClient.send(SynchronizeRequest(index: true))
      }
      semaphore.signal()
    }
    try semaphore.waitOrThrow()
  }

  func testBackgroundIndexingOfPackageDependency() async throws {
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
      enableBackgroundIndexing: true
    )

    let dependencyUrl = try XCTUnwrap(
      FileManager.default.findFiles(
        named: "MyDependency.swift",
        in: project.scratchDirectory.appending(components: ".build", "index-build", "checkouts")
      ).only
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
        "MyLibrary/include/destination.h": "",
        "MyFile.c": """
        void 1️⃣someFunc() {}

        void 2️⃣test() {
          3️⃣someFunc();
        }
        """,
      ],
      enableBackgroundIndexing: true
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
    let receivedBeginProgressNotification = WrappedSemaphore(
      name: "Received work done progress saying build graph generation"
    )
    let receivedReportProgressNotification = WrappedSemaphore(
      name: "Received work done progress saying indexing"
    )
    var testHooks = Hooks()
    testHooks.indexHooks = IndexHooks(
      buildGraphGenerationDidFinish: {
        receivedBeginProgressNotification.waitOrXCTFail()
      },
      updateIndexStoreTaskDidFinish: { _ in
        receivedReportProgressNotification.waitOrXCTFail()
      }
    )
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
      hooks: testHooks,
      enableBackgroundIndexing: true,
      pollIndex: false,
      preInitialization: { testClient in
        testClient.handleMultipleRequests { (request: CreateWorkDoneProgressRequest) in
          return VoidResponse()
        }
      }
    )

    let beginNotification = try await project.testClient.nextNotification(
      ofType: WorkDoneProgress.self,
      satisfying: { notification in
        guard case .begin(let data) = notification.value else {
          return false
        }
        return data.title == "Indexing"
      }
    )
    receivedBeginProgressNotification.signal()
    guard case .begin(let beginData) = beginNotification.value else {
      XCTFail("Expected begin notification")
      return
    }
    XCTAssertEqual(beginData.message, "Determining files")
    let indexingWorkDoneProgressToken = beginNotification.token

    _ = try await project.testClient.nextNotification(
      ofType: WorkDoneProgress.self,
      satisfying: { notification in
        guard notification.token == indexingWorkDoneProgressToken,
          case .report(let reportData) = notification.value,
          reportData.message == "0 / 1"
        else {
          return false
        }
        return true
      }
    )
    receivedReportProgressNotification.signal()

    _ = try await project.testClient.nextNotification(
      ofType: WorkDoneProgress.self,
      satisfying: { notification in
        guard notification.token == indexingWorkDoneProgressToken, case .end = notification.value else {
          return false
        }
        return true
      }
    )

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
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyFile.swift")
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let callsBeforeEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(callsBeforeEdit, [])

    let (otherFileUri, otherFilePositions) = try await project.changeFileOnDisk(
      "MyOtherFile.swift",
      newMarkedContents: """
        func 2️⃣bar() {
          3️⃣foo()
        }
        """
    )
    try await project.testClient.send(SynchronizeRequest(index: true))

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
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("Header.h", language: .c)
    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    let callsBeforeEdit = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: try XCTUnwrap(prepare?.only))
    )
    XCTAssertEqual(callsBeforeEdit, [])

    let (_, newPositions) = try await project.changeFileOnDisk(
      "Header.h",
      newMarkedContents: """
        void someFunc();

        void 2️⃣test() {
          3️⃣someFunc();
        };
        """
    )
    try await project.testClient.send(SynchronizeRequest(index: true))

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
    var testHooks = Hooks()
    let expectedPreparationTracker = ExpectedIndexTaskTracker(expectedPreparations: [
      [
        try ExpectedPreparation(target: "LibA", destination: .target),
        try ExpectedPreparation(target: "LibB", destination: .target),
      ],
      [
        try ExpectedPreparation(target: "LibB", destination: .target)
      ],
    ])
    testHooks.indexHooks = expectedPreparationTracker.testHooks

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
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """,
      capabilities: ClientCapabilities(
        workspace: WorkspaceClientCapabilities(diagnostics: RefreshRegistrationCapability(refreshSupport: true)),
        window: WindowClientCapabilities(workDoneProgress: true)
      ),
      hooks: testHooks,
      enableBackgroundIndexing: true,
      cleanUp: { expectedPreparationTracker.keepAlive() }
    )

    let (uri, _) = try project.openDocument("MyOtherFile.swift")
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertNotEqual(initialDiagnostics.fullReport?.items, [])

    try await project.changeFileOnDisk("MyFile.swift", newMarkedContents: "public func foo() {}")

    let receivedEmptyDiagnostics = self.expectation(description: "Received diagnostic refresh request")
    receivedEmptyDiagnostics.assertForOverFulfill = false
    project.testClient.handleMultipleRequests { (_: CreateWorkDoneProgressRequest) in
      return VoidResponse()
    }

    let testClient = project.testClient
    project.testClient.handleMultipleRequests { [weak testClient] (_: DiagnosticsRefreshRequest) in
      Task { [weak testClient] in
        let updatedDiagnostics = try await testClient?.send(
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

    // Send a document request for `uri` to trigger re-preparation of its target. We don't actually care about the
    // response for this request. Instead, we wait until SourceKit-LSP sends us a `DiagnosticsRefreshRequest`,
    // indicating that the target of `uri` has been prepared.
    _ = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )

    try await fulfillmentOfOrThrow(receivedEmptyDiagnostics)

    // Check that we received a work done progress for the re-preparation of the target
    _ = try await project.testClient.nextNotification(
      ofType: WorkDoneProgress.self,
      satisfying: { notification in
        switch notification.value {
        case .begin(let value): return value.message == "Preparing current file"
        case .report(let value): return value.message == "Preparing current file"
        case .end: return false
        }
      }
    )
  }

  func testDontStackTargetPreparationForEditorFunctionality() async throws {
    let allDocumentsOpened = WrappedSemaphore(name: "All documents opened")
    let libBStartedPreparation = WrappedSemaphore(name: "LibB started preparing")
    let libDPreparedForEditing = WrappedSemaphore(name: "LibD prepared for editing")

    var testHooks = Hooks()
    let expectedPreparationTracker = ExpectedIndexTaskTracker(expectedPreparations: [
      // Preparation of targets during the initial of the target
      [
        try ExpectedPreparation(target: "LibA", destination: .target),
        try ExpectedPreparation(target: "LibB", destination: .target),
        try ExpectedPreparation(target: "LibC", destination: .target),
        try ExpectedPreparation(target: "LibD", destination: .target),
      ],
      // LibB's preparation has already started by the time we browse through the other files, so we finish its preparation
      [
        try ExpectedPreparation(
          target: "LibB",
          destination: .target,
          didStart: { libBStartedPreparation.signal() },
          didFinish: { allDocumentsOpened.waitOrXCTFail() }
        )
      ],
      // And now we just want to prepare LibD, and not LibC
      [
        try ExpectedPreparation(
          target: "LibD",
          destination: .target,
          didFinish: { libDPreparedForEditing.signal() }
        )
      ],
    ])
    testHooks.indexHooks = expectedPreparationTracker.testHooks

    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": "",
        "LibB/LibB.swift": "",
        "LibC/LibC.swift": "",
        "LibD/LibD.swift": "",
      ],
      manifest: """
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
      hooks: testHooks,
      enableBackgroundIndexing: true,
      cleanUp: { expectedPreparationTracker.keepAlive() }
    )

    // Clean the preparation status of all libraries
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: try project.uri(for: "LibA.swift"), type: .changed)])
    )
    // Ensure that we handle the `DidChangeWatchedFilesNotification`.
    try await project.testClient.send(SynchronizeRequest())

    // Quickly flip through all files. The way the test is designed to work is as follows:
    //  - LibB.swift gets opened and prepared. Preparation is simulated to take a long time until both LibC.swift and
    //    LibD.swift have been opened.
    //  - LibC.swift gets opened. This queues preparation of LibC but doesn't cancel preparation of LibB because we
    //    don't cancel in-progress preparation tasks to guarantee forward progress (see comment at the end of
    //    `SemanticIndexManager.prepare`).
    //  - Now LibD.swift gets opened. This cancels preparation of LibC which actually cancels LibC's preparation for
    //    real because LibC's preparation hasn't started yet (it's only queued).
    // Thus, the only targets that are being prepared are LibB and LibD, which is checked by the
    // `ExpectedIndexTaskTracker`.
    _ = try project.openDocument("LibB.swift")
    try libBStartedPreparation.waitOrThrow()

    _ = try project.openDocument("LibC.swift")

    // Ensure that LibC gets opened before LibD, so that LibD is the latest document. Two open requests don't have
    // dependencies between each other, so SourceKit-LSP is free to execute them in parallel or re-order them without
    // the barrier.
    try await project.testClient.send(SynchronizeRequest())
    _ = try project.openDocument("LibD.swift")

    // Send a barrier request to ensure we have finished opening LibD before allowing the preparation of LibB to finish.
    try await project.testClient.send(SynchronizeRequest())

    allDocumentsOpened.signal()
    try libDPreparedForEditing.waitOrThrow()
  }

  func testProduceIndexLog() async throws {
    let didReceivePreparationIndexLogMessage = WrappedSemaphore(name: "Did receive preparation log message")
    let didReceiveIndexingLogMessage = WrappedSemaphore(name: "Did receive indexing log message")
    let updateIndexStoreTaskDidFinish = WrappedSemaphore(name: "Update index store task did finish")

    // Block the index tasks until we have received a log notification to make sure we stream out results as they come
    // in and not only when the indexing task has finished
    var testHooks = Hooks()
    testHooks.indexHooks.preparationTaskDidFinish = { _ in
      didReceivePreparationIndexLogMessage.waitOrXCTFail()
    }
    testHooks.indexHooks.updateIndexStoreTaskDidFinish = { _ in
      didReceiveIndexingLogMessage.waitOrXCTFail()
      updateIndexStoreTaskDidFinish.signal()
    }

    let project = try await SwiftPMTestProject(
      files: [
        "MyFile.swift": ""
      ],
      hooks: testHooks,
      enableBackgroundIndexing: true,
      pollIndex: false
    )
    _ = try await project.testClient.nextNotification(
      ofType: LogMessageNotification.self,
      satisfying: { notification in
        return notification.message.contains("Preparing MyLibrary")
      }
    )
    didReceivePreparationIndexLogMessage.signal()
    _ = try await project.testClient.nextNotification(
      ofType: LogMessageNotification.self,
      satisfying: { notification in
        notification.message.contains("Indexing \(try project.uri(for: "MyFile.swift").pseudoPath)")
      }
    )
    didReceiveIndexingLogMessage.signal()
    try updateIndexStoreTaskDidFinish.waitOrThrow()
  }

  func testProduceIndexLogWithTaskID() async throws {
    let project = try await SwiftPMTestProject(
      files: ["MyFile.swift": ""],
      options: .testDefault(experimentalFeatures: [.structuredLogs]),
      enableBackgroundIndexing: true,
      pollIndex: false
    )

    var inProgressMessagesByTaskID: [String: String] = [:]
    var finishedMessagesByTaskID: [String: String] = [:]
    while true {
      let notification = try await project.testClient.nextNotification(
        ofType: LogMessageNotification.self,
        satisfying: { $0.logName == "SourceKit-LSP: Indexing" }
      )
      switch notification.structure {
      case .begin(let begin):
        XCTAssertNil(inProgressMessagesByTaskID[begin.taskID])
        inProgressMessagesByTaskID[begin.taskID] = begin.title + "\n" + notification.message + "\n"
      case .report(let report):
        XCTAssertNotNil(inProgressMessagesByTaskID[report.taskID])
        inProgressMessagesByTaskID[report.taskID]?.append(notification.message + "\n")
      case .end(let end):
        finishedMessagesByTaskID[end.taskID] =
          try XCTUnwrap(inProgressMessagesByTaskID[end.taskID]) + notification.message
        inProgressMessagesByTaskID[end.taskID] = nil
      case nil:
        break
      }

      if let indexingTask = finishedMessagesByTaskID.values.first(where: { $0.contains("Indexing ") }),
        let prepareTask = finishedMessagesByTaskID.values.first(where: { $0.contains("Preparing ") }),
        indexingTask.contains("Finished"),
        prepareTask.contains("Finished")
      {
        // We have two finished tasks, one for preparation, one for indexing, which is what we expect.
        break
      }
    }
  }

  func testIndexingHappensInParallel() async throws {
    let fileAIndexingStarted = WrappedSemaphore(name: "FileA indexing started")
    let fileBIndexingStarted = WrappedSemaphore(name: "FileB indexing started")

    var testHooks = Hooks()
    let expectedIndexTaskTracker = ExpectedIndexTaskTracker(
      expectedIndexStoreUpdates: [
        [
          ExpectedIndexStoreUpdate(
            sourceFileName: "FileA.swift",
            didStart: {
              fileAIndexingStarted.signal()
            },
            didFinish: {
              fileBIndexingStarted.waitOrXCTFail()
            }
          ),
          ExpectedIndexStoreUpdate(
            sourceFileName: "FileB.swift",
            didStart: {
              fileBIndexingStarted.signal()
            },
            didFinish: {
              fileAIndexingStarted.waitOrXCTFail()
            }
          ),
        ]
      ]
    )
    testHooks.indexHooks = expectedIndexTaskTracker.testHooks

    _ = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "",
        "FileB.swift": "",
      ],
      hooks: testHooks,
      enableBackgroundIndexing: true,
      cleanUp: { expectedIndexTaskTracker.keepAlive() }
    )
  }

  func testNoIndexingHappensWhenPackageIsReopened() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "SwiftLib/NonEmptySwiftFile.swift": """
        func test() {}
        """,
        "CLib/include/EmptyHeader.h": "",
        "CLib/Assembly.S": "",
        "CLib/EmptyC.c": "",
        "CLib/NonEmptyC.c": """
        void test() {}
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "SwiftLib"),
            .target(name: "CLib"),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    var otherClientOptions = Hooks()
    otherClientOptions.indexHooks = IndexHooks(
      preparationTaskDidStart: { taskDescription in
        XCTFail("Did not expect any target preparation, got \(taskDescription.targetsToPrepare)")
      },
      updateIndexStoreTaskDidStart: { taskDescription in
        XCTFail("Did not expect any indexing tasks, got \(taskDescription.filesToIndex)")
      }
    )
    let otherClient = try await TestSourceKitLSPClient(
      hooks: otherClientOptions,
      enableBackgroundIndexing: true,
      workspaceFolders: [
        WorkspaceFolder(uri: DocumentURI(project.scratchDirectory))
      ]
    )
    try await otherClient.send(SynchronizeRequest(index: true))
  }

  func testOpeningFileThatIsNotPartOfThePackageDoesntGenerateABuildFolderThere() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": "",
        "OtherLib/OtherLib.swift": "",
      ],
      enableBackgroundIndexing: true
    )
    _ = try project.openDocument("OtherLib.swift")
    // Wait for 1 second to increase the likelihood of this test failing in case we would start scheduling some
    // background task that causes a build in the `OtherLib` directory.
    try await Task.sleep(for: .seconds(1))
    let nestedIndexBuildURL = try XCTUnwrap(
      project.uri(for: "OtherLib.swift").fileURL?
        .deletingLastPathComponent()
        .appending(components: ".build", "index-build")
    )
    XCTAssertFalse(
      FileManager.default.fileExists(at: nestedIndexBuildURL),
      "No file should exist at \(nestedIndexBuildURL)"
    )
  }

  func testNoPreparationStatusIfTargetIsUpToDate() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": ""
      ],
      capabilities: ClientCapabilities(window: WindowClientCapabilities(workDoneProgress: true)),
      enableBackgroundIndexing: true
    )

    // Opening the document prepares it for editor functionality. Its target is already prepared, so we shouldn't show
    // a work done progress for it.
    project.testClient.handleSingleRequest { (request: CreateWorkDoneProgressRequest) in
      XCTFail("Received unexpected create work done progress: \(request)")
      return VoidResponse()
    }
    _ = try project.openDocument("Lib.swift")
    try await project.testClient.send(SynchronizeRequest())
  }

  func testImportPreparedModuleWithFunctionBodiesSkipped() async throws {
    // This test case was crashing the indexing compiler invocation for Client if Lib was built for index preparation
    // (using `-enable-library-evolution -experimental-skip-all-function-bodies -experimental-lazy-typecheck`) but the
    // Client was not indexed with `-experimental-allow-module-with-compiler-errors`. rdar://129071600
    let project = try await SwiftPMTestProject(
      files: [
        "Lib/Lib.swift": """
        public class TerminalController {
          public var 1️⃣width: Int { 1 }
        }
        """,
        "Client/Client.swift": """
        import Lib

        func test(terminal: TerminalController) {
          let width = terminal.width
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "Lib"),
            .target(name: "Client", dependencies: ["Lib"]),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )
    let (uri, positions) = try project.openDocument("Lib.swift")

    // Check that we indexed `Client.swift` by checking that we return a rename location within it.
    let result = try await project.testClient.send(
      RenameRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"], newName: "height")
    )
    XCTAssertEqual(Set(try XCTUnwrap(result?.changes?.keys)), [uri, try project.uri(for: "Client.swift")])
  }

  func testDontPreparePackageManifest() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": ""
      ],
      enableBackgroundIndexing: true
    )

    _ = try await project.testClient.nextNotification(
      ofType: LogMessageNotification.self,
      satisfying: { $0.message.contains("Preparing MyLibrary") }
    )

    // Opening the package manifest shouldn't cause any `swift build` calls to prepare them because they are not part of
    // a target that can be prepared.
    let (uri, _) = try project.openDocument("Package.swift")
    _ = try await project.testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    try await project.testClient.assertDoesNotReceiveNotification(
      ofType: LogMessageNotification.self,
      satisfying: { $0.message.contains("Preparing") }
    )
  }

  func testUseBuildFlagsDuringPreparation() async throws {
    var options = try await SourceKitLSPOptions.testDefault()
    options.swiftPMOrDefault.swiftCompilerFlags = ["-D", "MY_FLAG"]
    let project = try await SwiftPMTestProject(
      files: [
        "Lib/Lib.swift": """
        #if MY_FLAG
        public func foo() -> Int { 1 }
        #endif
        """,
        "Client/Client.swift": """
        import Lib

        func test() -> String {
          return foo()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "Lib"),
            .target(name: "Client", dependencies: ["Lib"]),
          ]
        )
        """,
      options: options,
      enableBackgroundIndexing: true
    )

    // Check that we get an error about the return type of `foo` (`Int`) not being convertible to the return type of
    // `test` (`String`), which indicates that `Lib` had `foo` and was thus compiled with `-D MY_FLAG`
    let (uri, _) = try project.openDocument("Client.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssert(
      (diagnostics.fullReport?.items ?? []).contains(where: {
        $0.message == "Cannot convert return expression of type 'Int' to return type 'String'"
      }),
      "Did not get expected diagnostic: \(diagnostics)"
    )
  }

  func testUseSwiftSDKFlagsDuringPreparation() async throws {
    try await SkipUnless.canSwiftPMCompileForIOS()

    var options = try await SourceKitLSPOptions.testDefault()
    options.swiftPMOrDefault.swiftSDK = "arm64-apple-ios"
    let project = try await SwiftPMTestProject(
      files: [
        "Lib/Lib.swift": """
        #if os(iOS)
        public func foo() -> Int { 1 }
        #endif
        """,
        "Client/Client.swift": """
        import Lib

        func test() -> String {
          return foo()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "Lib"),
            .target(name: "Client", dependencies: ["Lib"]),
          ]
        )
        """,
      options: options,
      enableBackgroundIndexing: true
    )

    // Check that we get an error about the return type of `foo` (`Int`) not being convertible to the return type of
    // `test` (`String`), which indicates that `Lib` had `foo` and was thus compiled for iOS
    let (uri, _) = try project.openDocument("Client.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssert(
      (diagnostics.fullReport?.items ?? []).contains(where: {
        $0.message == "Cannot convert return expression of type 'Int' to return type 'String'"
      }),
      "Did not get expected diagnostic: \(diagnostics)"
    )
  }

  func testLibraryUsedByExecutableTargetAndPackagePlugin() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib/MyFile.swift": """
        public func 1️⃣foo() {}
        """,
        "MyExec/MyExec.swift": """
        import Lib
        func bar() {
          2️⃣foo()
        }
        """,
        "Plugins/MyPlugin/MyPlugin.swift": """
        import PackagePlugin
        @main
        struct MyPlugin: CommandPlugin {
          func performCommand(context: PluginContext, arguments: [String]) async throws {}
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "Lib"),
           .executableTarget(name: "MyExec", dependencies: ["Lib"]),
           .plugin(
             name: "MyPlugin",
             capability: .command(
               intent: .sourceCodeFormatting(),
               permissions: []
             ),
             dependencies: ["MyExec"]
           )
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyExec.swift")
    let definition = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertEqual(definition, .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "MyFile.swift")]))
  }

  func testCrossModuleFunctionalityEvenIfLowLevelModuleHasErrors() async throws {
    var options = try await SourceKitLSPOptions.testDefault()
    options.backgroundPreparationMode = .enabled
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func libATest() -> Invalid {
          return ""
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        public func 1️⃣libBTest() -> Int {
          return libATest()
        }
        """,
        "MyExec/MyExec.swift": """
        import LibB

        func test() -> Int {
          return 2️⃣libBTest()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
           .executableTarget(name: "MyExec", dependencies: ["LibB"]),
          ]
        )
        """,
      options: options,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyExec.swift")
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertEqual(response, .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "LibB.swift")]))
  }

  func testCrossModuleFunctionalityWithErrors() async throws {
    var options = try await SourceKitLSPOptions.testDefault()
    options.backgroundPreparationMode = .enabled
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣libATest() -> Invalid {
          return ""
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        public func libBTest() {
          2️⃣libATest()
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
        """,
      options: options,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("LibB.swift")
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertEqual(response, .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "LibA.swift")]))
  }

  func testCrossModuleFunctionalityWithPreparationNoSkipping() async throws {
    var options = try await SourceKitLSPOptions.testDefault()
    options.backgroundPreparationMode = .noLazy
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func test() -> Invalid {
          return ""
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        public func 1️⃣libBTest() -> Int {
          return libATest()
        }
        """,
        "MyExec/MyExec.swift": """
        import LibB

        func test() -> Int {
          return 2️⃣libBTest()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
           .executableTarget(name: "MyExec", dependencies: ["LibB"]),
          ]
        )
        """,
      options: options,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyExec.swift")
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    XCTAssertEqual(response, .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "LibB.swift")]))
  }

  func testUpdatePackageDependency() async throws {
    try SkipUnless.longTestsEnabled()

    let dependencyProject = try await SwiftPMDependencyProject(files: [
      "Sources/MyDependency/Dependency.swift": """
      /// Do something v1.0.0
      public func doSomething() {}
      """
    ])
    let dependencySwiftURL = dependencyProject.packageDirectory
      .appending(components: "Sources", "MyDependency", "Dependency.swift")
    defer { dependencyProject.keepAlive() }

    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        import MyDependency

        func test() {
          1️⃣doSomething()
        }
        """
      ],
      manifest: """
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
      enableBackgroundIndexing: true
    )
    let packageResolvedURL = project.scratchDirectory.appending(component: "Package.resolved")

    let originalPackageResolvedContents = try String(contentsOf: packageResolvedURL, encoding: .utf8)

    // First check our setup to see that we get the expected hover response before changing the dependency project.
    let (uri, positions) = try project.openDocument("Test.swift")
    let hoverBeforeUpdate = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssert(
      hoverBeforeUpdate?.contents.markupContent?.value.contains("Do something v1.0.0") ?? false,
      "Did not contain expected string: \(String(describing: hoverBeforeUpdate))"
    )

    // Just committing a new version of the dependency shouldn't change anything because we didn't update the package
    // dependencies.
    try await """
    /// Do something v1.1.0
    public func doSomething() {}
    """.writeWithRetry(to: dependencySwiftURL)
    try await dependencyProject.tag(changedFiles: [dependencySwiftURL], version: "1.1.0")

    let hoverAfterNewVersionCommit = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssert(
      hoverAfterNewVersionCommit?.contents.markupContent?.value.contains("Do something v1.0.0") ?? false,
      "Did not contain expected string: \(String(describing: hoverBeforeUpdate))"
    )

    // Updating Package.swift causes a package reload but should not cause dependencies to be updated.
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: DocumentURI(project.scratchDirectory.appending(component: "Package.swift")), type: .changed)
      ])
    )
    try await project.testClient.send(SynchronizeRequest(index: true))
    XCTAssertEqual(try String(contentsOf: packageResolvedURL, encoding: .utf8), originalPackageResolvedContents)

    // Simulate a package update which goes as follows:
    //  - The user runs `swift package update`
    //  - This updates `Package.resolved`, which we watch
    //  - We reload the package, which updates `Dependency.swift` in `.build/index-build/checkouts`, which we also watch.
    let projectURL = project.scratchDirectory
    let packageUpdateOutput = try await withTimeout(defaultTimeoutDuration) {
      try await Process.run(
        arguments: [
          unwrap(ToolchainRegistry.forTesting.default?.swift?.filePath),
          "package", "update",
          "--package-path", projectURL.filePath,
        ],
        workingDirectory: nil
      )
    }
    logger.debug(
      """
      'swift package update' output:
      \(packageUpdateOutput)
      """
    )

    XCTAssertNotEqual(try String(contentsOf: packageResolvedURL, encoding: .utf8), originalPackageResolvedContents)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: DocumentURI(project.scratchDirectory.appending(component: "Package.resolved")), type: .changed)
      ])
    )
    try await project.testClient.send(SynchronizeRequest(index: true))
    let dependencyCheckoutFile = try XCTUnwrap(
      FileManager.default.findFiles(
        named: "Dependency.swift",
        in: project.scratchDirectory
          .appending(components: ".build", "index-build", "checkouts")
      ).only
    )
    // Check that modifying Package.resolved actually modified the dependency checkout inside the package
    assertContains(try String(contentsOf: dependencyCheckoutFile, encoding: .utf8), "Do something v1.1.0")
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: DocumentURI(dependencyCheckoutFile), type: .changed)])
    )

    try await repeatUntilExpectedResult {
      let hoverAfterPackageUpdate = try await project.testClient.send(
        HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return hoverAfterPackageUpdate?.contents.markupContent?.value.contains("Do something v1.1.0") ?? false
    }
  }

  func testAddingRandomSwiftFileDoesNotTriggerPackageReload() async throws {
    let packageInitialized = AtomicBool(initialValue: false)

    var testHooks = Hooks()
    testHooks.buildServerHooks.swiftPMTestHooks.reloadPackageDidStart = {
      if packageInitialized.value {
        XCTFail("Build graph should not get reloaded when random file gets added")
      }
    }
    let project = try await SwiftPMTestProject(
      files: ["Test.swift": ""],
      hooks: testHooks,
      enableBackgroundIndexing: true
    )
    packageInitialized.value = true
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: DocumentURI(project.scratchDirectory.appending(component: "random.swift")), type: .created)
      ])
    )
    _ = try await project.testClient.send(SynchronizeRequest(index: true))
  }

  func testManualReindex() async throws {
    // This test relies on the issue described in https://github.com/apple/sourcekit-lsp/issues/1264 that we don't
    // re-index dependent files if a function of a low-level module gains a new default parameter, which changes the
    // function's USR but is API compatible with all dependencies.
    // Check that after running the re-index request, the index gets updated.

    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣getInt() -> Int {
          return 1
        }
        """,
        "LibB/LibB.swift": """
        import LibA

        public func 2️⃣test() -> Int {
          return 3️⃣getInt()
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
        """,
      enableBackgroundIndexing: true
    )

    let expectedCallHierarchyItem = CallHierarchyIncomingCall(
      from: CallHierarchyItem(
        name: "test()",
        kind: .function,
        tags: nil,
        uri: try project.uri(for: "LibB.swift"),
        range: try project.range(from: "2️⃣", to: "2️⃣", in: "LibB.swift"),
        selectionRange: try project.range(from: "2️⃣", to: "2️⃣", in: "LibB.swift"),
        data: .dictionary([
          "usr": .string("s:4LibB4testSiyF"),
          "uri": .string(try project.uri(for: "LibB.swift").stringValue),
        ])
      ),
      fromRanges: [try project.range(from: "3️⃣", to: "3️⃣", in: "LibB.swift")]
    )

    /// Start by making a call hierarchy request to check that we get the expected results without any edits.
    let (uri, positions) = try project.openDocument("LibA.swift")
    let prepareBeforeUpdate = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let callHierarchyBeforeUpdate = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: XCTUnwrap(prepareBeforeUpdate?.only))
    )
    XCTAssertEqual(callHierarchyBeforeUpdate, [expectedCallHierarchyItem])

    // Now add a new default parameter to `getInt`.
    project.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(uri)))
    let newLibAContents = """
      public func getInt(value: Int = 1) -> Int {
        return value
      }
      """
    try await newLibAContents.writeWithRetry(to: XCTUnwrap(uri.fileURL))
    project.testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(uri: uri, language: .swift, version: 0, text: newLibAContents)
      )
    )
    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: uri, type: .changed)]))
    _ = try await project.testClient.send(SynchronizeRequest(index: true))

    // The USR of `getInt` has changed but LibB.swift has not been re-indexed due to
    // https://github.com/apple/sourcekit-lsp/issues/1264. We expect to get an empty call hierarchy.
    let prepareAfterUpdate = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let callHierarchyAfterUpdate = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: XCTUnwrap(prepareAfterUpdate?.only))
    )
    XCTAssertEqual(callHierarchyAfterUpdate, [])

    // After re-indexing, we expect to get a full call hierarchy again.
    _ = try await project.testClient.send(TriggerReindexRequest())
    _ = try await project.testClient.send(SynchronizeRequest(index: true))

    let prepareAfterReindex = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let callHierarchyAfterReindex = try await project.testClient.send(
      CallHierarchyIncomingCallsRequest(item: XCTUnwrap(prepareAfterReindex?.only))
    )
    XCTAssertEqual(callHierarchyAfterReindex, [expectedCallHierarchyItem])
  }

  func testCancelIndexing() async throws {
    try SkipUnless.longTestsEnabled()

    var options = try await SourceKitLSPOptions.testDefault()
    options.backgroundPreparationMode = .enabled
    options.indexOrDefault.updateIndexStoreTimeout = 1 /* second */

    let dateStarted = Date()
    _ = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        struct A: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }
        struct B: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }
        struct C: ExpressibleByIntegerLiteral { init(integerLiteral value: Int) {} }

        func + (lhs: A, rhs: B) -> A { fatalError() }
        func + (lhs: B, rhs: C) -> A { fatalError() }
        func + (lhs: C, rhs: A) -> A { fatalError() }

        func + (lhs: B, rhs: A) -> B { fatalError() }
        func + (lhs: C, rhs: B) -> B { fatalError() }
        func + (lhs: A, rhs: C) -> B { fatalError() }

        func + (lhs: C, rhs: B) -> C { fatalError() }
        func + (lhs: B, rhs: C) -> C { fatalError() }
        func + (lhs: A, rhs: A) -> C { fatalError() }

        func slow() {
          let x: C = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10
        }
        """
      ],
      options: options,
      enableBackgroundIndexing: true
    )
    // Creating the `SwiftPMTestProject` implicitly waits for background indexing to finish.
    // Preparation of `Test.swift` should finish instantly because it doesn't type check the function body.
    // Type-checking of `slow()` should be slow because the expression has exponential complexity in the type checker.
    // We should hit the timeout of 1s. Adding another 2s to escalate a SIGINT (to which swift-frontend doesn't respond)
    // to a SIGKILL mean that the initial indexing should be done in ~3s. 90s should be enough to always finish within
    // this time while also testing that we don't wait for type checking of Test.swift to finish, even on slow CI
    // systems where package loading might take a while and just calling `swift build` to prepare `Test.swift` also has
    // a delay.
    XCTAssertLessThan(Date().timeIntervalSince(dateStarted), 90)
  }

  func testRedirectSymlink() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "/original.swift": """
        func original() {
          foo()
        }
        """,
        "/updated.swift": """
        func updated() {
          foo()
        }
        """,
        "test.swift": """
        func 1️⃣foo() {}
        """,
      ],
      workspaces: { scratchDirectory in
        let symlink =
          scratchDirectory
          .appending(components: "Sources", "MyLibrary", "symlink.swift")
        try FileManager.default.createSymbolicLink(
          at: symlink,
          withDestinationURL: scratchDirectory.appending(component: "original.swift")
        )
        return [WorkspaceFolder(uri: DocumentURI(scratchDirectory))]
      },
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("test.swift")

    let prepare = try await project.testClient.send(
      CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let initialItem = try XCTUnwrap(prepare?.only)
    let callsBeforeRedirect = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(callsBeforeRedirect?.only?.from.name, "original()")

    let symlink =
      project.scratchDirectory
      .appending(components: "Sources", "MyLibrary", "symlink.swift")
    try FileManager.default.removeItem(at: symlink)
    try FileManager.default.createSymbolicLink(
      at: symlink,
      withDestinationURL: project.scratchDirectory.appending(component: "updated.swift")
    )

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: DocumentURI(symlink), type: .changed)])
    )
    try await project.testClient.send(SynchronizeRequest(index: true))

    let callsAfterRedirect = try await project.testClient.send(CallHierarchyIncomingCallsRequest(item: initialItem))
    XCTAssertEqual(callsAfterRedirect?.only?.from.name, "updated()")
  }

  func testInvalidatePreparationStatusOfTransitiveDependencies() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public struct LibA {

        }
        """,
        "LibB/LibB.swift": "",
        "LibC/LibC.swift": """
        import LibA

        func test() {
          LibA().1️⃣test()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
           .target(name: "LibC", dependencies: ["LibB"]),
          ]
        )
        """,
      options: SourceKitLSPOptions(backgroundPreparationMode: .enabled),
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("LibC.swift")

    let definitionBeforeEdit = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertNil(definitionBeforeEdit)

    let (libAUri, newAMarkers) = try await project.changeFileOnDisk(
      "LibA.swift",
      newMarkedContents: """
        public struct LibA {
          public func 2️⃣test() {}
        }
        """
    )

    // Triggering a definition request causes `LibC` to be re-prepared. Repeat the request until LibC has been prepared
    // and we get the expected result.
    try await repeatUntilExpectedResult {
      let definitionAfterEdit = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return definitionAfterEdit?.locations == [Location(uri: libAUri, range: Range(newAMarkers["2️⃣"]))]
    }
  }

  func testCodeCompletionShowsUpdatedResultsAfterDependencyUpdated() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public struct LibA {

        }
        """,
        "LibB/LibB.swift": """
        import LibA

        func test() {
          LibA().1️⃣
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
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("LibB.swift")

    let completionBeforeEdit = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(completionBeforeEdit.items.map(\.label), ["self"])

    try await project.changeFileOnDisk(
      "LibA.swift",
      newMarkedContents: """
        public struct LibA {
          public func test() {}
        }
        """
    )

    try await repeatUntilExpectedResult {
      let completionAfterEdit = try await project.testClient.send(
        CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return completionAfterEdit.items.map(\.label) == ["self", "test()"]
    }
  }

  func testSymlinkedTargetReferringToSameSourceFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public let myVar: String
        """,
        "Client/Client.swift": """
        import LibASymlink

        func test() {
          print(1️⃣myVar)
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibASymlink"),
           .target(name: "Client", dependencies: ["LibASymlink"]),
          ]
        )
        """,
      workspaces: { scratchDirectory in
        let sources = scratchDirectory.appending(component: "Sources")
        try FileManager.default.createSymbolicLink(
          at: sources.appending(component: "LibASymlink"),
          withDestinationURL: sources.appending(component: "LibA")
        )
        return [WorkspaceFolder(uri: DocumentURI(scratchDirectory))]
      },
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("Client.swift")
    let preEditHover = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    let preEditHoverContent = try XCTUnwrap(preEditHover?.contents.markupContent?.value)
    XCTAssert(
      preEditHoverContent.contains("String"),
      "Pre edit hover content '\(preEditHoverContent)' does not contain 'String'"
    )

    try await project.changeFileOnDisk("LibA.swift", newMarkedContents: "public let myVar: Int")

    try await repeatUntilExpectedResult {
      let postEditHover = try await project.testClient.send(
        HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return try XCTUnwrap(postEditHover?.contents.markupContent?.value).contains("Int")
    }
  }

  func testPauseBackgroundIndexing() async throws {
    try SkipUnless.longTestsEnabled()
    let backgroundIndexingPaused = WrappedSemaphore(name: "Background indexing was paused")
    let hooks = Hooks(
      buildServerHooks: BuildServerHooks(
        swiftPMTestHooks: SwiftPMTestHooks(
          reloadPackageDidFinish: {
            backgroundIndexingPaused.waitOrXCTFail()
          }
        )
      )
    )
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        func foo() {}
        """
      ],
      options: .testDefault(experimentalFeatures: [.setOptionsRequest]),
      hooks: hooks,
      enableBackgroundIndexing: true,
      // pollIndex increases the background indexing priority from `low` to `medium`, which thus won't be affected by
      // `workspace/_setBackgroundIndexingPaused` anymore
      pollIndex: false
    )
    try await project.testClient.send(SetOptionsRequest(backgroundIndexingPaused: true))
    backgroundIndexingPaused.signal()

    // Give SwiftPM sufficient time to run background indexing if it was not paused.
    try await Task.sleep(for: .seconds(5))

    let workspaceSymbolsWithBackgroundIndexPaused = try await project.testClient.send(
      WorkspaceSymbolsRequest(query: "foo")
    )
    XCTAssertEqual(workspaceSymbolsWithBackgroundIndexPaused, [])

    try await project.testClient.send(SetOptionsRequest(backgroundIndexingPaused: false))

    try await repeatUntilExpectedResult {
      try await project.testClient.send(WorkspaceSymbolsRequest(query: "foo")) != []
    }
  }

  func testBackgroundIndexingRunsOnSynchronizeRequestEvenIfPaused() async throws {
    let backgroundIndexingPaused = WrappedSemaphore(name: "Background indexing was paused")
    let hooks = Hooks(
      buildServerHooks: BuildServerHooks(
        swiftPMTestHooks: SwiftPMTestHooks(
          reloadPackageDidFinish: {
            backgroundIndexingPaused.waitOrXCTFail()
          }
        )
      )
    )
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        func foo() {}
        """
      ],
      options: .testDefault(experimentalFeatures: [.setOptionsRequest]),
      hooks: hooks,
      enableBackgroundIndexing: true,
      // pollIndex increases the background indexing priority from `low` to `medium`, which thus won't be affected by
      // `workspace/_setBackgroundIndexingPaused` anymore
      pollIndex: false
    )
    try await project.testClient.send(SetOptionsRequest(backgroundIndexingPaused: true))
    backgroundIndexingPaused.signal()

    // Running a `SynchronizeRequest` elevates the background indexing tasks to `medium` priority. We thus no longer
    // consider the indexing to happen in the background and hence it is not affected by the paused background indexing
    // state.
    try await project.testClient.send(SynchronizeRequest(index: true))

    let workspaceSymbolsAfterPollIndex = try await project.testClient.send(WorkspaceSymbolsRequest(query: "foo"))
    XCTAssertNotEqual(workspaceSymbolsAfterPollIndex, [])
  }

  func testPausingBackgroundIndexingDoesNotStopPreparation() async throws {
    let backgroundIndexingPaused = WrappedSemaphore(name: "Background indexing was paused")
    let hooks = Hooks(
      buildServerHooks: BuildServerHooks(
        swiftPMTestHooks: SwiftPMTestHooks(
          reloadPackageDidFinish: {
            backgroundIndexingPaused.waitOrXCTFail()
          }
        )
      )
    )
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public struct LibA {

        }
        """,
        "LibB/LibB.swift": """
        import LibA

        func test() {
          1️⃣LibA()
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
        """,
      options: .testDefault(experimentalFeatures: [.setOptionsRequest]),
      hooks: hooks,
      enableBackgroundIndexing: true,
      // pollIndex increases the background indexing priority from `low` to `medium`, which thus won't be affected by
      // `workspace/_setBackgroundIndexingPaused` anymore
      pollIndex: false
    )
    try await project.testClient.send(SetOptionsRequest(backgroundIndexingPaused: true))
    backgroundIndexingPaused.signal()

    let (uri, positions) = try project.openDocument("LibB.swift")

    // Even with background indexing disabled, we should prepare LibB and eventually get hover results for it.
    // We shouldn't use `SynchronizeRequest` here because that elevates the background indexing priority and thereby
    // unpauses background indexing.
    try await repeatUntilExpectedResult {
      return try await project.testClient.send(
        HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      ) != nil
    }
  }

  func testIsIndexingRequest() async throws {
    let checkedIsIndexStatus = MultiEntrySemaphore(name: "Checked is index status")
    let hooks = Hooks(
      indexHooks: IndexHooks(updateIndexStoreTaskDidStart: { task in
        await checkedIsIndexStatus.waitOrXCTFail()
      })
    )
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": ""
      ],
      options: .testDefault(experimentalFeatures: [.isIndexingRequest]),
      hooks: hooks,
      enableBackgroundIndexing: true,
      pollIndex: false
    )
    let isIndexingResponseWhileIndexing = try await project.testClient.send(IsIndexingRequest())
    XCTAssert(isIndexingResponseWhileIndexing.indexing)
    checkedIsIndexStatus.signal()

    try await repeatUntilExpectedResult {
      try await project.testClient.send(IsIndexingRequest()).indexing == false
    }
  }

  func testIndexFileIfBuildTargetsChange() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL
      private let connectionToSourceKitLSP: any Connection
      private var buildSettingsByFile: [DocumentURI: TextDocumentSourceKitOptionsResponse] = [:]

      package func setBuildSettings(for uri: DocumentURI, to buildSettings: TextDocumentSourceKitOptionsResponse?) {
        buildSettingsByFile[uri] = buildSettings
        connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
      }

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
        self.connectionToSourceKitLSP = connectionToSourceKitLSP
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: false
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
        return dummyTargetSourcesResponse(files: buildSettingsByFile.keys)
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) -> TextDocumentSourceKitOptionsResponse? {
        return buildSettingsByFile[request.textDocument.uri]
      }
    }

    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.swift": """
        func 1️⃣myTestFunc() {}
        """
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true,
      pollIndex: false
    )
    let fileUrl = try XCTUnwrap(project.uri(for: "Test.swift").fileURL)

    var compilerArguments = [fileUrl.path]
    if let defaultSDKPath {
      compilerArguments += ["-sdk", defaultSDKPath]
    }

    // We don't initially index Test.swift because we don't have build settings for it.

    try await project.buildServer().setBuildSettings(
      for: DocumentURI(fileUrl),
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: compilerArguments)
    )

    // But once we get build settings for it, we should index the file.

    try await repeatUntilExpectedResult {
      let workspaceSymbols = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTestFunc"))
      guard let workspaceSymbols, !workspaceSymbols.isEmpty else {
        // No results yet, indexing of the file might not have finished.
        return false
      }
      XCTAssertEqual(
        workspaceSymbols,
        [
          .symbolInformation(
            SymbolInformation(
              name: "myTestFunc()",
              kind: .function,
              location: try project.location(from: "1️⃣", to: "1️⃣", in: "Test.swift")
            )
          )
        ]
      )
      return true
    }
  }

  func testRePrepareTargetsWhenBuildServerChanges() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        #if ENABLE_FOO
        public func foo() {}
        #endif
        """,
        "LibB/LibB.swift": """
        import LibA

        func test() {
          1️⃣foo()
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
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("LibB.swift")
    let hoverWithMissingDependencyDeclaration = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertNil(hoverWithMissingDependencyDeclaration)

    try await project.changeFileOnDisk(
      "Package.swift",
      newMarkedContents: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA", swiftSettings: [.define("ENABLE_FOO")]),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """
    )

    try await repeatUntilExpectedResult {
      let hoverAfterAddingDependencyDeclaration = try await project.testClient.send(
        HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return hoverAfterAddingDependencyDeclaration != nil
    }
  }

  func testUseResponseFileIfTooManyArguments() async throws {
    // The build server returns too many arguments to fit them into a command line invocation, so we need to use a
    // response file to invoke the indexer.

    final class BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL
      private var testFileURL: URL { projectRoot.appending(component: "Test File.swift") }

      init(projectRoot: URL, connectionToSourceKitLSP: any LanguageServerProtocol.Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return initializationResponse(
          initializeData: SourceKitInitializeBuildResponseData(
            indexDatabasePath: try projectRoot.appending(component: "index-db").filePath,
            indexStorePath: try projectRoot.appending(component: "index-store").filePath,
            prepareProvider: true,
            sourceKitOptionsProvider: true
          )
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return BuildTargetSourcesResponse(items: [
          SourcesItem(
            target: .dummy,
            sources: [
              SourceItem(uri: URI(testFileURL), kind: .file, generated: false)
            ]
          )
        ])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        var arguments =
          [try testFileURL.filePath] + (0..<50_000).map { "-DTHIS_IS_AN_OPTION_THAT_CONTAINS_MANY_BYTES_\($0)" }
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        return TextDocumentSourceKitOptionsResponse(
          compilerArguments: arguments
        )
      }

    }

    let project = try await CustomBuildServerTestProject(
      files: [
        // File name contains a space to ensure we escape it in the response file.
        "Test File.swift": """
        func 1️⃣myTestFunc() {}
        """
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )

    let symbols = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTestFunc"))
    XCTAssertEqual(
      symbols,
      [
        .symbolInformation(
          SymbolInformation(
            name: "myTestFunc()",
            kind: .function,
            location: try project.location(from: "1️⃣", to: "1️⃣", in: "Test File.swift")
          )
        )
      ]
    )
  }

  func testIndexingProgressIfNonIndexableFileIsInPackage() async throws {
    let receivedReportProgressNotification = AtomicBool(initialValue: false)

    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/Test.h": "",
        "MyLibrary/Test.c": "",
        "MyLibrary/Assembly.S": "",
      ],
      capabilities: ClientCapabilities(window: WindowClientCapabilities(workDoneProgress: true)),
      hooks: Hooks(
        indexHooks: IndexHooks(updateIndexStoreTaskDidFinish: { _ in
          while !receivedReportProgressNotification.value {
            try? await Task.sleep(for: .milliseconds(10))
          }
        })
      ),
      enableBackgroundIndexing: true,
      pollIndex: false,
      preInitialization: { testClient in
        testClient.handleMultipleRequests { (request: CreateWorkDoneProgressRequest) in
          return VoidResponse()
        }
      }
    )

    let beginNotification = try await project.testClient.nextNotification(
      ofType: WorkDoneProgress.self,
      satisfying: { notification in
        guard case .begin(let data) = notification.value else {
          return false
        }
        return data.title == "Indexing"
      }
    )
    receivedReportProgressNotification.value = true

    // Check that we receive an `end` notification
    _ = try await project.testClient.nextNotification(
      ofType: WorkDoneProgress.self,
      satisfying: { notification in
        if notification.token == beginNotification.token, case .end = notification.value {
          return true
        }
        return false
      }
    )
  }

  func testBuildServerUsesStandardizedFileUrlsInsteadOfRealpath() async throws {
    try SkipUnless.platformIsDarwin("The realpath vs standardized path difference only exists on macOS")

    final class BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL
      private var testFileURL: URL { projectRoot.appending(component: "test.c").standardized }

      required init(projectRoot: URL, connectionToSourceKitLSP: any LanguageServerProtocol.Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: false
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return BuildTargetSourcesResponse(items: [
          SourcesItem(target: .dummy, sources: [SourceItem(uri: URI(testFileURL), kind: .file, generated: false)])
        ])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        return TextDocumentSourceKitOptionsResponse(compilerArguments: [request.textDocument.uri.pseudoPath])
      }
    }

    let scratchDirectory = URL(fileURLWithPath: "/tmp")
      .appending(components: "sourcekitlsp-test", testScratchName())
    let indexedFiles = ThreadSafeBox<[DocumentURI]>(initialValue: [])
    let project = try await CustomBuildServerTestProject(
      files: [
        "test.c": "void x() {}"
      ],
      buildServer: BuildServer.self,
      hooks: Hooks(
        indexHooks: IndexHooks(
          updateIndexStoreTaskDidStart: { task in
            indexedFiles.withLock { indexedFiles in
              indexedFiles += task.filesToIndex.map(\.file.sourceFile)
            }
          }
        )
      ),
      enableBackgroundIndexing: true,
      testScratchDir: scratchDirectory
    )

    // Ensure that changing `/private/tmp/.../test.c` only causes `/tmp/.../test.c` to be indexed, not
    // `/private/tmp/.../test.c`.
    indexedFiles.value = []
    let testFileURL = try XCTUnwrap(project.uri(for: "test.c").fileURL?.realpath)
    try await "void y() {}".writeWithRetry(to: testFileURL)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: DocumentURI(testFileURL), type: .changed)])
    )
    try await project.testClient.send(SynchronizeRequest(index: true))
    XCTAssertEqual(indexedFiles.value, [try project.uri(for: "test.c")])
  }

  func testFilePartOfMultipleTargets() async throws {
    final class BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()

      private let projectRoot: URL

      private let libATarget = BuildTargetIdentifier(uri: try! URI(string: "build://targetA"))
      private let libBTarget = BuildTargetIdentifier(uri: try! URI(string: "build://targetB"))

      private var sources: [SourcesItem] {
        return [
          SourcesItem(
            target: libATarget,
            sources: [
              sourceItem(
                for: projectRoot.appending(component: "Shared.swift"),
                outputPath: fakeOutputPath(for: "Shared.swift", in: "LibA")
              ),
              sourceItem(
                for: projectRoot.appending(component: "LibA.swift"),
                outputPath: fakeOutputPath(for: "LibA.swift", in: "LibA")
              ),
            ]
          ),
          SourcesItem(
            target: libBTarget,
            sources: [
              sourceItem(
                for: projectRoot.appending(component: "Shared.swift"),
                outputPath: fakeOutputPath(for: "Shared.swift", in: "LibB")
              ),
              sourceItem(
                for: projectRoot.appending(component: "LibB.swift"),
                outputPath: fakeOutputPath(for: "LibB.swift", in: "LibB")
              ),
            ]
          ),
        ]
      }

      init(projectRoot: URL, connectionToSourceKitLSP: any LanguageServerProtocol.Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: true
        )
      }

      func workspaceBuildTargetsRequest(
        _ request: WorkspaceBuildTargetsRequest
      ) async throws -> WorkspaceBuildTargetsResponse {
        WorkspaceBuildTargetsResponse(targets: [
          BuildTarget(id: libATarget, languageIds: [.swift], dependencies: []),
          BuildTarget(id: libBTarget, languageIds: [.swift], dependencies: []),
        ])
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return BuildTargetSourcesResponse(items: sources.filter { request.targets.contains($0.target) })
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        let targetSources = try XCTUnwrap(sources.first(where: { $0.target == request.target })?.sources)
        let sourceInfo = try XCTUnwrap(targetSources.first(where: { $0.uri == request.textDocument.uri }))
        var arguments = targetSources.map(\.uri.pseudoPath)
        let targetName = try XCTUnwrap(request.target.uri.arbitrarySchemeURL.host)
        arguments += [
          "-module-name", targetName,
          "-index-unit-output-path", try XCTUnwrap(sourceInfo.sourceKitData?.outputPath),
        ]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    let project = try await CustomBuildServerTestProject(
      files: [
        "Shared.swift": """
        class Shared {}
        """,
        "LibA.swift": """
        class 1️⃣LibA: Shared {}
        """,
        "LibB.swift": """
        class 2️⃣LibB: Shared {}
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )

    let (libAUri, libAPositions) = try project.openDocument("LibA.swift")
    let libATypeHierarchyPrepare = try await project.testClient.send(
      TypeHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(libAUri), position: libAPositions["1️⃣"])
    )
    let libASupertypes = try await project.testClient.send(
      TypeHierarchySupertypesRequest(item: XCTUnwrap(libATypeHierarchyPrepare?.only))
    )
    XCTAssertEqual(libASupertypes?.count, 1)

    let (libBUri, libBPositions) = try project.openDocument("LibB.swift")
    let libBTypeHierarchyPrepare = try await project.testClient.send(
      TypeHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(libBUri), position: libBPositions["2️⃣"])
    )
    let libBSupertypes = try await project.testClient.send(
      TypeHierarchySupertypesRequest(item: XCTUnwrap(libBTypeHierarchyPrepare?.only))
    )
    XCTAssertEqual(libBSupertypes?.count, 1)
  }

  func testHeaderIncludedFromMultipleTargets() async throws {
    final class BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()

      private let projectRoot: URL

      private let libATarget = BuildTargetIdentifier(uri: try! URI(string: "build://targetA"))
      private let libBTarget = BuildTargetIdentifier(uri: try! URI(string: "build://targetB"))

      private var sources: [SourcesItem] {
        return [
          SourcesItem(
            target: libATarget,
            sources: [
              sourceItem(
                for: projectRoot.appending(component: "LibA.c"),
                outputPath: fakeOutputPath(for: "LibA.c", in: "LibA")
              )
            ]
          ),
          SourcesItem(
            target: libBTarget,
            sources: [
              sourceItem(
                for: projectRoot.appending(component: "LibB.c"),
                outputPath: fakeOutputPath(for: "LibB.c", in: "LibB")
              )
            ]
          ),
        ]
      }

      init(projectRoot: URL, connectionToSourceKitLSP: any LanguageServerProtocol.Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: true
        )
      }

      func workspaceBuildTargetsRequest(
        _ request: WorkspaceBuildTargetsRequest
      ) async throws -> WorkspaceBuildTargetsResponse {
        WorkspaceBuildTargetsResponse(targets: [
          BuildTarget(id: libATarget, languageIds: [.c], dependencies: []),
          BuildTarget(id: libBTarget, languageIds: [.c], dependencies: []),
        ])
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return BuildTargetSourcesResponse(items: sources.filter { request.targets.contains($0.target) })
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        let targetSources = try XCTUnwrap(sources.first(where: { $0.target == request.target })?.sources)
        let sourceInfo = try XCTUnwrap(targetSources.first(where: { $0.uri == request.textDocument.uri }))

        var arguments: [String] = [
          sourceInfo.uri.pseudoPath, "-index-unit-output-path", try XCTUnwrap(sourceInfo.sourceKitData?.outputPath),
        ]
        if request.target == libATarget {
          arguments.append("-DLIBA")
        } else if request.target == libBTarget {
          arguments.append("-DLIBB")
        } else {
          throw ResponseError.unknown("Unknown target \(request.target)")
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    let project = try await CustomBuildServerTestProject(
      files: [
        "Header.h": """
        #if defined(LIBA)
        void myTestA() {}
        #elif defined(LIBB)
        void myTestB() {}
        #else
        void myTestC() {}
        #endif
        """,
        "LibA.c": """
        #include "Header.h"
        """,
        "LibB.c": """
        #include "Header.h"
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )

    let workspaceSymbolsBeforeUpdate = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTest"))
    XCTAssertEqual(workspaceSymbolsBeforeUpdate?.compactMap(\.symbolInformation?.name), ["myTestA", "myTestB"])

    try await """
    #if defined(LIBA)
    void myTestA_updated() {}
    #elif defined(LIBB)
    void myTestB_updated() {}
    #else
    void myTestC_updated() {}
    #endif
    """.writeWithRetry(to: XCTUnwrap(project.uri(for: "Header.h").fileURL))

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: try project.uri(for: "Header.h"), type: .changed)])
    )

    try await project.testClient.send(SynchronizeRequest(index: true))

    // Technically, we would need to re-index the header in the context of every target that it's included in. But
    // that's quite expensive. And since we don't re-index all the files that include the header either, we chose to
    // only re-index the header file using a single main file that includes it. In this case, we deterministically pick
    // LibA because it's lexicographically earlier than LibB. We are thus left with the stale `myTestB` entry.
    let workspaceSymbolsAfterUpdate = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTest"))
    XCTAssertEqual(workspaceSymbolsAfterUpdate?.compactMap(\.symbolInformation?.name), ["myTestA_updated", "myTestB"])
  }

  func testCircularSymlink() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Symlink.swift": ""
      ],
      enableBackgroundIndexing: true
    )
    let circularSymlink = try XCTUnwrap(project.uri(for: "Symlink.swift").fileURL)
    try FileManager.default.removeItem(at: circularSymlink)
    try FileManager.default.createSymbolicLink(at: circularSymlink, withDestinationURL: circularSymlink)

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: URI(circularSymlink), type: .changed)])
    )
    // Check that we don't enter an infinite loop trying to index the circular symlink.
    try await project.testClient.send(SynchronizeRequest(index: true))
  }

  func testBuildServerDoesNotReturnIndexUnitOutputPath() async throws {
    final class BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL

      required init(projectRoot: URL, connectionToSourceKitLSP: any LanguageServerProtocol.Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: true
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return BuildTargetSourcesResponse(items: [
          SourcesItem(
            target: .dummy,
            sources: [
              sourceItem(
                for: projectRoot.appending(component: "test.swift"),
                outputPath: fakeOutputPath(for: "test.swift", in: "dummy")
              )
            ]
          )
        ])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        var arguments = [request.textDocument.uri.pseudoPath, "-o", fakeOutputPath(for: "test.swift", in: "dummy")]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    let project = try await CustomBuildServerTestProject(
      files: [
        "test.swift": "func myTestFunc() {}"
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )

    let symbols = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTestFu"))
    XCTAssertEqual(symbols?.compactMap(\.symbolInformation?.name), ["myTestFunc()"])
  }

  func testEnsureSymbolsLoadedIntoIndexstoreDbWhenIndexingHasFinished() async throws {
    let testSetupComplete = AtomicBool(initialValue: false)
    let updateIndexStoreStarted = self.expectation(description: "Update index store started")
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": ""
      ],
      options: .testDefault(experimentalFeatures: [.isIndexingRequest]),
      hooks: Hooks(
        indexHooks: IndexHooks(updateIndexStoreTaskDidStart: { _ in
          guard testSetupComplete.value else {
            return
          }
          updateIndexStoreStarted.fulfill()
        })
      ),
      enableBackgroundIndexing: true,
      pollIndex: false
    )

    try await project.changeFileOnDisk("Test.swift", newMarkedContents: "")
    try await project.testClient.send(SynchronizeRequest(index: true))
    let symbolsBeforeUpdate = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTestFu"))
    XCTAssertEqual(symbolsBeforeUpdate, [])

    testSetupComplete.value = true
    try await project.changeFileOnDisk(
      "Test.swift",
      newMarkedContents: """
        func myTestFunc() {}
        """
    )
    try await fulfillmentOfOrThrow(updateIndexStoreStarted)
    try await repeatUntilExpectedResult(sleepInterval: .milliseconds(2)) {
      try await !project.testClient.send(IsIndexingRequest()).indexing
    }
    // Check that the newly added function has been registered in indexstore-db once indexing is done and that there is
    // no time gap in which indexing has finished but the new unit has not been loaded into indexstore-db yet.
    let symbols = try await project.testClient.send(WorkspaceSymbolsRequest(query: "myTestFu"))
    XCTAssertEqual(symbols?.count, 1)
  }

  func testTargetsAreIndexedInDependencyOrder() async throws {
    // We want to prepare low-level targets before high-level targets to make progress on indexing more quickly.
    let preparationRequests = ThreadSafeBox<[BuildTargetPrepareRequest]>(initialValue: [])
    let twoPreparationRequestsReceived = self.expectation(description: "Received two preparation requests")
    let testHooks = Hooks(
      buildServerHooks: BuildServerHooks(preHandleRequest: { request in
        if let request = request as? BuildTargetPrepareRequest {
          preparationRequests.value.append(request)
          if preparationRequests.value.count >= 2 {
            twoPreparationRequestsReceived.fulfill()
          }
        }
      })
    )
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": "",
        "LibB/LibB.swift": "",
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"])
          ]
        )
        """,
      hooks: testHooks,
      enableBackgroundIndexing: true,
      pollIndex: false
    )
    // We can't poll the index using `workspace/synchronize` because that elevates the priority of the indexing requests
    // in a non-deterministic order (due to the way ). If LibB's priority gets elevated before LibA's, then LibB will
    // get prepared first, which is contrary to the background behavior we want to check here.
    try await fulfillmentOfOrThrow(twoPreparationRequestsReceived)
    XCTAssertEqual(
      preparationRequests.value.flatMap(\.targets),
      [
        try BuildTargetIdentifier(target: "LibA", destination: .target),
        try BuildTargetIdentifier(target: "LibB", destination: .target),
      ]
    )
    withExtendedLifetime(project) {}
  }

  func testIndexingProgressDoesNotGetStuckIfThereAreNoSourceFilesInTarget() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: false
        )
      }

      func workspaceBuildTargetsRequest(
        _ request: WorkspaceBuildTargetsRequest
      ) async throws -> WorkspaceBuildTargetsResponse {
        return WorkspaceBuildTargetsResponse(targets: [
          BuildTarget(
            id: .dummy,
            capabilities: BuildTargetCapabilities(),
            languageIds: [],
            dependencies: []
          )
        ])
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) throws -> BuildTargetSourcesResponse {
        return BuildTargetSourcesResponse(items: [
          SourcesItem(
            target: .dummy,
            sources: []
          )
        ])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) -> TextDocumentSourceKitOptionsResponse? {
        var arguments = [request.textDocument.uri.pseudoPath]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }

      func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> VoidResponse {
        return VoidResponse()
      }
    }

    let expectation = self.expectation(description: "Did receive indexing work done progress")
    let hooks = Hooks(
      indexHooks: IndexHooks(buildGraphGenerationDidStart: {
        // Defer build graph generation long enough so the the debouncer has time to start a work done progress for
        // indexing.
        do {
          try await fulfillmentOfOrThrow(expectation)
        } catch {
          XCTFail("\(error)")
        }
      })
    )
    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.swift": """
        func 1️⃣myTestFunc() {}
        """
      ],
      buildServer: BuildServer.self,
      capabilities: ClientCapabilities(window: WindowClientCapabilities(workDoneProgress: true)),
      hooks: hooks,
      enableBackgroundIndexing: true,
      pollIndex: false,
      preInitialization: { testClient in
        testClient.handleMultipleRequests { (request: CreateWorkDoneProgressRequest) in
          return VoidResponse()
        }
      }
    )
    let startIndexing = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self) { notification in
      guard case .begin(let value) = notification.value else {
        return false
      }
      return value.title == "Indexing"
    }
    expectation.fulfill()
    _ = try await project.testClient.nextNotification(ofType: WorkDoneProgress.self) { notification in
      guard notification.token == startIndexing.token else {
        return false
      }
      guard case .end = notification.value else {
        return false
      }
      return true
    }
  }

  func testIndexMultipleSwiftFilesInSameCompilerInvocation() async throws {
    try await SkipUnless.canIndexMultipleSwiftFilesInSingleInvocation()
    let hooks = Hooks(
      indexHooks: IndexHooks(
        updateIndexStoreTaskDidStart: { taskDescription in
          XCTAssertEqual(
            taskDescription.filesToIndex.map(\.file.sourceFile.fileURL?.lastPathComponent),
            ["First.swift", "Second.swift"]
          )
        }
      )
    )
    _ = try await SwiftPMTestProject(
      files: [
        "First.swift": "",
        "Second.swift": "",
      ],
      hooks: hooks,
      enableBackgroundIndexing: true
    )
  }

  func testIndexMultipleSwiftFilesWithExistingOutputFileMap() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: false
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return self.dummyTargetSourcesResponse(files: [
          DocumentURI(projectRoot.appending(component: "MyFile.swift")),
          DocumentURI(projectRoot.appending(component: "MyOtherFile.swift")),
        ])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        var arguments = [
          try projectRoot.appending(component: "MyFile.swift").filePath,
          try projectRoot.appending(component: "MyOtherFile.swift").filePath,
        ]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        arguments += ["-index-unit-output-path", request.textDocument.uri.pseudoPath + ".o"]
        arguments += ["-output-file-map", "dummy.json"]
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    let project = try await CustomBuildServerTestProject(
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
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
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
              "usr": .string("s:4main3baryyF"),
              "uri": .string(try project.uri(for: "MyOtherFile.swift").stringValue),
            ])
          ),
          fromRanges: [Range(try project.position(of: "3️⃣", in: "MyOtherFile.swift"))]
        )
      ]
    )
  }

  func testSwiftFilesInSameTargetHaveDifferentBuildSettings() async throws {
    // In the real world, this shouldn't happen. If the files within the same target and thus module have different
    // build settings, we wouldn't be able to build them with whole-module-optimization.
    // Check for this anyway to make sure that we provide reasonable behavior even for build servers that are somewhat
    // misbehaving, eg. if for some reasons targets and modules don't line up within the build server.
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: false
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return self.dummyTargetSourcesResponse(files: [
          DocumentURI(projectRoot.appending(component: "MyFile.swift")),
          DocumentURI(projectRoot.appending(component: "MyOtherFile.swift")),
        ])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        var arguments = [
          try projectRoot.appending(component: "MyFile.swift").filePath,
          try projectRoot.appending(component: "MyOtherFile.swift").filePath,
        ]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        arguments += ["-index-unit-output-path", request.textDocument.uri.pseudoPath + ".o"]
        if request.textDocument.uri.fileURL?.lastPathComponent == "MyFile.swift" {
          arguments += ["-DMY_FILE"]
        }
        if request.textDocument.uri.fileURL?.lastPathComponent == "MyOtherFile.swift" {
          arguments += ["-DMY_OTHER_FILE"]
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    let project = try await CustomBuildServerTestProject(
      files: [
        "MyFile.swift": """
        func 1️⃣foo() {}

        #if MY_FILE
        func 2️⃣boo() {
          3️⃣foo()
        }
        #endif
        """,
        "MyOtherFile.swift": """
        #if MY_OTHER_FILE
        func 4️⃣bar() {
          5️⃣foo()
        }
        #endif
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
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
            range: Range(try project.position(of: "4️⃣", in: "MyOtherFile.swift")),
            selectionRange: Range(try project.position(of: "4️⃣", in: "MyOtherFile.swift")),
            data: .dictionary([
              "usr": .string("s:4main3baryyF"),
              "uri": .string(try project.uri(for: "MyOtherFile.swift").stringValue),
            ])
          ),
          fromRanges: [Range(try project.position(of: "5️⃣", in: "MyOtherFile.swift"))]
        ),
        CallHierarchyIncomingCall(
          from: CallHierarchyItem(
            name: "boo()",
            kind: .function,
            tags: nil,
            uri: try project.uri(for: "MyFile.swift"),
            range: Range(try project.position(of: "2️⃣", in: "MyFile.swift")),
            selectionRange: Range(try project.position(of: "2️⃣", in: "MyFile.swift")),
            data: .dictionary([
              "usr": .string("s:4main3booyyF"),
              "uri": .string(try project.uri(for: "MyFile.swift").stringValue),
            ])
          ),
          fromRanges: [Range(try project.position(of: "3️⃣", in: "MyFile.swift"))]
        ),
      ]
    )
  }
}

extension HoverResponseContents {
  var markupContent: MarkupContent? {
    switch self {
    case .markupContent(let markupContent): return markupContent
    default: return nil
    }
  }
}

extension WorkspaceSymbolItem {
  var symbolInformation: SymbolInformation? {
    if case .symbolInformation(let symbolInformation) = self {
      return symbolInformation
    }
    return nil
  }
}
