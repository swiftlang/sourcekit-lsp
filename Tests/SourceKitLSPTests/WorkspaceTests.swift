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

import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKTestSupport
import SemanticIndex
import SourceKitLSP
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

final class WorkspaceTests: SourceKitLSPTestCase {
  func testMultipleSwiftPMWorkspaces() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    // The package manifest is the same for both packages we open.
    let packageManifest = """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLibrary",
        targets: [
          .target(name: "MyLibrary"),
          .executableTarget(name: "MyExec", dependencies: ["MyLibrary"])
        ]
      )
      """

    let project = try await MultiFileTestProject(
      files: [
        // PackageA
        "PackageA/Sources/MyLibrary/libA.swift": """
        public struct FancyLib {
          public init() {}
          public func sayHello() {}
        }
        """,

        "PackageA/Sources/MyExec/execA.swift": """
        import MyLibrary

        FancyLib().1️⃣sayHello()
        """,

        "PackageA/Package.swift": packageManifest,

        // PackageB
        "PackageB/Sources/MyLibrary/libB.swift": """
        public struct Lib {
          public init() {}
          public func foo() {}
        }
        """,
        "PackageB/Sources/MyExec/execB.swift": """
        import MyLibrary
        Lib().2️⃣foo()
        """,
        "PackageB/Package.swift": packageManifest,
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageB"))),
        ]
      },
      enableBackgroundIndexing: true
    )
    try await project.testClient.send(SynchronizeRequest(index: true))

    let (bUri, bPositions) = try project.openDocument("execB.swift")

    let completions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["2️⃣"])
    )

    XCTAssertEqual(
      completions.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "foo()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "foo()",
          insertText: "foo()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(bPositions["2️⃣"]), newText: "foo()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Lib",
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(bPositions["2️⃣"]), newText: "self")
          )
        ),
      ]
    )

    let (aUri, aPositions) = try project.openDocument("execA.swift")

    let otherCompletions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(aUri), position: aPositions["1️⃣"])
    )

    XCTAssertEqual(
      otherCompletions.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "sayHello()",
          kind: .method,
          detail: "Void",
          documentation: nil,
          deprecated: false,
          filterText: "sayHello()",
          insertText: "sayHello()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(aPositions["1️⃣"]), newText: "sayHello()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: LanguageServerProtocol.CompletionItemKind(rawValue: 14),
          detail: "FancyLib",
          documentation: nil,
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(aPositions["1️⃣"]), newText: "self")
          )
        ),
      ]
    )
  }

  func testOpenPackageManifestInMultiSwiftPMWorkspaceSetup() async throws {
    let project = try await MultiFileTestProject(
      files: [
        // PackageA
        "PackageA/Sources/MyLibrary/libA.swift": "",
        "PackageA/Package.swift": SwiftPMTestProject.defaultPackageManifest,

        // PackageB
        "PackageB/Sources/MyLibrary/libB.swift": "",
        "PackageB/Package.swift": SwiftPMTestProject.defaultPackageManifest,
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir)),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageB"))),
        ]
      }
    )

    let bPackageManifestUri = DocumentURI(
      project.scratchDirectory.appending(components: "PackageB", "Package.swift")
    )

    project.testClient.openDocument(SwiftPMTestProject.defaultPackageManifest, uri: bPackageManifestUri)

    // Ensure that we get proper build settings for Package.swift and no error about `No such module: PackageDescription`
    let diags = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(bPackageManifestUri))
    )
    XCTAssertEqual(diags.fullReport?.items, [])
  }

  func testCorrectWorkspaceForPackageSwiftInMultiSwiftPMWorkspaceSetup() async throws {
    let project = try await MultiFileTestProject(
      files: [
        // PackageA
        "PackageA/Sources/MyLibrary/libA.swift": "",
        "PackageA/Package.swift": SwiftPMTestProject.defaultPackageManifest,

        // PackageB
        "PackageB/Sources/MyLibrary/libB.swift": "",
        "PackageB/Package.swift": SwiftPMTestProject.defaultPackageManifest,
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir)),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageB"))),
        ]
      }
    )

    let pkgA = DocumentURI(
      project.scratchDirectory
        .appending(components: "PackageA", "Package.swift")
    )

    let pkgB = DocumentURI(
      project.scratchDirectory
        .appending(components: "PackageB", "Package.swift")
    )

    assertEqual(
      await project.testClient.server.workspaceForDocument(uri: pkgA)?.rootUri,
      DocumentURI(project.scratchDirectory.appending(component: "PackageA"))
    )

    assertEqual(
      await project.testClient.server.workspaceForDocument(uri: pkgB)?.rootUri,
      DocumentURI(project.scratchDirectory.appending(component: "PackageB"))
    )
  }

  func testSwiftPMPackageInSubfolder() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let packageManifest = """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLibrary",
        targets: [
          .target(name: "MyLibrary"),
          .executableTarget(name: "MyExec", dependencies: ["MyLibrary"])
        ]
      )
      """

    let project = try await MultiFileTestProject(
      files: [
        // PackageA
        "PackageA/Sources/MyLibrary/libA.swift": """
        public struct FancyLib {
          public init() {}
          public func sayHello() {}
        }
        """,

        "PackageA/Sources/MyExec/execA.swift": """
        import MyLibrary

        FancyLib().1️⃣sayHello()
        """,

        "PackageA/Package.swift": packageManifest,
      ],
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("execA.swift")

    try await project.testClient.send(SynchronizeRequest(index: true))

    let otherCompletions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    XCTAssertEqual(
      otherCompletions.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "sayHello()",
          kind: .method,
          detail: "Void",
          documentation: nil,
          deprecated: false,
          filterText: "sayHello()",
          insertText: "sayHello()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(positions["1️⃣"]), newText: "sayHello()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: LanguageServerProtocol.CompletionItemKind(rawValue: 14),
          detail: "FancyLib",
          documentation: nil,
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(positions["1️⃣"]), newText: "self")
          )
        ),
      ]
    )
  }

  func testNestedSwiftPMWorkspacesWithoutDedicatedWorkspaceFolder() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    // The package manifest is the same for both packages we open.
    let packageManifest = """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLibrary",
        targets: [
          .target(name: "MyLibrary"),
          .executableTarget(name: "MyExec", dependencies: ["MyLibrary"])
        ]
      )
      """

    let project = try await MultiFileTestProject(
      files: [
        // PackageA
        "PackageA/Sources/MyLibrary/libA.swift": """
        public struct FancyLib {
          public init() {}
          public func sayHello() {}
        }
        """,

        "PackageA/Sources/MyExec/execA.swift": """
        import MyLibrary

        FancyLib().1️⃣sayHello()
        """,

        "PackageA/Package.swift": packageManifest,

        // PackageB
        "Sources/MyLibrary/libB.swift": """
        public struct Lib {
          public init() {}
          public func foo() {}
        }
        """,
        "Sources/MyExec/execB.swift": """
        import MyLibrary
        Lib().2️⃣foo()
        """,
        "Package.swift": packageManifest,
      ],
      enableBackgroundIndexing: true
    )

    try await project.testClient.send(SynchronizeRequest(index: true))

    let (bUri, bPositions) = try project.openDocument("execB.swift")

    let completions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(bUri), position: bPositions["2️⃣"])
    )

    XCTAssertEqual(
      completions.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "foo()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "foo()",
          insertText: "foo()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(bPositions["2️⃣"]), newText: "foo()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Lib",
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(bPositions["2️⃣"]), newText: "self")
          )
        ),
      ]
    )

    let (aUri, aPositions) = try project.openDocument("execA.swift")

    try await project.testClient.send(SynchronizeRequest(index: true))

    let otherCompletions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(aUri), position: aPositions["1️⃣"])
    )

    XCTAssertEqual(
      otherCompletions.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "sayHello()",
          kind: .method,
          detail: "Void",
          documentation: nil,
          deprecated: false,
          filterText: "sayHello()",
          insertText: "sayHello()",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(aPositions["1️⃣"]), newText: "sayHello()")
          )
        ),
        CompletionItem(
          label: "self",
          kind: LanguageServerProtocol.CompletionItemKind(rawValue: 14),
          detail: "FancyLib",
          documentation: nil,
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(
            TextEdit(range: Range(aPositions["1️⃣"]), newText: "self")
          )
        ),
      ]
    )
  }

  func testMultipleClangdWorkspaces() async throws {
    let project = try await MultiFileTestProject(
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
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "WorkspaceA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "WorkspaceB"))),
        ]
      },
      usePullDiagnostics: false
    )

    _ = try project.openDocument("test.m")

    let diags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 0)

    let (mainUri, positions) = try project.openDocument("main.cpp")

    let highlightRequest = DocumentHighlightRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["3️⃣"]
    )
    let highlightResponse = try await project.testClient.send(highlightRequest)
    XCTAssertEqual(
      highlightResponse,
      [
        DocumentHighlight(range: positions["1️⃣"]..<positions["2️⃣"], kind: .text),
        DocumentHighlight(range: positions["3️⃣"]..<positions["4️⃣"], kind: .text),
      ]
    )
  }

  func testRecomputeFileWorkspaceMembershipOnPackageSwiftChange() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "PackageA/Sources/MyLibrary/libA.swift": "",
        "PackageA/Package.swift": SwiftPMTestProject.defaultPackageManifest,

        "PackageB/Sources/MyLibrary/libB.swift": """
        public struct Lib {
          public func foo() {}
          public init() {}
        }
        """,
        "PackageB/Sources/MyExec/main.swift": """
        import MyLibrary

        Lib().1️⃣
        """,
        "PackageB/Package.swift": SwiftPMTestProject.defaultPackageManifest,
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageA", directoryHint: .isDirectory))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "PackageB", directoryHint: .isDirectory))),
        ]
      }
    )

    let (mainUri, _) = try project.openDocument("main.swift")

    // We open PackageA first. Thus, MyExec/main (which is a file in PackageB that hasn't been added to Package.swift
    // yet) will belong to PackageA by default (because it provides fallback build settings for it).
    assertEqual(
      await project.testClient.server.workspaceForDocument(uri: mainUri)?.rootUri,
      DocumentURI(project.scratchDirectory.appending(component: "PackageA", directoryHint: .isDirectory))
    )

    // Add the MyExec target to PackageB/Package.swift
    let newPackageManifest = """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLibrary",
        targets: [
          .target(name: "MyLibrary"),
          .executableTarget(name: "MyExec", dependencies: ["MyLibrary"])
        ]
      )
      """

    let packageBManifestPath = project.scratchDirectory
      .appending(components: "PackageB", "Package.swift")

    try await newPackageManifest.writeWithRetry(to: packageBManifestPath)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: DocumentURI(packageBManifestPath), type: .changed)
      ])
    )
    // Ensure that the DidChangeWatchedFilesNotification is handled before we continue.
    _ = try await project.testClient.send(SynchronizeRequest())

    // After updating PackageB/Package.swift, PackageB can provide proper build settings for MyExec/main.swift and
    // thus workspace membership should switch to PackageB.

    // Updating the build settings takes a few seconds. Send code completion requests every second until we receive correct results.
    let packageBRootUri = DocumentURI(
      project.scratchDirectory.appending(component: "PackageB", directoryHint: .isDirectory)
    )
    try await repeatUntilExpectedResult {
      await project.testClient.server.workspaceForDocument(uri: mainUri)?.rootUri == packageBRootUri
    }
  }

  func testMixedPackage() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await SwiftPMTestProject(
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
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "lib", dependencies: []),
            .target(name: "clib", dependencies: []),
          ]
        )
        """
    )

    let (swiftUri, swiftPositions) = try project.openDocument("lib.swift")
    let (cUri, cPositions) = try project.openDocument("clib.c")

    let cCompletions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(cUri), position: cPositions["1️⃣"])
    )
    XCTAssertGreaterThanOrEqual(cCompletions.items.count, 0)

    let swiftCompletions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(swiftUri), position: swiftPositions["2️⃣"])
    )
    XCTAssertGreaterThanOrEqual(swiftCompletions.items.count, 0)
  }

  func testChangeWorkspaceFolders() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await MultiFileTestProject(
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
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "fake")))
        ]
      }
    )

    let packageDir = try project.uri(for: "Package.swift").fileURL!.deletingLastPathComponent()

    try await SwiftPMTestProject.build(at: packageDir)

    let (otherPackageUri, positions) = try project.openDocument("otherPackage.swift")
    let testPosition = positions["1️⃣"]

    let preChangeWorkspaceResponse = try await project.testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(otherPackageUri),
        position: testPosition
      )
    )

    XCTAssertEqual(
      preChangeWorkspaceResponse.items,
      [],
      "Should not receive cross-module code completion results when opening an unrelated directory as workspace root"
    )

    project.testClient.send(
      DidChangeWorkspaceFoldersNotification(
        event: WorkspaceFoldersChangeEvent(added: [
          WorkspaceFolder(uri: DocumentURI(packageDir))
        ])
      )
    )

    try await project.testClient.send(SynchronizeRequest(index: true))

    let postChangeWorkspaceResponse = try await project.testClient.send(
      CompletionRequest(
        textDocument: TextDocumentIdentifier(otherPackageUri),
        position: testPosition
      )
    )

    XCTAssertEqual(
      postChangeWorkspaceResponse.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "helloWorld()",
          kind: .method,
          detail: "Void",
          documentation: nil,
          deprecated: false,
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
  func testIntegrationTest() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    // This test is doing the same as `test-sourcekit-lsp` in the `swift-integration-tests` repo.

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/clib/include/clib.h": """
        #ifndef CLIB_H
        #define CLIB_H

        void clib_func(void);
        void clib_other(void);

        #endif // CLIB_H
        """,
        "Sources/clib/clib.c": """
        #include "clib.h"

        void 1️⃣clib_func(void) {2️⃣}
        """,
        "Sources/exec/main.swift": """
        import lib
        import clib

        Lib().3️⃣foo()
        4️⃣clib_func()
        """,
        "Sources/lib/lib.swift": """
        public struct Lib {
          public func 5️⃣foo() {}
          public init() {}
        }
        """,
      ],
      manifest: """
        // swift-tools-version:5.5
        import PackageDescription

        let package = Package(
          name: "pkg",
          targets: [
            .target(name: "exec", dependencies: ["lib", "clib"]),
            .target(name: "lib", dependencies: []),
            .target(name: "clib", dependencies: []),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )
    let (mainUri, mainPositions) = try project.openDocument("main.swift")

    let fooDefinitionResponse = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(mainUri), position: mainPositions["3️⃣"])
    )
    XCTAssertEqual(
      fooDefinitionResponse,
      .locations([
        Location(uri: try project.uri(for: "lib.swift"), range: try Range(project.position(of: "5️⃣", in: "lib.swift")))
      ])
    )

    let clibFuncDefinitionResponse = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(mainUri), position: mainPositions["4️⃣"])
    )
    XCTAssertEqual(
      clibFuncDefinitionResponse,
      .locations([
        Location(uri: try project.uri(for: "clib.c"), range: try Range(project.position(of: "1️⃣", in: "clib.c")))
      ])
    )

    let swiftCompletionResponse = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(mainUri), position: mainPositions["3️⃣"])
    )
    XCTAssertEqual(
      swiftCompletionResponse.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "foo()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "foo()",
          insertText: "foo()",
          insertTextFormat: .plain,
          textEdit: .textEdit(TextEdit(range: Range(mainPositions["3️⃣"]), newText: "foo()"))
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Lib",
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(TextEdit(range: Range(mainPositions["3️⃣"]), newText: "self"))
        ),
      ]
    )

    let (clibcUri, clibcPositions) = try project.openDocument("clib.c")

    let cCompletionResponse = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(clibcUri), position: clibcPositions["2️⃣"])
    )
    // rdar://73762053: This should also suggest clib_other
    XCTAssert(cCompletionResponse.items.contains(where: { $0.insertText == "clib_func" }))
  }

  func testWorkspaceOptions() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "/.sourcekit-lsp/config.json": """
        {
          "swiftPM": {
            "swiftCompilerFlags": ["-D", "TEST"]
          }
        }
        """,
        "Test.swift": """
        func test() {
        #if TEST
          let x: String = 1
        #endif
        }
        """,
      ]
    )

    let (uri, _) = try project.openDocument("Test.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'String'"]
    )
  }

  func testOptionsInInitializeRequest() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        func test() {
        #if TEST
          let x: String = 1
        #endif
        }
        """
      ],
      initializationOptions: SourceKitLSPOptions(
        swiftPM: SourceKitLSPOptions.SwiftPMOptions(swiftCompilerFlags: ["-D", "TEST"])
      ).asLSPAny
    )

    let (uri, _) = try project.openDocument("Test.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'String'"]
    )
  }

  func testWorkspaceOptionsOverrideGlobalOptions() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "/.sourcekit-lsp/config.json": """
        {
          "swiftPM": {
            "swiftCompilerFlags": ["-D", "TEST"]
          }
        }
        """,
        "Test.swift": """
        func test() {
        #if TEST
          let x: String = 1
        #endif
        #if OTHER
          let x: String = 1.0
        #endif
        }
        """,
      ],
      initializationOptions: SourceKitLSPOptions(
        swiftPM: SourceKitLSPOptions.SwiftPMOptions(swiftCompilerFlags: ["-D", "OTHER"])
      ).asLSPAny
    )

    let (uri, _) = try project.openDocument("Test.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'String'"]
    )
  }

  func testWorkspaceOptionsOverrideBuildServer() async throws {
    let project = try await MultiFileTestProject(files: [
      ".sourcekit-lsp/config.json": """
      {
        "defaultWorkspaceType": "compilationDatabase"
      }
      """,
      "src/Foo.swift": """
      #if HAVE_SETTINGS
      #error("Have settings")
      #endif
      """,
      "Sources/MyLib/Bar.swift": "",
      "build/compile_commands.json": """
      [
        {
          "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
          "arguments": [
            "swiftc",
            "$TEST_DIR_BACKSLASH_ESCAPED/src/Foo.swift",
            \(defaultSDKArgs)
            "-DHAVE_SETTINGS"
          ],
          "file": "src/Foo.swift",
          "output": "$TEST_DIR_BACKSLASH_ESCAPED/build/Foo.swift.o"
        }
      ]
      """,
      "Package.swift": """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLib",
        targets: [
          .target(name: "MyLib"),
        ]
      )
      """,
    ])
    let (uri, _) = try project.openDocument("Foo.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Have settings"]
    )
  }

  func testImplicitWorkspaceOptionsOverrideBuildServer() async throws {
    let project = try await MultiFileTestProject(files: [
      "projA/.sourcekit-lsp/config.json": """
      {
        "defaultWorkspaceType": "compilationDatabase"
      }
      """,
      "projA/src/Foo.swift": """
      #if HAVE_SETTINGS
      #error("Have settings")
      #endif
      """,
      "projA/Sources/MyLib/Bar.swift": "",
      "projA/build/compile_commands.json": """
      [
        {
          "directory": "$TEST_DIR_BACKSLASH_ESCAPED/projA",
          "arguments": [
            "swiftc",
            "$TEST_DIR_BACKSLASH_ESCAPED/projA/src/Foo.swift",
            \(defaultSDKArgs)
            "-DHAVE_SETTINGS"
          ],
          "file": "src/Foo.swift",
          "output": "$TEST_DIR_BACKSLASH_ESCAPED/projA/build/Foo.swift.o"
        }
      ]
      """,
      "projA/Package.swift": """
      // swift-tools-version: 5.7

      import PackageDescription

      let package = Package(
        name: "MyLib",
        targets: [
          .target(name: "MyLib"),
        ]
      )
      """,
    ])
    let (uri, _) = try project.openDocument("Foo.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Have settings"]
    )
  }

  func testWorkspaceOptionsCanAddSearchPaths() async throws {
    let project = try await MultiFileTestProject(files: [
      ".sourcekit-lsp/config.json": """
      {
        "compilationDatabase": {
          "searchPaths": ["otherbuild"]
        }
      }
      """,
      "src/Foo.swift": """
      #if HAVE_SETTINGS
      #error("Have settings")
      #endif
      """,
      "otherbuild/compile_commands.json": """
      [
        {
          "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
          "arguments": [
            "swiftc",
            "$TEST_DIR_BACKSLASH_ESCAPED/src/Foo.swift",
            \(defaultSDKArgs)
            "-DHAVE_SETTINGS"
          ],
          "file": "src/Foo.swift",
          "output": "$TEST_DIR_BACKSLASH_ESCAPED/otherbuild/Foo.swift.o"
        }
      ]
      """,
    ])
    let (uri, _) = try project.openDocument("Foo.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Have settings"]
    )
  }

  func testUnknownFileInProjectRootUsesWorkspaceAtRoot() async throws {
    let project = try await MultiFileTestProject(files: [
      "build/test.h": "",
      "build/compile_commands.json": "[]",
    ])

    let uri = try project.uri(for: "test.h")
    assertEqual(
      await project.testClient.server.workspaceForDocument(uri: uri)?.rootUri?.fileURL,
      project.scratchDirectory
    )
  }

  func testDidChangeActiveEditorDocument() async throws {
    let didChangeBaseLib = AtomicBool(initialValue: false)
    let didPrepareLibBAfterChangingBaseLib = self.expectation(description: "Did prepare LibB after changing base lib")
    let project = try await SwiftPMTestProject(
      files: [
        "BaseLib/BaseLib.swift": "",
        "LibA/LibA.swift": "",
        "LibB/LibB.swift": "",
      ],
      manifest: """
        let package = Package(
          name: "MyLib",
          targets: [
            .target(name: "BaseLib"),
            .target(name: "LibA", dependencies: ["BaseLib"]),
            .target(name: "LibB", dependencies: ["BaseLib"]),
          ]
        )
        """,
      capabilities: ClientCapabilities(experimental: [
        DidChangeActiveDocumentNotification.method: .dictionary(["supported": .bool(true)])
      ]),
      hooks: Hooks(
        indexHooks: IndexHooks(preparationTaskDidStart: { task in
          guard didChangeBaseLib.value else {
            return
          }
          do {
            XCTAssert(
              task.targetsToPrepare.contains(try BuildTargetIdentifier(target: "LibB", destination: .target)),
              "Prepared unexpected targets: \(task.targetsToPrepare)"
            )
            try await repeatUntilExpectedResult {
              Task.currentPriority > .low
            }
            didPrepareLibBAfterChangingBaseLib.fulfill()
          } catch {
            XCTFail("Received unexpected error: \(error)")
          }
        })
      ),
      enableBackgroundIndexing: true
    )

    _ = try project.openDocument("LibA.swift")
    let (libBUri, _) = try project.openDocument("LibB.swift")
    let baseLibUri = try XCTUnwrap(project.uri(for: "BaseLib.swift"))

    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: baseLibUri, type: .changed)]))
    // Ensure that we handle the `DidChangeWatchedFilesNotification`.
    try await project.testClient.send(SynchronizeRequest())
    didChangeBaseLib.value = true

    project.testClient.send(
      DidChangeActiveDocumentNotification(textDocument: TextDocumentIdentifier(libBUri))
    )
    try await fulfillmentOfOrThrow(didPrepareLibBAfterChangingBaseLib)

    withExtendedLifetime(project) {}
  }

  func testSourceKitOptions() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": ""
      ],
      options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest])
    )
    let optionsOptional = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(unwrap(project.uri(for: "Test.swift"))),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    let options = try XCTUnwrap(optionsOptional)
    assertContains(options.compilerArguments, "-module-name")
    XCTAssertEqual(options.kind, .normal)
    XCTAssertNil(options.didPrepareTarget)
  }

  func testSourceKitOptionsAllowingFallback() async throws {
    let hooks = Hooks(
      buildServerHooks: BuildServerHooks(
        swiftPMTestHooks: SwiftPMTestHooks(
          reloadPackageDidStart: {
            // Essentially make sure that the package never loads, so we are forced to return fallback arguments.
            try? await Task.sleep(for: .seconds(defaultTimeout * 2))
          }
        )
      )
    )
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": ""
      ],
      options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest]),
      hooks: hooks,
      pollIndex: false
    )
    let optionsOptional = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(unwrap(project.uri(for: "Test.swift"))),
        prepareTarget: false,
        allowFallbackSettings: true
      )
    )
    let options = try XCTUnwrap(optionsOptional)
    // Fallback arguments can't know the module name
    XCTAssert(!options.compilerArguments.contains("-module-name"))
    XCTAssertEqual(options.kind, .fallback)
    XCTAssertNil(options.didPrepareTarget)
  }

  func testSourceKitOptionsTriggersPrepare() async throws {
    let didChangeBaseLib = AtomicBool(initialValue: false)
    let didPrepareAfterChangingBaseLib = self.expectation(description: "Did prepare after changing base lib")

    let project = try await SwiftPMTestProject(
      files: [
        "BaseLib/BaseLib.swift": "",
        "LibA/LibA.swift": "",
      ],
      manifest: """
        let package = Package(
          name: "MyLib",
          targets: [
            .target(name: "BaseLib"),
            .target(name: "LibA", dependencies: ["BaseLib"])
          ]
        )
        """,
      options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest]),
      hooks: Hooks(
        indexHooks: IndexHooks(
          preparationTaskDidStart: { _ in
            guard didChangeBaseLib.value else {
              return
            }
            didPrepareAfterChangingBaseLib.fulfill()
          }
        )
      ),
      enableBackgroundIndexing: true
    )

    let baseLibUri = try XCTUnwrap(project.uri(for: "BaseLib.swift"))
    let uri = try XCTUnwrap(project.uri(for: "LibA.swift"))

    let noPrepare = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    try XCTAssertEqual(XCTUnwrap(noPrepare).didPrepareTarget, nil)

    let prepareUpToDate = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        prepareTarget: true,
        allowFallbackSettings: false
      )
    )
    try XCTAssertEqual(XCTUnwrap(prepareUpToDate).didPrepareTarget, false)

    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: baseLibUri, type: .changed)]))
    // Ensure that we handle the `DidChangeWatchedFilesNotification`.
    try await project.testClient.send(SynchronizeRequest())
    didChangeBaseLib.value = true

    let triggerPrepare = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        prepareTarget: true,
        allowFallbackSettings: false
      )
    )
    try XCTAssertEqual(XCTUnwrap(triggerPrepare).didPrepareTarget, true)

    // Check that we did actually run a preparation
    try await fulfillmentOfOrThrow(didPrepareAfterChangingBaseLib)

    let prepareUpToDateAgain = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        prepareTarget: true,
        allowFallbackSettings: false
      )
    )
    try XCTAssertEqual(XCTUnwrap(prepareUpToDateAgain).didPrepareTarget, false)
  }

  func testBuildServerUsesStandardizedFileUrlsInsteadOfRealpath() async throws {
    try SkipUnless.platformIsDarwin("The realpath vs standardized path difference only exists on macOS")

    // Explicitly create a directory at /tmp (which is a standardized path but whose realpath is /private/tmp)
    let scratchDirectory = URL(fileURLWithPath: "/tmp")
      .appending(component: testScratchName())
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

    defer {
      if cleanScratchDirectories {
        try? FileManager.default.removeItem(at: scratchDirectory)
      }
    }

    _ = try MultiFileTestProject.writeFilesToDisk(
      files: [
        "test.h": "",
        "test.c": """
        #include "test.h"
        """,
        "compile_commands.json": """
        [
          {
            "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
            "arguments": [
              "clang",
              "$TEST_DIR_BACKSLASH_ESCAPED/test.c",
              "-DHAVE_SETTINGS",
              "-index-store-path",
              "$TEST_DIR_BACKSLASH_ESCAPED/index"
            ],
            "file": "test.c",
            "output": "$TEST_DIR_BACKSLASH_ESCAPED/build/test.o"
          }
        ]
        """,
      ],
      scratchDirectory: scratchDirectory
    )

    let clang = try unwrap(await ToolchainRegistry.forTesting.default?.clang)
    let clangOutput = try await withTimeout(defaultTimeoutDuration) {
      try await Process.checkNonZeroExit(
        arguments: [
          clang.filePath, "-index-store-path", scratchDirectory.appending(component: "index").filePath,
          scratchDirectory.appending(component: "test.c").filePath,
          "-fsyntax-only",
        ]
      )
    }
    logger.debug("Clang output:\n\(clangOutput)")

    let testClient = try await TestSourceKitLSPClient(
      options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest]),
      workspaceFolders: [WorkspaceFolder(uri: DocumentURI(scratchDirectory), name: nil)]
    )
    try await testClient.send(SynchronizeRequest(index: true))

    // Check that we can infer build settings for the header from its main file. indexstore-db stores this main file
    // path as `/private/tmp` while the build server only knows about it as `/tmp`.
    let options = try await testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(scratchDirectory.appending(component: "test.h")),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    assertContains(options.compilerArguments, "-DHAVE_SETTINGS")
  }

  func testOutputPaths() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "",
        "FileB.swift": "",
      ],
      options: .testDefault(experimentalFeatures: [.outputPathsRequest]),
      enableBackgroundIndexing: true
    )

    let outputPaths = try await project.testClient.send(
      OutputPathsRequest(
        target: BuildTargetIdentifier(target: "MyLibrary", destination: .target).uri,
        workspace: DocumentURI(project.scratchDirectory)
      )
    )
    XCTAssertEqual(outputPaths.outputPaths.map { $0.suffix(13) }.sorted(), ["FileA.swift.o", "FileB.swift.o"])
  }

  func testOrphanedClangLanguageServiceShutdown() async throws {
    // test that when we remove a workspace, the ClangLanguageService for that workspace is shut down.
    // verify this by checking that clangd receives a ShutdownRequest.

    let clangdReceivedShutdown = self.expectation(description: "clangd received shutdown request")
    clangdReceivedShutdown.assertForOverFulfill = false

    let project = try await MultiFileTestProject(
      files: [
        "WorkspaceA/compile_flags.txt": "",
        "WorkspaceA/dummy.c": "",
        "WorkspaceB/main.c": """
        int main() { return 0; }
        """,
        "WorkspaceB/compile_flags.txt": "",
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "WorkspaceA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "WorkspaceB"))),
        ]
      },
      hooks: Hooks(preForwardRequestToClangd: { request in
        if request is ShutdownRequest {
          clangdReceivedShutdown.fulfill()
        }
      }),
      usePullDiagnostics: false
    )

    // open a .c file in WorkspaceB to launch clangd
    let (mainUri, _) = try project.openDocument("main.c")

    // send a request to ensure clangd is up and running
    _ = try await project.testClient.send(
      DocumentSymbolRequest(textDocument: TextDocumentIdentifier(mainUri))
    )

    // get the language service for WorkspaceB before closing
    let clangdServerBeforeClose = try await project.testClient.server.primaryLanguageService(
      for: mainUri,
      .c,
      in: unwrap(project.testClient.server.workspaceForDocument(uri: mainUri))
    )

    // close the document
    project.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(mainUri)))

    // remove WorkspaceB
    let workspaceBUri = DocumentURI(project.scratchDirectory.appending(component: "WorkspaceB"))
    project.testClient.send(
      DidChangeWorkspaceFoldersNotification(
        event: WorkspaceFoldersChangeEvent(removed: [WorkspaceFolder(uri: workspaceBUri)])
      )
    )
    _ = try await project.testClient.send(SynchronizeRequest())
    // wait for clangd to receive the shutdown request
    try await fulfillmentOfOrThrow(clangdReceivedShutdown)

    let workspaceAfterRemoval = await project.testClient.server.workspaceForDocument(uri: mainUri)
    XCTAssertNotEqual(
      try XCTUnwrap(workspaceAfterRemoval?.rootUri?.fileURL?.lastPathComponent),
      "WorkspaceB",
      "WorkspaceB should have been removed"
    )

    // verify the language service is orphaned - opening a file in WorkspaceA should get a different language service
    let (dummyUri, _) = try project.openDocument("dummy.c")
    _ = try await project.testClient.send(
      DocumentSymbolRequest(textDocument: TextDocumentIdentifier(dummyUri))
    )

    let clangdServerForWorkspaceA = try await project.testClient.server.primaryLanguageService(
      for: dummyUri,
      .c,
      in: unwrap(project.testClient.server.workspaceForDocument(uri: dummyUri))
    )


    XCTAssertFalse(clangdServerBeforeClose === clangdServerForWorkspaceA, "WorkspaceB's clangd should have been shut down and a new one created for WorkspaceA")
  }

  func testOrphanedSwiftLanguageServiceShutdownAndRelaunch() async throws {
  
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await MultiFileTestProject(
      files: [
        "WorkspaceA/Sources/LibA/LibA.swift": """
        public struct LibA {
          public func 1️⃣foo() {}
          public init() {}
        }
        """,
        "WorkspaceA/Package.swift": """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "LibA",
          targets: [.target(name: "LibA")]
        )
        """,
        "WorkspaceB/Sources/LibB/LibB.swift": """
        public struct LibB {
          public func bar() {}
          public init() {}
        }
        """,
        "WorkspaceB/Package.swift": """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "LibB",
          targets: [.target(name: "LibB")]
        )
        """,
      ],
      workspaces: { scratchDir in
        return [
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "WorkspaceA"))),
          WorkspaceFolder(uri: DocumentURI(scratchDir.appending(component: "WorkspaceB"))),
        ]
      }
    )


    let (libBUri, _) = try project.openDocument("LibB.swift")

  
    let initialHover = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(libBUri), position: Position(line: 1, utf16index: 14))
    )
    XCTAssertNotNil(initialHover, "Should get hover response for LibB.swift")

    // close the document in WorkspaceB
    project.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(libBUri)))

    // remove WorkspaceB
    let workspaceBUri = DocumentURI(project.scratchDirectory.appending(component: "WorkspaceB"))
    project.testClient.send(
      DidChangeWorkspaceFoldersNotification(
        event: WorkspaceFoldersChangeEvent(removed: [WorkspaceFolder(uri: workspaceBUri)])
      )
    )
    _ = try await project.testClient.send(SynchronizeRequest())

    //  orphaned service to be shut down in the background
    try await Task.sleep(for: .milliseconds(500))

    // open a file in WorkspaceA
    let (libAUri, positions) = try project.openDocument("LibA.swift")

    // verify that the language service in WorkspaceA still works correctly
    let hover = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(libAUri), position: positions["1️⃣"])
    )
    XCTAssertNotNil(hover, "Should still get hover response after removing WorkspaceB")
    assertContains(hover?.contents.markupContent?.value ?? "", "foo")
  }
}

private let defaultSDKArgs: String = {
  if let defaultSDKPath {
    let escapedPath = defaultSDKPath.replacing(#"\"#, with: #"\\"#)
    return """
      "-sdk", "\(escapedPath)",
      """
  }
  return ""
}()
