//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import XCTest

final class SwiftPMIntegrationTests: SourceKitLSPTestCase {
  func testSwiftPMIntegration() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": """
        struct Lib {
          func 1️⃣foo() {}
        }
        """,
        "Other.swift": """
        func test() {
          Lib().2️⃣foo()
        }
        """,
      ],
      enableBackgroundIndexing: true
    )

    let (otherUri, otherPositions) = try project.openDocument("Other.swift")
    let callPosition = otherPositions["2️⃣"]

    let refs = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(otherUri),
        position: callPosition,
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(refs),
      [
        Location(uri: otherUri, range: Range(callPosition)),
        Location(uri: try project.uri(for: "Lib.swift"), range: Range(try project.position(of: "1️⃣", in: "Lib.swift"))),
      ]
    )

    let completions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(otherUri), position: callPosition)
    )

    XCTAssertEqual(
      completions.items.clearingUnstableValues,
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
            TextEdit(range: Range(callPosition), newText: "foo()")
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
            TextEdit(range: Range(callPosition), newText: "self")
          )
        ),
      ]
    )
  }

  func testAddFile() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": """
        struct Lib {
          func foo() {
            1️⃣
          }
        }
        """
      ],
      enableBackgroundIndexing: true
    )

    // First, create a new in-memory file and verify that we get some basic functionality for it

    let newFileUrl = project.scratchDirectory
      .appending(components: "Sources", "MyLibrary", "Other.swift")
    let newFileUri = DocumentURI(newFileUrl)

    let newFileContents = """
      func baz(l: Lib)  {
        l.2️⃣foo()
        #warning("A manual warning")
      }
      """
    let newFilePositions = project.testClient.openDocument(newFileContents, uri: newFileUri)

    try await extractMarkers(newFileContents).textWithoutMarkers.writeWithRetry(to: newFileUrl)
    let completionsBeforeSave = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(newFileUri), position: newFilePositions["2️⃣"])
    )
    XCTAssertEqual(Set(completionsBeforeSave.items.map(\.label)), ["foo()", "self"])

    // We shouldn't get diagnostics for the new file yet since we still consider the build settings inferred from a
    // sibling file fallback settings.
    let diagnosticsBeforeSave = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(newFileUri))
    )
    XCTAssertEqual(diagnosticsBeforeSave.fullReport?.items, [])

    let (oldFileUri, oldFilePositions) = try project.openDocument("Lib.swift")
    // Check that we don't get completions for `baz` (defined in the new file) in the old file yet because the new file
    // is not part of the package manifest yet.
    let oldFileCompletionsBeforeSave = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(oldFileUri), position: oldFilePositions["1️⃣"])
    )
    XCTAssert(!oldFileCompletionsBeforeSave.items.contains(where: { $0.label == "baz(l: Lib)" }))

    // Now save the file to disk, which adds it to the package graph, which should enable more functionality.

    try await extractMarkers(newFileContents).textWithoutMarkers.writeWithRetry(to: newFileUrl)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: newFileUri, type: .created)
      ])
    )
    // Ensure that the DidChangeWatchedFilesNotification is handled before we continue.
    try await project.testClient.send(SynchronizeRequest(index: true))

    // Check that we still get completions in the new file, now get diagnostics in the new file and also see functions
    // from the new file in the old file
    let completionsAfterSave = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(newFileUri), position: newFilePositions["2️⃣"])
    )
    XCTAssertEqual(Set(completionsAfterSave.items.map(\.label)), ["foo()", "self"])
    let diagnosticsAfterSave = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(newFileUri))
    )
    XCTAssertEqual(diagnosticsAfterSave.fullReport?.items.map(\.message), ["A manual warning"])
    let oldFileCompletionsAfterSave = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(oldFileUri), position: oldFilePositions["1️⃣"])
    )
    assertContains(oldFileCompletionsAfterSave.items.map(\.label), "baz(l: Lib)")
  }

  func testNestedPackage() async throws {
    try await SkipUnless.sourcekitdSupportsPlugin()

    let project = try await MultiFileTestProject(files: [
      "pkg/Sources/lib/lib.swift": "",
      "pkg/Package.swift": """
      // swift-tools-version:4.2
      import PackageDescription
      let package = Package(name: "a", products: [], dependencies: [],
      targets: [.target(name: "lib", dependencies: [])])
      """,
      "nested/pkg/Sources/lib/a.swift.swift": """
      struct Foo {
        func bar() {}
      }
      """,
      "nested/pkg/Sources/lib/b.swift": """
      func test(foo: Foo) {
        foo.1️⃣
      }
      """,
      "nested/pkg/Package.swift": """
      // swift-tools-version:4.2
      import PackageDescription
      let package = Package(name: "a", products: [], dependencies: [],
      targets: [.target(name: "lib", dependencies: [])])
      """,
    ])

    let (uri, positions) = try project.openDocument("b.swift")

    try await project.testClient.send(SynchronizeRequest(index: true))

    let result = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )

    XCTAssertEqual(
      result.items.clearingUnstableValues,
      [
        CompletionItem(
          label: "bar()",
          kind: .method,
          detail: "Void",
          deprecated: false,
          filterText: "bar()",
          insertText: "bar()",
          insertTextFormat: .plain,
          textEdit: .textEdit(TextEdit(range: positions["1️⃣"]..<positions["1️⃣"], newText: "bar()"))
        ),
        CompletionItem(
          label: "self",
          kind: .keyword,
          detail: "Foo",
          deprecated: false,
          filterText: "self",
          insertText: "self",
          insertTextFormat: .plain,
          textEdit: .textEdit(TextEdit(range: positions["1️⃣"]..<positions["1️⃣"], newText: "self"))
        ),
      ]
    )
  }

  func testWasm() async throws {
    try await SkipUnless.canCompileForWasm()

    let project = try await SwiftPMTestProject(
      files: [
        "/.sourcekit-lsp/config.json": """
        {
          "swiftPM": {
            "triple": "wasm32-unknown-none-wasm"
          }
        }
        """,
        "Test.swift": """
        #if arch(wasm32)
        let _: UnsafeRawPointer = 1
        #endif
        """,
      ],
      manifest: """
        let package = Package(
          name: "WasmTest",
          targets: [
            .executableTarget(
              name: "wasmTest",
              cSettings: [.unsafeFlags(["-fdeclspec"])],
              swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .interoperabilityMode(.Cxx),
                .unsafeFlags(["-wmo", "-disable-cmo", "-Xfrontend", "-gnone"]),
              ],
              linkerSettings: [.unsafeFlags(["-Xclang-linker", "-nostdlib", "-Xlinker", "--no-entry"])]
            )
          ]
        )
        """
    )

    let (uri, _) = try project.openDocument("Test.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'UnsafeRawPointer'"]
    )
  }

  func testProvideSyntacticFunctionalityWhilePackageIsLoading() async throws {
    let receivedDocumentSymbolsReply = WrappedSemaphore(name: "Received document symbols reply")
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": ""
      ],
      hooks: Hooks(
        buildServerHooks: BuildServerHooks(
          swiftPMTestHooks: SwiftPMTestHooks(reloadPackageDidStart: {
            receivedDocumentSymbolsReply.waitOrXCTFail()
          })
        )
      ),
      pollIndex: false
    )
    let (uri, _) = try project.openDocument("Test.swift")
    _ = try await project.testClient.send(DocumentSymbolRequest(textDocument: TextDocumentIdentifier(uri)))
    receivedDocumentSymbolsReply.signal()
  }

  func testDiagnosticsGetRefreshedAfterPackageLoadingFinishes() async throws {
    let receivedInitialDiagnosticsReply = WrappedSemaphore(name: "Received initial diagnostics reply")
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        let x: String = 1
        """
      ],
      capabilities: ClientCapabilities(
        workspace: WorkspaceClientCapabilities(diagnostics: RefreshRegistrationCapability(refreshSupport: true))
      ),
      hooks: Hooks(
        buildServerHooks: BuildServerHooks(
          swiftPMTestHooks: SwiftPMTestHooks(reloadPackageDidStart: {
            receivedInitialDiagnosticsReply.waitOrXCTFail()
          })
        )
      ),
      pollIndex: false
    )
    let diagnosticRefreshRequestReceived = self.expectation(description: "DiagnosticsRefreshRequest received")
    project.testClient.handleSingleRequest { (request: DiagnosticsRefreshRequest) in
      diagnosticRefreshRequestReceived.fulfill()
      return VoidResponse()
    }

    let (uri, _) = try project.openDocument("Test.swift")
    let diagnosticsBeforePackageLoading = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(diagnosticsBeforePackageLoading.fullReport?.items, [])
    receivedInitialDiagnosticsReply.signal()
    try await Task.sleep(for: .seconds(1))

    try await fulfillmentOfOrThrow(diagnosticRefreshRequestReceived)
    let diagnosticsAfterPackageLoading = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      diagnosticsAfterPackageLoading.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'String'"]
    )
  }

  func testToolPluginWithBuild() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Plugins/plugin.swift": #"""
        import PackagePlugin
        @main struct CodeGeneratorPlugin: BuildToolPlugin {
          func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
            let genSourcesDir = context.pluginWorkDirectoryURL.appending(path: "GeneratedSources")
            guard let target = target as? SourceModuleTarget else { return [] }
            let codeGenerator = try context.tool(named: "CodeGenerator").url
            let generatedFile = genSourcesDir.appending(path: "\(target.name)-generated.swift")
            return [.buildCommand(
              displayName: "Generating code for \(target.name)",
              executable: codeGenerator,
              arguments: [
                generatedFile.path
              ],
              inputFiles: [],
              outputFiles: [generatedFile]
            )]
          }
        }
        """#,

        "Sources/CodeGenerator/CodeGenerator.swift": #"""
        import Foundation
        try "let generated = 1".write(to: URL(fileURLWithPath: CommandLine.arguments[1]), atomically: true, encoding: String.Encoding.utf8)
        """#,

        "Sources/TestLib/TestLib.swift": #"""
        func useGenerated() {
          _ = 1️⃣generated
        }
        """#,
      ],
      manifest: """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
          name: "PluginTest",
          targets: [
            .executableTarget(name: "CodeGenerator"),
            .target(
              name: "TestLib",
              plugins: [.plugin(name: "CodeGeneratorPlugin")]
            ),
            .plugin(
              name: "CodeGeneratorPlugin",
              capability: .buildTool(),
              dependencies: ["CodeGenerator"]
            ),
          ]
        )
        """,
      enableBackgroundIndexing: false
    )

    let (uri, positions) = try project.openDocument("TestLib.swift")
    let result = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    // We cannot run plugins when not using background indexing, so we expect no result here.
    XCTAssertNil(result)
  }

  func testToolPluginWithBackgroundIndexing() async throws {
    try await SkipUnless.canLoadPluginsBuiltByToolchain()

    let project = try await SwiftPMTestProject(
      files: [
        "Plugins/plugin.swift": #"""
        import Foundation
        import PackagePlugin
        @main struct CodeGeneratorPlugin: BuildToolPlugin {
          func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
            let genSourcesDir = context.pluginWorkDirectoryURL.appending(path: "GeneratedSources")
            guard let target = target as? SourceModuleTarget else { return [] }
            let codeGenerator = try context.tool(named: "CodeGenerator").url
            let generatedFile = genSourcesDir.appending(path: "\(target.name)-generated.swift")
            return [.buildCommand(
              displayName: "Generating code for \(target.name)",
              executable: codeGenerator,
              arguments: [
                generatedFile.path
              ],
              inputFiles: [
                URL(fileURLWithPath: "$TEST_DIR_BACKSLASH_ESCAPED/topDep.txt"),
                URL(fileURLWithPath: "$TEST_DIR_BACKSLASH_ESCAPED/Sources/TestLib/targetDep.txt")
              ],
              outputFiles: [generatedFile]
            )]
          }
        }
        """#,

        "Sources/CodeGenerator/CodeGenerator.swift": #"""
        import Foundation
        let topGenerated = try String(contentsOf: URL(fileURLWithPath: "$TEST_DIR_BACKSLASH_ESCAPED/topDep.txt"))
        let targetGenerated = try String(contentsOf: URL(fileURLWithPath: "$TEST_DIR_BACKSLASH_ESCAPED/Sources/TestLib/targetDep.txt"))
        try "\(topGenerated)\n\(targetGenerated)".write(
          to: URL(fileURLWithPath: CommandLine.arguments[1]),
          atomically: true,
          encoding: String.Encoding.utf8
        )
        """#,

        "Sources/TestLib/TestLib.swift": #"""
        func useGenerated() {
          _ = 1️⃣topGenerated
          _ = 2️⃣targetGenerated
        }
        """#,

        "/topDep.txt": "let topGenerated = 1",
        "Sources/TestLib/targetDep.txt": "let targetGenerated = 1",
      ],
      manifest: """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
          name: "PluginTest",
          targets: [
            .executableTarget(name: "CodeGenerator"),
            .target(
              name: "TestLib",
              plugins: [.plugin(name: "CodeGeneratorPlugin")]
            ),
            .plugin(
              name: "CodeGeneratorPlugin",
              capability: .buildTool(),
              dependencies: ["CodeGenerator"]
            ),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("TestLib.swift")

    // We should have run plugins and thus created generated.swift
    do {
      let topResult = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      let topLocation = try XCTUnwrap(topResult?.locations?.only)
      XCTAssertTrue(topLocation.uri.pseudoPath.hasSuffix("generated.swift"))
      XCTAssertEqual(topLocation.range.lowerBound, Position(line: 0, utf16index: 4))
      XCTAssertEqual(topLocation.range.upperBound, Position(line: 0, utf16index: 4))

      let targetResult = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
      )
      let targetLocation = try XCTUnwrap(targetResult?.locations?.only)
      XCTAssertTrue(targetLocation.uri.pseudoPath.hasSuffix("generated.swift"))
      XCTAssertEqual(targetLocation.range.lowerBound, Position(line: 1, utf16index: 4))
      XCTAssertEqual(targetLocation.range.upperBound, Position(line: 1, utf16index: 4))
    }

    // Make a change to the top level input file of the plugin command
    try await project.changeFileOnDisk(
      "topDep.txt",
      newMarkedContents: """
        // some change
        let topGenerated = 2
        """
    )
    try await project.testClient.send(SynchronizeRequest(index: true))

    // Expect that the position has been updated in the dependency
    try await repeatUntilExpectedResult {
      let result = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      let location = try XCTUnwrap(result?.locations?.only)
      return location.range.lowerBound == Position(line: 1, utf16index: 4)
    }

    // Make a change to the target level input file of the plugin command
    try await project.changeFileOnDisk(
      "targetDep.txt",
      newMarkedContents: """
        // some change
        let targetGenerated = 2
        """
    )
    try await project.testClient.send(SynchronizeRequest(index: true))

    // Expect that the position has been updated in the dependency
    try await repeatUntilExpectedResult {
      let result = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
      )
      let location = try XCTUnwrap(result?.locations?.only)
      return location.range.lowerBound == Position(line: 3, utf16index: 4)
    }
  }

  func testChangePackageManifestFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": """
        #if MY_FLAG
        #error("MY_FLAG set")
        #else
        #error("MY_FLAG not set")
        #endif
        """
      ],
      manifest: """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary")]
        )
        """
    )

    let (uri, _) = try project.openDocument("Lib.swift")
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items.map(\.message), ["MY_FLAG not set"])

    try await project.changeFileOnDisk(
      "Package.swift",
      newMarkedContents: """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary", swiftSettings: [.define("MY_FLAG")])]
        )
        """
    )
    try await repeatUntilExpectedResult {
      let diagnosticsAfterUpdate = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagnosticsAfterUpdate.fullReport?.items.map(\.message) == ["MY_FLAG set"]
    }
  }

  func testChangeVersionSpecificPackageManifestFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": """
        #if MY_FLAG
        #error("MY_FLAG set")
        #elseif MY_OTHER_FLAG
        #error("MY_OTHER_FLAG set")
        #else
        #error("no flag set")
        #endif
        """,
        "/Package@swift-6.1.swift": """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary", swiftSettings: [.define("MY_FLAG")])]
        )
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary")]
        )
        """
    )

    let (uri, _) = try project.openDocument("Lib.swift")
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items.map(\.message), ["MY_FLAG set"])

    try await project.changeFileOnDisk(
      "Package@swift-6.1.swift",
      newMarkedContents: """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary", swiftSettings: [.define("MY_OTHER_FLAG")])]
        )
        """
    )
    try await repeatUntilExpectedResult {
      let diagnosticsAfterUpdate = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagnosticsAfterUpdate.fullReport?.items.map(\.message) == ["MY_OTHER_FLAG set"]
    }
  }

  func testAddVersionSpecificPackageManifestFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Lib.swift": """
        #if MY_FLAG
        #error("MY_FLAG set")
        #else
        #error("MY_FLAG not set")
        #endif
        """
      ],
      manifest: """
        // swift-tools-version: 5.7
        import PackageDescription
        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary")]
        )
        """
    )

    let (uri, _) = try project.openDocument("Lib.swift")
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items.map(\.message), ["MY_FLAG not set"])

    let versionSpecificManifestUrl = project.scratchDirectory.appending(component: "Package@swift-6.1.swift")
    try await """
    // swift-tools-version: 6.1
    import PackageDescription
    let package = Package(
      name: "MyLibrary",
      targets: [.target(name: "MyLibrary", swiftSettings: [.define("MY_FLAG")])]
    )
    """.writeWithRetry(to: versionSpecificManifestUrl)

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: DocumentURI(versionSpecificManifestUrl), type: .created)
      ])
    )
    try await repeatUntilExpectedResult {
      let diagnosticsAfterUpdate = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagnosticsAfterUpdate.fullReport?.items.map(\.message) == ["MY_FLAG set"]
    }
  }

  func testClearPreparationStatusWhenPackageManifestIsModifiedAndPackageIsOpenedWithoutTrailingSlash() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyLibrary.swift": """
        #if MY_FLAG
        public func foo() -> String { "" }
        #else
        public func foo() -> Int { "" }
        #endif
        """,
        "MyExecutable/MyExecutable.swift": """
        import MyLibrary

        let 1️⃣x = foo()
        """,
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .executableTarget(name: "MyExecutable", dependencies: ["MyLibrary"])
          ]
        )
        """,
      workspaces: {
        [WorkspaceFolder(uri: DocumentURI(try URL(filePath: $0.filePath, directoryHint: .notDirectory)))]
      },
      enableBackgroundIndexing: true
    )
    let (uri, positions) = try project.openDocument("MyExecutable.swift")
    let preEditHoverResponse = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    assertContains(try XCTUnwrap(preEditHoverResponse?.contents.markupContent?.value), "let x: Int")

    try await project.changeFileOnDisk(
      "Package.swift",
      newMarkedContents: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary", swiftSettings: [.define("MY_FLAG")]),
            .executableTarget(name: "MyExecutable", dependencies: ["MyLibrary"])
          ]
        )
        """
    )

    try await repeatUntilExpectedResult {
      let postEditHoverResponse = try await project.testClient.send(
        HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return try XCTUnwrap(postEditHoverResponse?.contents.markupContent?.value).contains("let x: String")
    }
  }

  func testPackagePlugin() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": "",
        "Plugins/PrintMessage/Plugin.swift": """
        import PackagePlugin

        @main
        struct PrintMessagePlugin: CommandPlugin {
          func performCommand(context: PluginContext, arguments: [String]) throws {
            print("Message")
            let x: String = 1
          }
        }
        """,
      ],
      manifest: """
        import PackageDescription

        let package = Package(
          name: "PrintMessage",
          platforms: [.macOS(.v14)],
          products: [
            .plugin(
              name: "PrintMessage",
              targets: ["PrintMessage"]
            )
          ],
          targets: [
            .target(name: "MyLibrary"),
            .plugin(
              name: "PrintMessage",
              capability: .command(
                intent: .custom(
                  verb: "print-message",
                  description: "Prints message"
                )
              )
            )
          ]
        )
        """,
      // enableBackgroundIndexing: true
    )
    let (uri, _) = try! project.openDocument("Plugin.swift")
    let diags = try await project.testClient.send(DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      diags.fullReport?.items.map(\.message),
      ["Cannot convert value of type 'Int' to specified type 'String'"]
    )
  }
}
