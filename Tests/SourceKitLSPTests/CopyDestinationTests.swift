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

import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(Testing) @_spi(SourceKitLSP) import SKLogging
import SKTestSupport
import SwiftExtensions
import XCTest

class CopyDestinationTests: SourceKitLSPTestCase {
  actor BuildServer: CustomBuildServer {
    let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
    private let projectRoot: URL

    var headerCopyDestination: URL {
      projectRoot.appending(components: "header-copy", "CopiedTest.h")
    }

    init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
      self.projectRoot = projectRoot
    }

    func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
      return try initializationResponseSupportingBackgroundIndexing(
        projectRoot: projectRoot,
        outputPathsProvider: false
      )
    }

    func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
      return BuildTargetSourcesResponse(items: [
        SourcesItem(
          target: .dummy,
          sources: [
            SourceItem(
              uri: DocumentURI(projectRoot.appending(component: "Test.c")),
              kind: .file,
              generated: false,
              dataKind: .sourceKit,
              data: SourceKitSourceItemData(
                language: .c,
                kind: .source,
              ).encodeToLSPAny()
            ),
            SourceItem(
              uri: DocumentURI(projectRoot.appending(component: "Test.h")),
              kind: .file,
              generated: false,
              dataKind: .sourceKit,
              data: SourceKitSourceItemData(
                language: .c,
                kind: .header,
                copyDestinations: [DocumentURI(headerCopyDestination)]
              ).encodeToLSPAny()
            ),
          ]
        )
      ])
    }

    func textDocumentSourceKitOptionsRequest(
      _ request: TextDocumentSourceKitOptionsRequest
    ) throws -> TextDocumentSourceKitOptionsResponse? {
      return TextDocumentSourceKitOptionsResponse(compilerArguments: [
        request.textDocument.uri.pseudoPath,
        "-I", try headerCopyDestination.deletingLastPathComponent().filePath,
        "-D", "FOO",
      ])
    }

    func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> VoidResponse {
      try FileManager.default.createDirectory(
        at: headerCopyDestination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.copyItem(
        at: projectRoot.appending(component: "Test.h"),
        to: headerCopyDestination
      )
      return VoidResponse()
    }
  }

  func testJumpToCopiedHeader() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.h": """
        void hello();
        """,
        "Test.c": """
        #include <CopiedTest.h>

        void test() {
          1️⃣hello();
        }
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true,
    )
    try await project.testClient.send(SynchronizeRequest(copyFileMap: true))

    let (uri, positions) = try project.openDocument("Test.c")
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(response?.locations?.map(\.uri), [try project.uri(for: "Test.h")])
  }

  func testFindReferencesInCopiedHeader() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.h": """
        void 1️⃣hello();
        """,
        "Test.c": """
        #include <CopiedTest.h>

        void test() {
          2️⃣hello();
        }
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )
    try await project.testClient.send(SynchronizeRequest(copyFileMap: true))

    let (uri, positions) = try project.openDocument("Test.c")
    let response = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )
    let expected = [
      try project.location(from: "2️⃣", to: "2️⃣", in: "Test.c"),
      try project.location(from: "1️⃣", to: "1️⃣", in: "Test.h"),
    ]
    XCTAssertEqual(response, expected)
  }

  func testFindDeclarationInCopiedHeader() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.h": """
        void 1️⃣hello2️⃣();
        """,
        "Test.c": """
        #include <CopiedTest.h>

        void hello() {}

        void test() {
          3️⃣hello();
        }
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )
    try await project.testClient.send(SynchronizeRequest(copyFileMap: true))

    let (uri, positions) = try project.openDocument("Test.c")
    let response = try await project.testClient.send(
      DeclarationRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["3️⃣"]
      )
    )
    XCTAssertEqual(
      response?.locations,
      [
        try project.location(from: "1️⃣", to: "2️⃣", in: "Test.h")
      ]
    )
  }

  func testWorkspaceSymbolsInCopiedHeader() async throws {
    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.h": """
        void 1️⃣hello();
        """,
        "Test.c": """
        #include <CopiedTest.h>

        void test() {
          hello();
        }
        """,
      ],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: true
    )
    try await project.testClient.send(SynchronizeRequest(copyFileMap: true))

    _ = try project.openDocument("Test.c")
    let response = try await project.testClient.send(
      WorkspaceSymbolsRequest(query: "hello")
    )
    let item = try XCTUnwrap(response?.only)
    guard case .symbolInformation(let info) = item else {
      XCTFail("Expected a symbol information")
      return
    }
    XCTAssertEqual(info.location, try project.location(from: "1️⃣", to: "1️⃣", in: "Test.h"))
  }

  func testSemanticFunctionalityInCopiedHeader() async throws {
    let contents = """
      #ifdef FOO
      typedef void 1️⃣MY_VOID2️⃣;
      #else
      typedef void MY_VOID;
      #endif
      3️⃣MY_VOID hello();
      """

    let project = try await CustomBuildServerTestProject(
      files: ["Test.h": contents],
      buildServer: BuildServer.self,
      enableBackgroundIndexing: false,
    )
    try await project.testClient.send(SynchronizeRequest(copyFileMap: true))
    let headerUri = try await DocumentURI(project.buildServer().headerCopyDestination)

    let positions = project.testClient.openDocument(contents, uri: headerUri, language: .c)
    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(headerUri), position: positions["3️⃣"])
    )
    XCTAssertEqual(response?.locations, [try project.location(from: "1️⃣", to: "2️⃣", in: "Test.h")])
  }
}
