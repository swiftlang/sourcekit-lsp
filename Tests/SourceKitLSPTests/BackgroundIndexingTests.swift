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

fileprivate actor ExpectedPreparationTracker {
  /// The targets we expect to be prepared. For targets within the same set, we don't care about the exact order.
  private var expectedPreparations: [Set<ConfiguredTarget>]

  /// Implicitly-unwrapped optional so we can reference `self` when creating `IndexTestHooks`.
  /// `nonisolated(unsafe)` is fine because this is not modified after `testHooks` is created.
  nonisolated(unsafe) var testHooks: IndexTestHooks!

  init(expectedPreparations: [Set<ConfiguredTarget>]) {
    self.expectedPreparations = expectedPreparations
    self.testHooks = IndexTestHooks(preparationTaskDidFinish: { [weak self] in
      await self?.preparationTaskDidFinish(taskDescription: $0)
    })
  }

  func preparationTaskDidFinish(taskDescription: PreparationTaskDescription) -> Void {
    guard let expectedTargetsToPrepare = expectedPreparations.first else {
      XCTFail("Didn't expect a preparation but received \(taskDescription)")
      return
    }
    guard Set(taskDescription.targetsToPrepare).isSubset(of: expectedTargetsToPrepare) else {
      XCTFail("Received unexpected preparation of \(taskDescription)")
      return
    }
    let remainingExpectedTargetsToPrepare = expectedTargetsToPrepare.subtracting(taskDescription.targetsToPrepare)
    if remainingExpectedTargetsToPrepare.isEmpty {
      expectedPreparations.remove(at: 0)
    } else {
      expectedPreparations[0] = remainingExpectedTargetsToPrepare
    }
  }

  deinit {
    let expectedPreparations = self.expectedPreparations
    XCTAssert(
      expectedPreparations.isEmpty,
      "ExpectedPreparationTracker destroyed with unfulfilled expected preparations: \(expectedPreparations)."
    )
  }
}

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

  func testPrepareTarget() async throws {
    try await SkipUnless.swiftpmStoresModulesInSubdirectory()
    var serverOptions = backgroundIndexingOptions
    let expectedPreparationTracker = ExpectedPreparationTracker(expectedPreparations: [
      [
        ConfiguredTarget(targetID: "LibA", runDestinationID: "dummy"),
        ConfiguredTarget(targetID: "LibB", runDestinationID: "dummy"),
      ],
      [
        ConfiguredTarget(targetID: "LibA", runDestinationID: "dummy"),
        ConfiguredTarget(targetID: "LibB", runDestinationID: "dummy"),
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
      cleanUp: { /* Keep expectedPreparationTracker alive */ _ = expectedPreparationTracker }
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
    project.testClient.handleNextRequest { (_: DiagnosticsRefreshRequest) in
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
}
