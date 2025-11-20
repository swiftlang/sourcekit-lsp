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
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SwiftExtensions
import TSCBasic
import TSCExtensions
import ToolchainRegistry
import XCTest

final class CompilationDatabaseTests: SourceKitLSPTestCase {
  func testModifyCompilationDatabase() async throws {
    let project = try await MultiFileTestProject(files: [
      "main.cpp": """
      #if FOO
      void 1️⃣foo2️⃣() {}
      #else
      void 3️⃣foo4️⃣() {}
      #endif

      int main() {
        5️⃣foo6️⃣();
      }
      """,
      "compile_flags.txt": """
      -DFOO
      """,
    ])

    let (mainUri, positions) = try project.openDocument("main.cpp")

    // Verify that we get the expected result from a hover response before modifying the compile commands.

    let highlightRequest = DocumentHighlightRequest(
      textDocument: TextDocumentIdentifier(mainUri),
      position: positions["5️⃣"]
    )
    let preChangeHighlightResponse = try await project.testClient.send(highlightRequest)
    XCTAssertEqual(
      preChangeHighlightResponse,
      [
        DocumentHighlight(range: positions["1️⃣"]..<positions["2️⃣"], kind: .text),
        DocumentHighlight(range: positions["5️⃣"]..<positions["6️⃣"], kind: .text),
      ]
    )

    // Remove -DFOO from the compile commands.

    try await project.changeFileOnDisk(FixedCompilationDatabaseBuildServer.dbName, newMarkedContents: "")

    // DocumentHighlight should now point to the definition in the `#else` block.

    let expectedPostEditHighlight = [
      DocumentHighlight(range: positions["3️⃣"]..<positions["4️⃣"], kind: .text),
      DocumentHighlight(range: positions["5️⃣"]..<positions["6️⃣"], kind: .text),
    ]

    // Updating the build settings takes a few seconds.
    // Send highlight requests every second until we receive correct results.
    try await repeatUntilExpectedResult {
      let postChangeHighlightResponse = try await project.testClient.send(highlightRequest)
      return postChangeHighlightResponse == expectedPostEditHighlight
    }
  }

  func testJSONCompilationDatabaseWithDifferentToolchainsForSwift() async throws {
    let dummyToolchain = Toolchain(
      identifier: "dummy",
      displayName: "dummy",
      path: URL(fileURLWithPath: "/dummy"),
      clang: nil,
      swift: URL(fileURLWithPath: "/dummy/usr/bin/swift"),
      swiftc: URL(fileURLWithPath: "/dummy/usr/bin/swiftc"),
      swiftFormat: nil,
      clangd: nil,
      sourcekitd: URL(fileURLWithPath: "/dummy/usr/lib/sourcekitd.framework/sourcekitd"),
      libIndexStore: nil
    )
    let toolchainRegistry = ToolchainRegistry(toolchains: [
      try await unwrap(ToolchainRegistry.forTesting.default), dummyToolchain,
    ])

    let project = try await MultiFileTestProject(
      files: [
        "testFromDefaultToolchain.swift": """
        #warning("Test warning")
        """,
        "testFromDummyToolchain.swift": """
        #warning("Test warning")
        """,
        "compile_commands.json": """
        [
          {
            "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
            "arguments": [
              "swiftc",
              "$TEST_DIR_BACKSLASH_ESCAPED/testFromDefaultToolchain.swift",
              \(defaultSDKArgs)
            ],
            "file": "testFromDefaultToolchain.swift",
            "output": "$TEST_DIR_BACKSLASH_ESCAPED/testFromDefaultToolchain.swift.o"
          },
          {
            "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
            "arguments": [
              "/dummy/usr/bin/swiftc",
              "$TEST_DIR_BACKSLASH_ESCAPED/testFromDummyToolchain.swift",
              \(defaultSDKArgs)
            ],
            "file": "testFromDummyToolchain.swift",
            "output": "$TEST_DIR_BACKSLASH_ESCAPED/testFromDummyToolchain.swift.o"
          }
        ]
        """,
      ],
      toolchainRegistry: toolchainRegistry
    )

    // We should be able to provide semantic functionality for `testFromDefaultToolchain` because we open it using the
    // default toolchain.

    let (forDefaultToolchainUri, _) = try project.openDocument("testFromDefaultToolchain.swift")
    let diagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(forDefaultToolchainUri))
    )
    XCTAssertEqual(
      diagnostics.fullReport?.items.map(\.message),
      ["Test warning"]
    )

    // But for `testFromDummyToolchain.swift`, we can't launch sourcekitd (because it doesn't exist, we just provided a
    // dummy), so we should receive an error. The exact error here is not super relevant, the important part is that we
    // apparently tried to launch a different sourcekitd.
    let (forDummyToolchainUri, _) = try project.openDocument("testFromDummyToolchain.swift")
    await assertThrowsError(
      try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(forDummyToolchainUri))
      )
    ) { error in
      guard let error = error as? ResponseError else {
        XCTFail("Expected ResponseError, got \(error)")
        return
      }
      assertContains(error.message, "No language service")
    }
  }

  func testJSONCompilationDatabaseWithDifferentToolchainsForClang() async throws {
    let dummyToolchain = Toolchain(
      identifier: "dummy",
      displayName: "dummy",
      path: URL(fileURLWithPath: "/dummy"),
      clang: URL(fileURLWithPath: "/dummy/usr/bin/clang"),
      swift: nil,
      swiftc: nil,
      swiftFormat: nil,
      clangd: URL(fileURLWithPath: "/dummy/usr/bin/clangd"),
      sourcekitd: nil,
      libIndexStore: nil
    )
    let toolchainRegistry = ToolchainRegistry(toolchains: [
      try await unwrap(ToolchainRegistry.forTesting.default), dummyToolchain,
    ])

    let project = try await MultiFileTestProject(
      files: [
        "testFromDefaultToolchain.c": """
        void 1️⃣main() {}
        """,
        "testFromDummyToolchain.c": """
        void 2️⃣main() {}
        """,
        "compile_commands.json": """
        [
          {
            "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
            "arguments": [
              "clang",
              "$TEST_DIR_BACKSLASH_ESCAPED/testFromDefaultToolchain.c"
            ],
            "file": "testFromDefaultToolchain.c",
            "output": "$TEST_DIR_BACKSLASH_ESCAPED/testFromDefaultToolchain.o"
          },
          {
            "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
            "arguments": [
              "/dummy/usr/bin/clang",
              "$TEST_DIR_BACKSLASH_ESCAPED/testFromDummyToolchain.c"
            ],
            "file": "testFromDummyToolchain.c",
            "output": "$TEST_DIR_BACKSLASH_ESCAPED/testFromDummyToolchain.o"
          }
        ]
        """,
      ],
      toolchainRegistry: toolchainRegistry
    )

    // We should be able to provide semantic functionality for `testFromDefaultToolchain` because we open it using the
    // default toolchain.

    let (forDefaultToolchainUri, forDefaultToolchainPositions) = try project.openDocument("testFromDefaultToolchain.c")
    let hover = try await project.testClient.send(
      HoverRequest(
        textDocument: TextDocumentIdentifier(forDefaultToolchainUri),
        position: forDefaultToolchainPositions["1️⃣"]
      )
    )
    let hoverContent = try XCTUnwrap(hover?.contents.markupContent?.value)
    assertContains(hoverContent, "void main()")

    // But for `testFromDummyToolchain.swift`, we can't launch sourcekitd (because it doesn't exist, we just provided a
    // dummy), so we should receive an error. The exact error here is not super relevant, the important part is that we
    // apparently tried to launch a different sourcekitd.
    let (forDummyToolchainUri, forDummyToolchainPositions) = try project.openDocument("testFromDummyToolchain.c")
    await assertThrowsError(
      try await project.testClient.send(
        HoverRequest(
          textDocument: TextDocumentIdentifier(forDummyToolchainUri),
          position: forDummyToolchainPositions["2️⃣"]
        )
      )
    ) { error in
      guard let error = error as? ResponseError else {
        XCTFail("Expected ResponseError, got \(error)")
        return
      }
      assertContains(error.message, "No language service")
    }
  }

  func testLookThroughSwiftly() async throws {
    try await withTestScratchDir { scratchDirectory in
      let defaultToolchain = try await unwrap(ToolchainRegistry.forTesting.default)

      // We create a toolchain registry with the default toolchain, which is able to provide semantic functionality and
      // a dummy toolchain that can't provide semantic functionality.
      let fakeToolchainURL = scratchDirectory.appending(components: "fakeToolchain")
      let fakeToolchain = Toolchain(
        identifier: "fake",
        displayName: "fake",
        path: fakeToolchainURL,
        clang: nil,
        swift: fakeToolchainURL.appending(components: "usr", "bin", "swift"),
        swiftc: fakeToolchainURL.appending(components: "usr", "bin", "swiftc"),
        swiftFormat: nil,
        clangd: nil,
        sourcekitd: fakeToolchainURL.appending(components: "usr", "lib", "sourcekitd.framework", "sourcekitd"),
        libIndexStore: nil
      )
      let toolchainRegistry = ToolchainRegistry(toolchains: [
        defaultToolchain, fakeToolchain,
      ])

      // We need to create a file for the swift executable because `SwiftToolchainResolver` checks for its presence.
      try FileManager.default.createDirectory(
        at: XCTUnwrap(fakeToolchain.swift).deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try await "".writeWithRetry(to: XCTUnwrap(fakeToolchain.swift))

      // Create a dummy swiftly executable that picks the default toolchain for all file unless `fakeToolchain` is in
      // the source file's path.
      let dummySwiftlyExecutableUrl = scratchDirectory.appending(component: "swiftly")
      let dummySwiftExecutableUrl = scratchDirectory.appending(component: "swift")
      try FileManager.default.createSymbolicLink(
        at: dummySwiftExecutableUrl,
        withDestinationURL: dummySwiftlyExecutableUrl
      )
      try await createBinary(
        """
        import Foundation

        if FileManager.default.currentDirectoryPath.contains("fakeToolchain") {
          print(#"\(fakeToolchain.path.filePath)"#)
        } else {
          print(#"\(defaultToolchain.path.filePath)"#)
        }
        """,
        at: dummySwiftlyExecutableUrl
      )

      // Now create a project in which we have one file in a `realToolchain` directory for which our fake swiftly will
      // pick the default toolchain and one in `fakeToolchain` for which swiftly will pick the fake toolchain. We should
      // be able to get semantic functionality for the file in `realToolchain` but not for `fakeToolchain` because
      // sourcekitd can't be launched for that toolchain (since it doesn't exist).
      let dummySwiftExecutablePathForJSON = try dummySwiftExecutableUrl.filePath.replacing(#"\"#, with: #"\\"#)

      let project = try await MultiFileTestProject(
        files: [
          "realToolchain/realToolchain.swift": """
          #warning("Test warning")
          """,
          "fakeToolchain/fakeToolchain.swift": """
          #warning("Test warning")
          """,
          "compile_commands.json": """
          [
            {
              "directory": "$TEST_DIR_BACKSLASH_ESCAPED/realToolchain",
              "arguments": [
                "\(dummySwiftExecutablePathForJSON)",
                "$TEST_DIR_BACKSLASH_ESCAPED/realToolchain/realToolchain.swift",
                \(defaultSDKArgs)
              ],
              "file": "realToolchain.swift",
              "output": "$TEST_DIR_BACKSLASH_ESCAPED/realToolchain/test.swift.o"
            },
            {
              "directory": "$TEST_DIR_BACKSLASH_ESCAPED/fakeToolchain",
              "arguments": [
                "\(dummySwiftExecutablePathForJSON)",
                "$TEST_DIR_BACKSLASH_ESCAPED/fakeToolchain/fakeToolchain.swift",
                \(defaultSDKArgs)
              ],
              "file": "fakeToolchain.swift",
              "output": "$TEST_DIR_BACKSLASH_ESCAPED/fakeToolchain/test.swift.o"
            }
          ]
          """,
        ],
        toolchainRegistry: toolchainRegistry
      )

      let (forRealToolchainUri, _) = try project.openDocument("realToolchain.swift")
      let diagnostics = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(forRealToolchainUri))
      )
      XCTAssertEqual(diagnostics.fullReport?.items.map(\.message), ["Test warning"])

      let (forDummyToolchainUri, _) = try project.openDocument("fakeToolchain.swift")
      await assertThrowsError(
        try await project.testClient.send(
          DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(forDummyToolchainUri))
        )
      ) { error in
        guard let error = error as? ResponseError else {
          XCTFail("Expected ResponseError, got \(error)")
          return
        }
        // The actual error message here doesn't matter too much, we just need to check that we don't get diagnostics.
        assertContains(error.message, "No language service")
      }
    }
  }

  func testCompilationDatabaseWithRelativeDirectory() async throws {
    let project = try await MultiFileTestProject(files: [
      "projectA/headers/header.h": """
      int 1️⃣foo2️⃣() {}
      """,
      "projectA/main.cpp": """
      #include "header.h"

      int main() {
        3️⃣foo();
      }
      """,
      "compile_commands.json": """
      [
        {
          "directory": "projectA",
          "arguments": [
            "clang",
            "-I", "headers"
          ],
          "file": "main.cpp"
        }
      ]
      """,
    ])

    let (mainUri, positions) = try project.openDocument("main.cpp")

    let definition = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(mainUri), position: positions["3️⃣"])
    )
    XCTAssertEqual(definition?.locations, [try project.location(from: "1️⃣", to: "2️⃣", in: "header.h")])
  }

  func testLookThroughXcrun() async throws {
    try SkipUnless.platformIsDarwin("xcrun is macOS only")

    try await withTestScratchDir { scratchDirectory in
      let toolchainRegistry = try XCTUnwrap(ToolchainRegistry.forTesting)

      let project = try await MultiFileTestProject(
        files: [
          "test.swift": """
          #warning("Test warning")
          """,
          "compile_commands.json": """
          [
            {
              "directory": "$TEST_DIR_BACKSLASH_ESCAPED",
              "arguments": [
                "/usr/bin/swiftc",
                "$TEST_DIR_BACKSLASH_ESCAPED/test.swift",
                \(defaultSDKArgs)
              ],
              "file": "test.swift",
              "output": "$TEST_DIR_BACKSLASH_ESCAPED/test.swift.o"
            }
          ]
          """,
        ],
        toolchainRegistry: toolchainRegistry
      )

      let (uri, _) = try project.openDocument("test.swift")
      let diagnostics = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      XCTAssertEqual(diagnostics.fullReport?.items.map(\.message), ["Test warning"])
    }
  }
}

private let defaultSDKArgs: String = {
  if let defaultSDKPath {
    let escapedPath = defaultSDKPath.replacing(#"\"#, with: #"\\"#)
    return """
      "-sdk", "\(escapedPath)"
      """
  }
  return ""
}()
