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

@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
import SKTestSupport
import XCTest

final class PublishDiagnosticsTests: SourceKitLSPTestCase {
  func testUnknownIdentifierDiagnostic() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """
      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let diags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    XCTAssertEqual(
      diags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
  }

  func testRangeShiftAfterNewlineAdded() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """
      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(
            range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
            rangeLength: 0,
            text: "\n"
          )
        ]
      )
    )

    let editDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )
  }

  func testRangeShiftAfterNewlineRemoved() async throws {
    let testClient = try await TestSourceKitLSPClient(usePullDiagnostics: false)
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """

      func foo() {
        invalid
      }
      """,
      uri: uri
    )

    let openDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(openDiags.diagnostics.count, 1)
    XCTAssertEqual(
      openDiags.diagnostics.first?.range,
      Position(line: 2, utf16index: 2)..<Position(line: 2, utf16index: 9)
    )

    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(
            range: Position(line: 0, utf16index: 0)..<Position(line: 1, utf16index: 0),
            rangeLength: 1,
            text: ""
          )
        ]
      )
    )

    let editDiags = try await testClient.nextDiagnosticsNotification()
    XCTAssertEqual(editDiags.diagnostics.count, 1)
    XCTAssertEqual(
      editDiags.diagnostics.first?.range,
      Position(line: 1, utf16index: 2)..<Position(line: 1, utf16index: 9)
    )
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
      usePullDiagnostics: false
    )

    _ = try project.openDocument("FileB.swift")
    try await repeatUntilExpectedResult {
      let diagnostics = try await project.testClient.nextDiagnosticsNotification()
      if diagnostics.diagnostics.contains(where: { $0.message == "Cannot find 'sayHello' in scope" }) {
        return true
      }
      logger.debug("Received unexpected diagnostics: \(diagnostics.forLogging)")
      return false
    }

    try await project.changeFileOnDisk("FileA.swift", newMarkedContents: "func sayHello() {}")

    let diagnosticsAfterChangingFileA = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diagnosticsAfterChangingFileA.diagnostics, [])
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
      usePullDiagnostics: false
    )

    _ = try project.openDocument("LibB.swift")

    // We might receive empty syntactic diagnostics before getting build settings. Wait until we get the diagnostic
    // about the missing module.
    try await repeatUntilExpectedResult {
      let diagnosticsBeforeBuilding = try? await project.testClient.nextDiagnosticsNotification(timeout: .seconds(1))
      if (diagnosticsBeforeBuilding?.diagnostics ?? []).map(\.message).contains("No such module 'LibA'") {
        return true
      }
      logger.debug("Received unexpected diagnostics: \(diagnosticsBeforeBuilding?.forLogging)")
      return false
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

    let diagnosticsAfterBuilding = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diagnosticsAfterBuilding.diagnostics, [])
  }
}
