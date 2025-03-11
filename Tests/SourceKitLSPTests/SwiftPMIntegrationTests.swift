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

import BuildSystemIntegration
import Foundation
import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import XCTest

final class SwiftPMIntegrationTests: XCTestCase {

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

    let newFileUrl = project.scratchDirectory
      .appendingPathComponent("Sources")
      .appendingPathComponent("MyLibrary")
      .appendingPathComponent("Other.swift")
    let newFileUri = DocumentURI(newFileUrl)

    let newFileContents = """
      func baz(l: Lib)  {
        l.2️⃣foo()
      }
      """
    try await extractMarkers(newFileContents).textWithoutMarkers.writeWithRetry(to: newFileUrl)

    // Check that we don't get cross-file code completion before we send a `DidChangeWatchedFilesNotification` to make
    // sure we didn't include the file in the initial retrieval of build settings.
    let (oldFileUri, oldFilePositions) = try project.openDocument("Lib.swift")
    let newFilePositions = project.testClient.openDocument(newFileContents, uri: newFileUri)

    let completionsBeforeDidChangeNotification = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(newFileUri), position: newFilePositions["2️⃣"])
    )
    XCTAssertEqual(completionsBeforeDidChangeNotification.items, [])

    // Send a `DidChangeWatchedFilesNotification` and verify that we now get cross-file code completion.
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: newFileUri, type: .created)
      ])
    )

    // Ensure that the DidChangeWatchedFilesNotification is handled before we continue.
    try await project.testClient.send(PollIndexRequest())

    let completions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(newFileUri), position: newFilePositions["2️⃣"])
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
            TextEdit(range: Range(newFilePositions["2️⃣"]), newText: "foo()")
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
            TextEdit(range: Range(newFilePositions["2️⃣"]), newText: "self")
          )
        ),
      ]
    )

    // Check that we get code completion for `baz` (defined in the new file) in the old file.
    // I.e. check that the existing file's build settings have been updated to include the new file.

    let oldFileCompletions = try await project.testClient.send(
      CompletionRequest(textDocument: TextDocumentIdentifier(oldFileUri), position: oldFilePositions["1️⃣"])
    )
    XCTAssert(oldFileCompletions.items.contains(where: { $0.label == "baz(l: Lib)" }))
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

    try await project.testClient.send(PollIndexRequest())

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
        buildSystemHooks: BuildSystemHooks(
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
      hooks: Hooks(
        buildSystemHooks: BuildSystemHooks(
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

    try await fulfillmentOfOrThrow([diagnosticRefreshRequestReceived])
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
    try await project.testClient.send(PollIndexRequest())

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
    try await project.testClient.send(PollIndexRequest())

    // Expect that the position has been updated in the dependency
    try await repeatUntilExpectedResult {
      let result = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
      )
      let location = try XCTUnwrap(result?.locations?.only)
      return location.range.lowerBound == Position(line: 3, utf16index: 4)
    }
  }
}
