//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SwiftExtensions
import XCTest

final class IndexTests: SourceKitLSPTestCase {
  func testIndexSwiftModules() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func 1️⃣aaa() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func bbb() {
          2️⃣aaa()
        }
        """,
        "LibC/LibC.swift": """
        import LibA
        public func ccc() {
          3️⃣aaa()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
           .target(name: "LibC", dependencies: ["LibA", "LibB"]),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (libAUri, libAPositions) = try project.openDocument("LibA.swift")
    let libBUri = try project.uri(for: "LibB.swift")
    let (libCUri, libCPositions) = try project.openDocument("LibC.swift")

    let definitionPos = libAPositions["1️⃣"]
    let referencePos = try project.position(of: "2️⃣", in: "LibB.swift")
    let callPos = libCPositions["3️⃣"]

    // MARK: Jump to definition

    let response = try await project.testClient.send(
      DefinitionRequest(
        textDocument: TextDocumentIdentifier(libCUri),
        position: libCPositions["3️⃣"]
      )
    )
    let jump = try XCTUnwrap(response?.locations)

    XCTAssertEqual(jump.count, 1)
    XCTAssertEqual(jump.first?.uri, libAUri)
    XCTAssertEqual(jump.first?.range.lowerBound, definitionPos)

    // MARK: Find references

    let refs = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(libAUri),
        position: definitionPos,
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(refs),
      [
        Location(
          uri: libAUri,
          range: Range(definitionPos)
        ),
        Location(
          uri: libBUri,
          range: Range(referencePos)
        ),
        Location(
          uri: libCUri,
          range: Range(callPos)
        ),
      ]
    )
  }

  func testIndexShutdown() async throws {
    func listdir(_ url: URL) throws -> [URL] {
      try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    func checkRunningIndex(cleanUp: Bool, workspaceDirectory: URL) async throws -> URL? {
      let project = try await IndexedSingleSwiftFileTestProject(
        """
        func 1️⃣foo() {}

        func bar() {
          2️⃣foo()
        }
        """,
        workspaceDirectory: workspaceDirectory,
        cleanUp: cleanUp
      )

      let response = try await project.testClient.send(
        DefinitionRequest(
          textDocument: TextDocumentIdentifier(project.fileURI),
          position: project.positions["2️⃣"]
        )
      )
      let jump = try XCTUnwrap(response?.locations)
      XCTAssertEqual(jump.count, 1)
      XCTAssertEqual(jump.first?.uri, project.fileURI)
      XCTAssertEqual(jump.first?.range.lowerBound, project.positions["1️⃣"])

      let indexDBURL = project.fileURI.fileURL!.deletingLastPathComponent().appending(component: "IndexDatabase")
      let tmpContents = try listdir(indexDBURL)
      guard let versionedPath = tmpContents.filter({ $0.lastPathComponent.starts(with: "v") }).only else {
        XCTFail("expected one version path 'v[0-9]*', found \(tmpContents)")
        return nil
      }

      let versionContentsBefore = try listdir(versionedPath)
      XCTAssertEqual(versionContentsBefore.count, 1, "Received multiple versions: \(versionContentsBefore)")
      XCTAssert(
        versionContentsBefore.first?.lastPathComponent.starts(with: "p") ?? false,
        "Received unexpected version: \(versionContentsBefore.first?.lastPathComponent ?? "<nil>")"
      )

      _ = try await project.testClient.send(ShutdownRequest())
      return versionedPath
    }

    let workspaceDirectory = try testScratchDir()

    guard let versionedPath = try await checkRunningIndex(cleanUp: false, workspaceDirectory: workspaceDirectory) else {
      return
    }

    let versionContentsAfter = try listdir(versionedPath)
    XCTAssertEqual(versionContentsAfter.count, 1)
    XCTAssertEqual(versionContentsAfter.first?.lastPathComponent, "saved")

    _ = try await checkRunningIndex(cleanUp: true, workspaceDirectory: workspaceDirectory)
  }
}
