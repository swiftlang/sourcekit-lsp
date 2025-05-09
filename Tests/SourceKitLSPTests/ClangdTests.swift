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

import LanguageServerProtocol
import SKLogging
import SKOptions
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import TSCBasic
import XCTest

final class ClangdTests: XCTestCase {
  func testClangdGoToInclude() async throws {
    let project = try await MultiFileTestProject(files: [
      "Object.h": "",
      "main.c": """
      #include 1️⃣"Object.h"
      """,
    ])
    let (mainUri, positions) = try project.openDocument("main.c")
    let headerUri = try project.uri(for: "Object.h")

    let goToInclude = DefinitionRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["1️⃣"]
    )
    let resp = try await project.testClient.send(goToInclude)

    let locationsOrLinks = try XCTUnwrap(resp, "No response for go-to-#include")
    switch locationsOrLinks {
    case .locations(let locations):
      XCTAssert(!locations.isEmpty, "Found no locations for go-to-#include")
      if let loc = locations.first {
        XCTAssertEqual(loc.uri, headerUri)
      }
    case .locationLinks(let locationLinks):
      XCTAssert(!locationLinks.isEmpty, "Found no location links for go-to-#include")
      if let link = locationLinks.first {
        XCTAssertEqual(link.targetUri, headerUri)
      }
    }
  }

  func testClangdGoToDefinitionWithoutIndex() async throws {
    let project = try await MultiFileTestProject(files: [
      "Object.h": """
      struct Object {
        int field;
      };
      """,
      "main.c": """
      #include "Object.h"

      int main(int argc, const char *argv[]) {
        struct 1️⃣Object *obj;
      }
      """,
    ])

    let (mainUri, positions) = try project.openDocument("main.c")
    let headerUri = try project.uri(for: "Object.h")

    let goToDefinition = DefinitionRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["1️⃣"]
    )
    let resp = try await project.testClient.send(goToDefinition)

    let locationsOrLinks = try XCTUnwrap(resp, "No response for go-to-definition")
    switch locationsOrLinks {
    case .locations(let locations):
      XCTAssert(!locations.isEmpty, "Found no locations for go-to-definition")
      if let loc = locations.first {
        XCTAssertEqual(loc.uri, headerUri)
      }
    case .locationLinks(let locationLinks):
      XCTAssert(!locationLinks.isEmpty, "Found no location links for go-to-definition")
      if let link = locationLinks.first {
        XCTAssertEqual(link.targetUri, headerUri)
      }
    }
  }

  func testClangdGoToDeclaration() async throws {
    let project = try await MultiFileTestProject(files: [
      "Object.h": """
      struct Object {
        int field;
      };

      struct Object * newObject();
      """,
      "main.c": """
      #include "Object.h"

      int main(int argc, const char *argv[]) {
        struct Object *obj = 1️⃣newObject();
      }
      """,
    ])

    let (mainUri, positions) = try project.openDocument("main.c")
    let headerUri = try project.uri(for: "Object.h")

    let goToInclude = DeclarationRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["1️⃣"]
    )
    let resp = try await project.testClient.send(goToInclude)

    let locationsOrLinks = try XCTUnwrap(resp, "No response for go-to-declaration")
    switch locationsOrLinks {
    case .locations(let locations):
      XCTAssert(!locations.isEmpty, "Found no locations for go-to-declaration")
      if let loc = locations.first {
        XCTAssertEqual(loc.uri, headerUri)
      }
    case .locationLinks(let locationLinks):
      XCTAssert(!locationLinks.isEmpty, "Found no location links for go-to-declaration")
      if let link = locationLinks.first {
        XCTAssertEqual(link.targetUri, headerUri)
      }
    }
  }

  func testRestartClangdIfItDoesntReply() async throws {
    // We simulate clangd not replying until it is restarted using a hook.
    let clangdRestarted = AtomicBool(initialValue: false)
    let clangdRestartedExpectation = self.expectation(description: "clangd restarted")
    let hooks = Hooks(preForwardRequestToClangd: { request in
      if !clangdRestarted.value {
        try? await Task.sleep(for: .seconds(60 * 60))
      }
    })

    let testClient = try await TestSourceKitLSPClient(
      options: SourceKitLSPOptions(semanticServiceRestartTimeout: 1),
      hooks: hooks
    )
    let uri = DocumentURI(for: .c)
    let positions = testClient.openDocument(
      """
      void test() {
        int x1️⃣;
      }
      """,
      uri: uri
    )

    // Monitor clangd to notice when it gets restarted
    let clangdServer = try await unwrap(
      testClient.server.languageService(for: uri, .c, in: unwrap(testClient.server.workspaceForDocument(uri: uri)))
    )
    await clangdServer.addStateChangeHandler { oldState, newState in
      if oldState == .connectionInterrupted, newState == .connected {
        clangdRestarted.value = true
        clangdRestartedExpectation.fulfill()
      }
    }

    // The first hover request should get cancelled by `semanticServiceRestartTimeout`
    await assertThrowsError(
      try await testClient.send(HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"]))
    ) { error in
      XCTAssert(
        (error as? ResponseError)?.message.contains("Timed out") ?? false,
        "Received unexpected error: \(error)"
      )
    }

    try await fulfillmentOfOrThrow(clangdRestartedExpectation)

    // After clangd gets restarted
    let hover = try await testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    assertContains(hover?.contents.markupContent?.value ?? "", "Type: int")
  }
}
