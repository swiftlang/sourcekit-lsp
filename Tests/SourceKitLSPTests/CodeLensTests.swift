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
import ToolchainRegistry
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
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        import Playgrounds
        @main
        struct MyApp {
          public static func main() {}
        }

        #Playground {
          print("Hello Playground!")
        }

        #Playground("named") {
          print("Hello named Playground!")
        }
        """
      ],
      toolchainRegistry: toolchainRegistry
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
      SupportedCodeLensCommand.play: "swift.play",
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyApp/Test.swift": """
        import Playgrounds
        1️⃣@main2️⃣
        struct MyApp {
          public static func main() {}
        }

        3️⃣#Playground {
          print("Hello Playground!")
        }4️⃣

        5️⃣#Playground("named") {
          print("Hello named Playground!")
        }6️⃣
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
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
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
        CodeLens(
          range: positions["3️⃣"]..<positions["4️⃣"],
          command: Command(
            title: "Play \"MyApp/Test.swift:7:1\"",
            command: "swift.play",
            arguments: [
              TextDocumentPlayground(
                id: "MyApp/Test.swift:7:1",
                label: nil,
                range: positions["3️⃣"]..<positions["4️⃣"],
              ).encodeToLSPAny()
            ]
          )
        ),
        CodeLens(
          range: positions["5️⃣"]..<positions["6️⃣"],
          command: Command(
            title: "Play \"named\"",
            command: "swift.play",
            arguments: [
              TextDocumentPlayground(
                id: "MyApp/Test.swift:11:1",
                label: "named",
                range: positions["5️⃣"]..<positions["6️⃣"],
              ).encodeToLSPAny()
            ]
          )
        ),
      ]
    )
  }

  func testMultiplePlaygroundCodeLensOnLine() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.play: "swift.play"
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds
        1️⃣#Playground { print("Hello Playground!") }2️⃣;  3️⃣#Playground { print("Hello Again!") }4️⃣
        """
      ],
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
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
          command: Command(
            title: #"Play "MyLibrary/Test.swift:2:1""#,
            command: "swift.play",
            arguments: [
              TextDocumentPlayground(
                id: "MyLibrary/Test.swift:2:1",
                label: nil,
                range: positions["1️⃣"]..<positions["2️⃣"],
              ).encodeToLSPAny()
            ]
          )
        ),
        CodeLens(
          range: positions["3️⃣"]..<positions["4️⃣"],
          command: Command(
            title: "Play \"MyLibrary/Test.swift:2:46\"",
            command: "swift.play",
            arguments: [
              TextDocumentPlayground(
                id: "MyLibrary/Test.swift:2:46",
                label: nil,
                range: positions["3️⃣"]..<positions["4️⃣"],
              ).encodeToLSPAny()
            ]
          )
        ),
      ]
    )
  }

  func testCodeLensRequestSwiftPlayMissing() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.run: "swift.run",
      SupportedCodeLensCommand.debug: "swift.debug",
      SupportedCodeLensCommand.play: "swift.play",
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithoutSwiftPlay])

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyApp/Test.swift": """
        import Playgrounds
        1️⃣@main2️⃣
        struct MyApp {
          public static func main() {}
        }

        #Playground {
          print("Hello Playground!")
        }

        #Playground("named") {
          print("Hello named Playground!")
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
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
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

  func testNoImportPlaygrounds() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.play: "swift.play"
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        public func foo() -> String {
          "bar"
        }

        #Playground("foo") {
          print(foo())
        }

        #Playground {
          print(foo())
        }

        public func bar(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        #Playground("bar") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }
        """
      ],
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
    )

    let (uri, _) = try project.openDocument("Test.swift")
    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(response, [])
  }

  func testCodeLensRequestNoPlaygrounds() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.play: "swift.play"
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds

        public func Playground(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        @Playground
        struct MyPlayground {
          public var playground: String = ""
        }
        """
      ],
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
    )

    let (uri, _) = try project.openDocument("Test.swift")
    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(response, [])
  }

  func testEmojiPlaygroundName() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.play: "swift.play"
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds
        1️⃣#Playground("🧑‍🧑‍🧒‍🧒") { print("Hello Playground!") }2️⃣
        """
      ],
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
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
          command: Command(
            title: #"Play "🧑‍🧑‍🧒‍🧒""#,
            command: "swift.play",
            arguments: [
              TextDocumentPlayground(
                id: "MyLibrary/Test.swift:2:1",
                label: "🧑‍🧑‍🧒‍🧒",
                range: positions["1️⃣"]..<positions["2️⃣"],
              ).encodeToLSPAny()
            ]
          )
        )
      ]
    )
  }

  func testUtf8PlaygroundOffset() async throws {
    var codeLensCapabilities = TextDocumentClientCapabilities.CodeLens()
    codeLensCapabilities.supportedCommands = [
      SupportedCodeLensCommand.play: "swift.play"
    ]
    let capabilities = ClientCapabilities(textDocument: TextDocumentClientCapabilities(codeLens: codeLensCapabilities))
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])

    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds
        /* 🧑‍🧑‍🧒‍🧒 */ 1️⃣#Playground { print("Hello Playground!") }2️⃣
        """
      ],
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry
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
          command: Command(
            title: #"Play "MyLibrary/Test.swift:2:33""#,
            command: "swift.play",
            arguments: [
              TextDocumentPlayground(
                id: "MyLibrary/Test.swift:2:33",
                label: nil,
                range: positions["1️⃣"]..<positions["2️⃣"],
              ).encodeToLSPAny()
            ]
          )
        )
      ]
    )
  }
}
