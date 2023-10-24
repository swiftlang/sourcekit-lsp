//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LSPTestSupport
import LanguageServerProtocol
import SKCore
import SKTestSupport
import SourceKitLSP
import TSCBasic
import XCTest

final class WorkspaceTests: XCTestCase {

  func testMultipleSwiftPMWorkspaces() async throws {
    guard let ws = try await staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage") else { return }
    try ws.buildAndIndex()

    guard
      let otherWs = try await staticSourceKitSwiftPMWorkspace(name: "OtherSwiftPMPackage", testClient: ws.testClient)
    else { return }
    try otherWs.buildAndIndex()

    assert(ws.testClient === otherWs.testClient, "Sanity check: The two workspaces should be opened in the same server")

    let call = ws.testLoc("Lib.foo:call")
    let otherCall = otherWs.testLoc("FancyLib.sayHello:call")

    try ws.openDocument(call.url, language: .swift)

    let completions = try await ws.testClient.send(
      CompletionRequest(textDocument: call.docIdentifier, position: call.position)
    )

    XCTAssertEqual(
      completions.items,
      [
        CompletionItem(
          label: "foo()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          sortText: nil,
          filterText: "foo()",
          insertText: "foo()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Position(line: 2, utf16index: 24)..<Position(line: 2, utf16index: 24), newText: "foo()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Lib",
          deprecated: false,
          sortText: nil,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Position(line: 2, utf16index: 24)..<Position(line: 2, utf16index: 24), newText: "self")
          )
        ),
      ]
    )

    try ws.openDocument(otherCall.url, language: .swift)

    let otherCompletions = try await ws.testClient.send(
      CompletionRequest(textDocument: otherCall.docIdentifier, position: otherCall.position)
    )

    XCTAssertEqual(
      otherCompletions.items,
      [
        CompletionItem(
          label: "sayHello()",
          kind: .method,
          detail: "Void",
          documentation: nil,
          deprecated: false,
          sortText: nil,
          filterText: "sayHello()",
          insertText: "sayHello()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(
              range: Position(line: 7, utf16index: 41)..<Position(line: 7, utf16index: 41),
              newText: "sayHello()"
            )
          )
        ),
        CompletionItem(
          label: "self",
          kind: LanguageServerProtocol.CompletionItemKind(rawValue: 14),
          detail: "FancyLib",
          documentation: nil,
          deprecated: false,
          sortText: nil,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Position(line: 7, utf16index: 41)..<Position(line: 7, utf16index: 41), newText: "self")
          )
        ),
      ]
    )
  }

  func testMultipleClangdWorkspaces() async throws {
    let ws = try await MultiFileTestWorkspace(
      files: [
        "WorkspaceA/main.cpp": """
        #if FOO
        void 1️⃣foo2️⃣() {}
        #else
        void foo() {}
        #endif

        int main() {
          3️⃣foo4️⃣();
        }
        """,
        "WorkspaceA/compile_flags.txt": """
        -DFOO
        """,
        "WorkspaceB/test.m": "",
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir.appendingPathComponent("WorkspaceA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appendingPathComponent("WorkspaceB"))),
        ]
      }
    )

    _ = try ws.openDocument("test.m")

    let diags = try await ws.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 0)

    let (mainUri, positions) = try ws.openDocument("main.cpp")

    let highlightRequest = DocumentHighlightRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["3️⃣"]
    )
    let highlightResponse = try await ws.testClient.send(highlightRequest)
    XCTAssertEqual(
      highlightResponse,
      [
        DocumentHighlight(range: positions["1️⃣"]..<positions["2️⃣"], kind: .text),
        DocumentHighlight(range: positions["3️⃣"]..<positions["4️⃣"], kind: .text),
      ]
    )
  }

  func testRecomputeFileWorkspaceMembershipOnPackageSwiftChange() async throws {
    guard let otherWs = try await staticSourceKitSwiftPMWorkspace(name: "OtherSwiftPMPackage") else { return }
    try otherWs.buildAndIndex()

    guard let ws = try await staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage", testClient: otherWs.testClient)
    else {
      return
    }
    try ws.buildAndIndex()

    assert(ws.testClient === otherWs.testClient, "Sanity check: The two workspaces should be opened in the same server")

    let otherLib = ws.testLoc("OtherLib.topLevelFunction:libMember")
    let packageTargets = ws.testLoc("Package.swift:targets")

    try ws.openDocument(otherLib.url, language: .swift)

    // We open OtherSwiftPMPackage first. Thus, otherLib (which is a folder in
    // SwiftPMPackage that hasn't been added to Package.swift yet) will belong
    // to OtherSwiftPMPackage by default (because it provides fallback build
    // settings for it).
    assertEqual(
      await ws.testClient.server.workspaceForDocument(uri: otherLib.docUri)?.rootUri,
      DocumentURI(otherWs.sources.rootDirectory)
    )

    // Add the otherlib target to Package.swift
    _ = try ws.sources.edit { builder in
      let packageManifest = ws.sources.rootDirectory
        .appendingPathComponent("Package.swift")
      var packageManifestContents = try String(contentsOf: packageManifest, encoding: .utf8)
      let targetMarkerRange = packageManifestContents.range(of: "/*Package.swift:targets*/")!
      packageManifestContents.replaceSubrange(
        targetMarkerRange,
        with: """
          .target(
             name: "otherlib",
             dependencies: ["lib"]
          ),
          /*Package.swift:targets*/
          """
      )
      builder.write(packageManifestContents, to: packageManifest)
    }

    ws.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: packageTargets.docUri, type: .changed)
      ])
    )

    // After updating Package.swift in SwiftPMPackage, SwiftPMPackage can
    // provide proper build settings for otherLib and thus workspace
    // membership should switch to SwiftPMPackage.

    // Updating the build settings takes a few seconds. Send code completion requests every second until we receive correct results.
    var didReceiveCorrectWorkspaceMembership = false

    // Updating the build settings takes a few seconds. Send code completion requests every second until we receive correct results.
    for _ in 0..<30 {
      if await ws.testClient.server.workspaceForDocument(uri: otherLib.docUri)?.rootUri
        == DocumentURI(ws.sources.rootDirectory)
      {
        didReceiveCorrectWorkspaceMembership = true
        break
      }
      try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    XCTAssert(didReceiveCorrectWorkspaceMembership)
  }

  func testMixedPackage() async throws {
    let ws = try await SwiftPMTestWorkspace(
      files: [
        "clib/include/clib.h": """
        #ifndef CLIB_H
        #define CLIB_H

        void clib_func(void);
        void clib_other(void);

        #endif // CLIB_H
        """,
        "clib/clib.c": """
        #include "clib.h"

        void clib_func(void) {1️⃣}
        """,
        "lib/lib.swift": """
        public struct Lib {
          public func foo() {}
          public init() {}
        }
        2️⃣
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "lib", dependencies: []),
            .target(name: "clib", dependencies: []),
          ]
        )
        """
    )

    let (swiftUri, swiftPositions) = try ws.openDocument("lib.swift")
    let (cUri, cPositions) = try ws.openDocument("clib.c")

    let cCompletions = try await ws.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(cUri), position: cPositions["1️⃣"])
    )
    XCTAssertGreaterThanOrEqual(cCompletions.items.count, 0)

    let swiftCompletions = try await ws.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(swiftUri), position: swiftPositions["2️⃣"])
    )
    XCTAssertGreaterThanOrEqual(swiftCompletions.items.count, 0)
  }

  func testChangeWorkspaceFolders() async throws {
    let ws = try await MultiFileTestWorkspace(
      files: [
        "subdir/Sources/otherPackage/otherPackage.swift": """
        import package

        func test() {
          Package().1️⃣helloWorld()
        }
        """,
        "subdir/Sources/package/package.swift": """
        public struct Package {
          public init() {}

          public func helloWorld() {
            print("Hello world!")
          }
        }
        """,
        "subdir/Package.swift": """
        // swift-tools-version: 5.5

        import PackageDescription

        let package = Package(
          name: "package",
          products: [
            .library(name: "package", targets: ["package"]),
            .library(name: "otherPackage", targets: ["otherPackage"]),
          ],
          targets: [
            .target(
              name: "package",
              dependencies: []
            ),
            .target(
              name: "otherPackage",
              dependencies: ["package"]
            ),
          ]
        )
        """,
      ]
    )

    let packageDir = try ws.uri(for: "Package.swift").fileURL!.deletingLastPathComponent()

    try await TSCBasic.Process.checkNonZeroExit(arguments: [
      ToolchainRegistry.shared.default!.swift!.pathString,
      "build",
      "--package-path", packageDir.path,
      "-Xswiftc", "-index-ignore-system-modules",
      "-Xcc", "-index-ignore-system-symbols",
    ])

    let (otherPackageUri, positions) = try ws.openDocument("otherPackage.swift")
    let testPosition = positions["1️⃣"]

    let preChangeWorkspaceResponse = try await ws.testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(otherPackageUri),
        position: testPosition
      )
    )

    XCTAssertEqual(
      preChangeWorkspaceResponse.items,
      [],
      "Did not expect to receive cross-module code completion results if we opened the parent directory of the package"
    )

    ws.testClient.send(
      DidChangeWorkspaceFoldersNotification(
        event: WorkspaceFoldersChangeEvent(added: [
          WorkspaceFolder(uri: DocumentURI(packageDir))
        ])
      )
    )

    let postChangeWorkspaceResponse = try await ws.testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(otherPackageUri),
        position: testPosition
      )
    )

    XCTAssertEqual(
      postChangeWorkspaceResponse.items,
      [
        CompletionItem(
          label: "helloWorld()",
          kind: .method,
          detail: "Void",
          documentation: nil,
          deprecated: false,
          sortText: nil,
          filterText: "helloWorld()",
          insertText: "helloWorld()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(
              range: Range(testPosition),
              newText: "helloWorld()"
            )
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Package",
          documentation: nil,
          deprecated: false,
          sortText: nil,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(
              range: Range(testPosition),
              newText: "self"
            )
          )
        ),
      ]
    )
  }
}
