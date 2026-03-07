//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
import SKTestSupport
import SemanticIndex
import SourceKitLSP
import SwiftExtensions
import XCTest

#if os(Windows)
import WinSDK
#elseif canImport(Android)
import Android
#endif

final class PullDiagnosticsTests: SourceKitLSPTestCase {
  func testUnknownIdentifierDiagnostic() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """
      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let report = try await testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))

    XCTAssertEqual(report.fullReport?.items.count, 1)
    let diagnostic = try XCTUnwrap(report.fullReport?.items.first)
    XCTAssertEqual(diagnostic.range, Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9))
  }

  func testDiagnosticsIfFileIsOpenedWithLowercaseDriveLetter() async throws {
    try SkipUnless.platformIsWindows("Drive letters only exist on Windows")

    let fileContents = """
      func foo() {
        invalid
      }
      """

    // We use `IndexedSingleSwiftFileTestProject` so that the test file exists on disk, which causes sourcekitd to
    // uppercase the drive letter.
    let project = try await IndexedSingleSwiftFileTestProject(fileContents, allowBuildFailure: true)
    project.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(project.fileURI)))

    let filePath = try XCTUnwrap(project.fileURI.fileURL?.filePath)
    XCTAssertEqual(filePath[filePath.index(filePath.startIndex, offsetBy: 1)], ":")
    let lowercaseDriveLetterPath = filePath.first!.lowercased() + filePath.dropFirst()
    let uri = DocumentURI(filePath: lowercaseDriveLetterPath, isDirectory: false)
    project.testClient.openDocument(fileContents, uri: uri)

    let report = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )

    XCTAssertEqual(report.fullReport?.items.count, 1)
    let diagnostic = try XCTUnwrap(report.fullReport?.items.first)
    XCTAssertEqual(diagnostic.range, Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9))
  }

  /// Test that we can get code actions for pulled diagnostics (https://github.com/swiftlang/sourcekit-lsp/issues/776)
  func testCodeActions() async throws {
    let testClient = try await TestSourceKitLSPClient(
      capabilities: ClientCapabilities(
        workspace: nil,
        textDocument: .init(
          codeAction: .init(codeActionLiteralSupport: .init(codeActionKind: .init(valueSet: [.quickFix])))
        )
      )
    )
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      protocol MyProtocol {
        func bar()
      }

      struct 1️⃣Test: 2️⃣MyProtocol {}
      """,
      uri: uri
    )
    let report = try await testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    let diagnostics = try XCTUnwrap(report.fullReport?.items)

    let diagnostic = try XCTUnwrap(diagnostics.only)
    XCTAssert(
      diagnostic.range == Range(positions["1️⃣"]) || diagnostic.range == Range(positions["2️⃣"]),
      "Unexpected range: \(diagnostic.range)"
    )
    let note = try XCTUnwrap(diagnostic.relatedInformation?.first)
    XCTAssert(
      note.location.range == Range(positions["1️⃣"]) || note.location.range == Range(positions["2️⃣"]),
      "Unexpected range: \(note.location.range)"
    )
    XCTAssertEqual(note.codeActions?.count ?? 0, 1)

    let response = try await testClient.send(
      CodeActionRequest(
        range: note.location.range,
        context: CodeActionContext(
          diagnostics: diagnostics,
          only: [.quickFix],
          triggerKind: .invoked
        ),
        textDocument: TextDocumentIdentifier(note.location.uri)
      )
    )

    guard case .codeActions(let actions) = response else {
      XCTFail("Expected codeActions response")
      return
    }

    XCTAssertEqual(actions.count, 2)
    XCTAssert(
      actions.contains { action in
        // Allow the action message to be the one before or after
        // https://github.com/apple/swift/pull/67909, ensuring this test passes with
        // a sourcekitd that contains the change from that PR as well as older
        // toolchains that don't contain the change yet.
        [
          "Add stubs for conformance",
          "Do you want to add protocol stubs?",
        ].contains(action.title)
      }
    )
  }

  func testNotesFromIntegratedSwiftSyntaxDiagnostics() async throws {
    // Create a workspace that has compile_commands.json so that it has a build server but no compiler arguments
    // for test.swift so that we fall back to producing diagnostics from the built-in swift-syntax.
    let project = try await MultiFileTestProject(files: [
      "test.swift": "func foo() 1️⃣{2️⃣",
      "compile_commands.json": "[]",
    ])

    let (uri, positions) = try project.openDocument("test.swift")

    let report = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    let diagnostic = try XCTUnwrap(report.fullReport?.items.only)
    XCTAssertEqual(diagnostic.message, "expected '}' to end function")
    XCTAssertEqual(diagnostic.range, Range(positions["2️⃣"]))

    let note = try XCTUnwrap(diagnostic.relatedInformation?.only)
    XCTAssertEqual(note.message, "to match this opening '{'")
    XCTAssertEqual(note.location.range, positions["1️⃣"]..<positions["2️⃣"])
  }

  func testDiagnosticUpdatedAfterFilesInSameModuleAreUpdated() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "",
        "FileB.swift": """
        func test() {
          sayHello()
        }
        """,
      ],
      capabilities: ClientCapabilities(
        workspace: WorkspaceClientCapabilities(diagnostics: RefreshRegistrationCapability(refreshSupport: true))
      )
    )

    let (bUri, _) = try project.openDocument("FileB.swift")
    let beforeChangingFileA = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(bUri))
    )
    XCTAssert(
      (beforeChangingFileA.fullReport?.items ?? []).contains(where: { $0.message == "Cannot find 'sayHello' in scope" })
    )

    let diagnosticsRefreshRequestReceived = self.expectation(description: "DiagnosticsRefreshRequest received")
    project.testClient.handleSingleRequest { (request: DiagnosticsRefreshRequest) in
      diagnosticsRefreshRequestReceived.fulfill()
      return VoidResponse()
    }

    try await project.changeFileOnDisk("FileA.swift", newMarkedContents: "func sayHello() {}")
    try await fulfillmentOfOrThrow(diagnosticsRefreshRequestReceived)

    let afterChangingFileA = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(bUri))
    )
    XCTAssertEqual(afterChangingFileA.fullReport?.items, [])
  }

  func testDiagnosticUpdatedAfterDependentModuleIsBuilt() async throws {
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
        """,
      capabilities: ClientCapabilities(
        workspace: WorkspaceClientCapabilities(diagnostics: RefreshRegistrationCapability(refreshSupport: true))
      )
    )

    let (bUri, _) = try project.openDocument("LibB.swift")

    // We might receive empty syntactic diagnostics before getting build settings. Wait until we get the diagnostic
    // about the missing module.
    try await repeatUntilExpectedResult {
      let beforeBuilding = try? await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(bUri))
      )
      if (beforeBuilding?.fullReport?.items ?? []).map(\.message).contains("No such module 'LibA'") {
        return true
      }
      logger.debug("Received unexpected diagnostics: \(beforeBuilding?.forLogging)")
      return false
    }

    let diagnosticsRefreshRequestReceived = self.expectation(description: "DiagnosticsRefreshRequest received")
    project.testClient.handleSingleRequest { (request: DiagnosticsRefreshRequest) in
      diagnosticsRefreshRequestReceived.fulfill()
      return VoidResponse()
    }

    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    project.testClient.send(
      DidChangeWatchedFilesNotification(
        changes:
          FileManager.default.findFiles(withExtension: "swiftmodule", in: project.scratchDirectory).map {
            FileEvent(uri: DocumentURI($0), type: .created)
          }
      )
    )

    try await fulfillmentOfOrThrow(diagnosticsRefreshRequestReceived)

    let afterChangingFileA = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(bUri))
    )
    XCTAssertEqual(afterChangingFileA.fullReport?.items, [])
  }

  func testDiagnosticsWaitForDocumentToBePrepared() async throws {
    let diagnosticRequestSent = MultiEntrySemaphore(name: "Diagnostic request sent")
    var testHooks = Hooks()
    testHooks.indexHooks.preparationTaskDidStart = { @Sendable taskDescription in
      // Only start preparation after we sent the diagnostic request. In almost all cases, this should not give
      // preparation enough time to finish before the diagnostic request is handled unless we wait for preparation in
      // the diagnostic request.
      await diagnosticRequestSent.waitOrXCTFail()
    }

    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func sayHello() {}
        """,
        "LibB/LibB.swift": """
        import LibA

        func test() {
          sayHello()
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

    let (uri, _) = try project.openDocument("LibB.swift")

    // Use completion handler based method to send request so we can fulfill `diagnosticRequestSent` after sending it
    // but before receiving a reply. The async variant doesn't allow this distinction.
    let receivedDiagnostics = self.expectation(description: "Received diagnostics")
    project.testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))) { diagnostics in
      XCTAssertEqual(diagnostics.success?.fullReport?.items, [])
      receivedDiagnostics.fulfill()
    }
    diagnosticRequestSent.signal()
    try await fulfillmentOfOrThrow(receivedDiagnostics)
  }

  func testDontReturnEmptyDiagnosticsIfDiagnosticRequestIsCancelled() async throws {
    // Use an example that is slow to type check to ensure that we don't get a diagnostic response from sourcekitd
    // before the request cancellation gets handled.
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": """
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
      enableBackgroundIndexing: false
    )
    let (uri, _) = try project.openDocument("Lib.swift")

    let diagnosticResponseReceived = self.expectation(description: "Received diagnostic response")
    let requestID = project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    ) { result in
      XCTAssertEqual(result, .failure(ResponseError.cancelled))
      diagnosticResponseReceived.fulfill()
    }
    project.testClient.send(CancelRequestNotification(id: requestID))
    try await fulfillmentOfOrThrow(diagnosticResponseReceived)
  }

  func testNoteInSecondaryFile() async throws {
    let project = try await SwiftPMTestProject(files: [
      "FileA.swift": """
      @available(*, unavailable)
      struct 1️⃣Test {}
      """,
      "FileB.swift": """
      func test() {
          _ = Test()
      }
      """,
    ])

    let (uri, _) = try project.openDocument("FileB.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    let diagnostic = try XCTUnwrap(diagnostics.fullReport?.items.only)
    let note = try XCTUnwrap(diagnostic.relatedInformation?.only)
    XCTAssertEqual(note.location, try project.location(from: "1️⃣", to: "1️⃣", in: "FileA.swift"))
  }

  func testDiagnosticsFromSourcekitdRequestError() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "test.swift": """
        func test() {}
        """,
        "compile_flags.txt": "-invalid-argument",
      ]
    )
    let (uri, _) = try project.openDocument("test.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items,
      [
        Diagnostic(
          range: Range(Position(line: 0, utf16index: 0)),
          severity: .error,
          source: "SourceKit",
          message: "Internal SourceKit error: unknown argument: '-invalid-argument'"
        )
      ]
    )
  }

  func testDiagnosticsWhenOpeningProjectFromSymlink() async throws {
    let contents = """
      let x: String = 1
      """
    let project = try await SwiftPMTestProject(
      files: ["FileA.swift": contents],
      workspaces: { scratchDirectory in
        let symlinkUrl = scratchDirectory.appending(component: "symlink")
        try FileManager.default.createSymbolicLink(
          at: symlinkUrl,
          withDestinationURL: scratchDirectory
        )
        return [WorkspaceFolder(uri: DocumentURI(symlinkUrl))]
      }
    )

    let uri = DocumentURI(
      project.scratchDirectory
        .appending(components: "symlink", "Sources", "MyLibrary", "FileA.swift")
    )
    project.testClient.send(
      DidOpenTextDocumentNotification(
        textDocument: TextDocumentItem(uri: uri, language: .swift, version: 0, text: contents)
      )
    )
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    let diagnostic = try XCTUnwrap(diagnostics.fullReport?.items.only)
    XCTAssertEqual(diagnostic.message, "Cannot convert value of type 'Int' to specified type 'String'")
  }

  func testDiagnosticsInScripts() async throws {
    let project = try await SwiftPMTestProject(files: [
      "Test.swift": "",
      "/script.swift": """
      1️⃣let x: String = 1
      """,
    ])

    // We should not report diagnostics for random files in the workspace. They are likely part of a target that we
    // don't know about and produce nonsensical diagnostics.
    let (uri, positions) = try project.openDocument("script.swift")
    let diagnosticsBeforeEdit = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(diagnosticsBeforeEdit.fullReport?.items, [])

    // But if the source file contains a shebang, we know that it is intended to be executed by its own an thus fallback
    // build settings will be sufficient to generate diagnostics for it.
    project.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(positions["1️⃣"]), text: "#!/usr/bin/env swift\n")]
      )
    )
    let diagnosticsAfterEdit = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnosticsAfterEdit.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'String'"]
    )
  }
}
