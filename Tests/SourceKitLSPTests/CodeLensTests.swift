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
import SKLogging
import SKTestSupport
import XCTest

final class CodeLensTests: SourceKitLSPTestCase {
  func testNoLenses() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.run: "swift.run",
      SupportedCodeLensCommand.debug: "swift.debug",
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))

    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        struct MyApp {
          public static func main() {}
        }
        """
      ],
      capabilities: capabilities
    )
    let (uri, _) = try project.openDocument("Test.swift")

    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )

    XCTAssertEqual(response, [])
  }

  func testNoClientCodeLenses() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        @main
        struct MyApp {
          public static func main() {}
        }
        """
      ]
    )

    let (uri, _) = try project.openDocument("Test.swift")

    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )

    XCTAssertEqual(response, [])
  }

  func testSuccessfulCodeLensRequest() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.run: "swift.run",
      SupportedCodeLensCommand.debug: "swift.debug",
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyApp/Test.swift": """
        1️⃣@main2️⃣
        struct MyApp {
          public static func main() {}
        }
        """
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyApp",
          targets: [.executableTarget(name: "MyApp")]
        )
        """,
      capabilities: capabilities
    )

    let (uri, positions) = try project.openDocument("Test.swift")

    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )

    XCTAssertEqual(
      response,
      [
        CodeLens(
          range: positions["1️⃣"]..<positions["2️⃣"],
          command: Command(title: "Run MyApp", command: "swift.run", arguments: [.string("MyApp")])
        ),
        CodeLens(
          range: positions["1️⃣"]..<positions["2️⃣"],
          command: Command(title: "Debug MyApp", command: "swift.debug", arguments: [.string("MyApp")])
        ),
      ]
    )
  }
}
