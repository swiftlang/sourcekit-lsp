//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SwiftExtensions
import ToolchainRegistry
import XCTest

extension Toolchain {
  #if compiler(>=6.4)
  #warning(
    "Once we require swift-play in the toolchain that's used to test SourceKit-LSP, we can just use `forTesting`"
  )
  #endif
  static var forTestingWithSwiftPlay: Toolchain {
    get async throws {
      let toolchain = try await unwrap(ToolchainRegistry.forTesting.default)
      return Toolchain(
        identifier: "\(toolchain.identifier)-swift-swift",
        displayName: "\(toolchain.identifier) with swift-play",
        path: toolchain.path,
        clang: toolchain.clang,
        swift: toolchain.swift,
        swiftc: toolchain.swiftc,
        swiftPlay: URL(fileURLWithPath: "/dummy/usr/bin/swift-play"),
        clangd: toolchain.clangd,
        sourcekitd: toolchain.sourcekitd,
        sourceKitClientPlugin: toolchain.sourceKitClientPlugin,
        sourceKitServicePlugin: toolchain.sourceKitServicePlugin,
        libIndexStore: toolchain.libIndexStore
      )
    }
  }

  static var forTestingWithoutSwiftPlay: Toolchain {
    get async throws {
      let toolchain = try await unwrap(ToolchainRegistry.forTesting.default)
      return Toolchain(
        identifier: "\(toolchain.identifier)-no-swift-swift",
        displayName: "\(toolchain.identifier) without swift-play",
        path: toolchain.path,
        clang: toolchain.clang,
        swift: toolchain.swift,
        swiftc: toolchain.swiftc,
        swiftPlay: nil,
        clangd: toolchain.clangd,
        sourcekitd: toolchain.sourcekitd,
        sourceKitClientPlugin: toolchain.sourceKitClientPlugin,
        sourceKitServicePlugin: toolchain.sourceKitServicePlugin,
        libIndexStore: toolchain.libIndexStore
      )
    }
  }
}

final class WorkspacePlaygroundDiscoveryTests: SourceKitLSPTestCase {

  func testWorkspacePlaygroundsScanned() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds

        public func foo() -> String {
          "bar"
        }

        1️⃣#Playground("foo") {
          print(foo())
        }2️⃣

        3️⃣#Playground {
          print(foo())
        }4️⃣

        public func bar(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        5️⃣#Playground("bar") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }6️⃣
        """,
        "Sources/MyLibrary/TestNoImport.swift": """
        #Playground("fooNoImport") {
          print(foo())
        }

        #Playground {
          print(foo())
        }

        #Playground("barNoImport") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }
        """,
        "Sources/MyLibrary/bar.swift": """
        import Playgrounds

        1️⃣#Playground("bar2") {
          print(foo())
        }2️⃣
        """,
        "Sources/MyApp/baz.swift": """
        import Playgrounds

         1️⃣#Playground("baz") {
          print("baz")
        }2️⃣
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .target(name: "MyApp")
          ]
        )
        """,
      toolchainRegistry: toolchainRegistry
    )

    let response = try await project.testClient.send(WorkspacePlaygroundsRequest())

    // Notice sorted order
    XCTAssertEqual(
      response,
      [
        Playground(
          id: "MyApp/baz.swift:3:2",
          label: "baz",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "baz.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:7:1",
          label: "foo",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:11:1",
          label: nil,
          location: try project.location(from: "3️⃣", to: "4️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:19:1",
          label: "bar",
          location: try project.location(from: "5️⃣", to: "6️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/bar.swift:3:1",
          label: "bar2",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "bar.swift")
        ),
      ]
    )
  }

  func testWorkspacePlaygroundsInTestTarget() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import Playgrounds
        import XCTest

        public func foo() -> String {
          "bar"
        }

        1️⃣#Playground("foo") {
          print(foo())
        }2️⃣

        3️⃣#Playground("bar") {
          print(foo())
        }4️⃣

        class MyTests: XCTestCase {
          func testMyLibrary() {
            XCTAssertEqual(foo(), "bar)
          }
        }
        """
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      toolchainRegistry: toolchainRegistry
    )

    let response = try await project.testClient.send(WorkspacePlaygroundsRequest())

    XCTAssertEqual(
      response,
      [
        Playground(
          id: "MyLibraryTests/MyTests.swift:8:1",
          label: "foo",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "MyTests.swift")
        ),
        Playground(
          id: "MyLibraryTests/MyTests.swift:12:1",
          label: "bar",
          location: try project.location(from: "3️⃣", to: "4️⃣", in: "MyTests.swift")
        ),
      ]
    )
  }

  func testWorkspacePlaygroundsFileChange() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds

        public func foo() -> String {
          "bar"
        }

        1️⃣#Playground("foo") {
          print(foo())
        }2️⃣

        3️⃣#Playground {
          print(foo())
        }4️⃣

        public func bar(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        5️⃣#Playground("bar") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }6️⃣
        """,
        "Sources/MyLibrary/TestNoImport.swift": """
        #Playground("fooNoImport") {
          print(foo())
        }

        #Playground {
          print(foo())
        }

        #Playground("barNoImport") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }
        """,
        "Sources/MyLibrary/bar.swift": """
        import Playgrounds

        1️⃣#Playground("bar2") {
          print(foo())
        }2️⃣
        """,
        "Sources/MyApp/baz.swift": """
        import Playgrounds

         1️⃣#Playground("baz") {
          print("baz")
        }2️⃣
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .target(name: "MyApp")
          ]
        )
        """,
      toolchainRegistry: toolchainRegistry,
    )

    let response = try await project.testClient.send(WorkspacePlaygroundsRequest())

    XCTAssertEqual(
      response,
      [
        Playground(
          id: "MyApp/baz.swift:3:2",
          label: "baz",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "baz.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:7:1",
          label: "foo",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:11:1",
          label: nil,
          location: try project.location(from: "3️⃣", to: "4️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:19:1",
          label: "bar",
          location: try project.location(from: "5️⃣", to: "6️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/bar.swift:3:1",
          label: "bar2",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "bar.swift")
        ),
      ]
    )

    _ = try await project.changeFileOnDisk(
      "Test.swift",
      newMarkedContents: """
        // No more playgrounds import
        public func foo() -> String {
          "bar"
        }

        1️⃣#Playground("baz") {
          print(foo())
        }2️⃣

        3️⃣#Playground("qux") {
          print(foo())
        }4️⃣
        """
    )

    let (uri, newPositions) = try await project.changeFileOnDisk(
      "baz.swift",
      newMarkedContents: """
        import Playgrounds
        1️⃣#Playground("newBaz") {
          print("baz")
        }2️⃣
        """
    )

    let newResponse = try await project.testClient.send(WorkspacePlaygroundsRequest())

    XCTAssertEqual(
      newResponse,
      [
        Playground(
          id: "MyApp/baz.swift:2:1",
          label: "newBaz",
          location: Location(uri: uri, range: newPositions["1️⃣"]..<newPositions["2️⃣"])
        ),
        Playground(
          id: "MyLibrary/bar.swift:3:1",
          label: "bar2",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "bar.swift")
        ),
      ]
    )
  }

  func testWorkspacePlaygroundsFileRemove() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/MyLibrary/Test.swift": """
        import Playgrounds

        public func foo() -> String {
          "bar"
        }

        1️⃣#Playground("foo") {
          print(foo())
        }2️⃣

        3️⃣#Playground {
          print(foo())
        }4️⃣

        public func bar(_ i: Int, _ j: Int) -> Int {
          i + j
        }

        5️⃣#Playground("bar") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }6️⃣
        """,
        "Sources/MyLibrary/TestNoImport.swift": """
        #Playground("fooNoImport") {
          print(foo())
        }

        #Playground {
          print(foo())
        }

        #Playground("barNoImport") {
          var i = bar(1, 2)
          i = i + 1
          print(i)
        }
        """,
        "Sources/MyLibrary/bar.swift": """
        import Playgrounds

        1️⃣#Playground("bar2") {
          print(foo())
        }2️⃣
        """,
        "Sources/MyApp/baz.swift": """
        import Playgrounds

         1️⃣#Playground("baz") {
          print("baz")
        }2️⃣
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "MyLibrary"),
            .target(name: "MyApp")
          ]
        )
        """,
      toolchainRegistry: toolchainRegistry
    )

    let response = try await project.testClient.send(WorkspacePlaygroundsRequest())

    XCTAssertEqual(
      response,
      [
        Playground(
          id: "MyApp/baz.swift:3:2",
          label: "baz",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "baz.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:7:1",
          label: "foo",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:11:1",
          label: nil,
          location: try project.location(from: "3️⃣", to: "4️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:19:1",
          label: "bar",
          location: try project.location(from: "5️⃣", to: "6️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/bar.swift:3:1",
          label: "bar2",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "bar.swift")
        ),
      ]
    )

    _ = try await project.changeFileOnDisk(
      "baz.swift",
      newMarkedContents: nil
    )

    let newResponse = try await project.testClient.send(WorkspacePlaygroundsRequest())

    XCTAssertEqual(
      newResponse,
      [
        Playground(
          id: "MyLibrary/Test.swift:7:1",
          label: "foo",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:11:1",
          label: nil,
          location: try project.location(from: "3️⃣", to: "4️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/Test.swift:19:1",
          label: "bar",
          location: try project.location(from: "5️⃣", to: "6️⃣", in: "Test.swift")
        ),
        Playground(
          id: "MyLibrary/bar.swift:3:1",
          label: "bar2",
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "bar.swift")
        ),
      ]
    )
  }

  func testWorkspacePlaygroundsCapability() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let testClient = try await TestSourceKitLSPClient(toolchainRegistry: toolchainRegistry)
    let experimentalCapabilities = testClient.initializeResult?.capabilities.experimental
    switch experimentalCapabilities {
    case .dictionary(let dict):
      XCTAssertNotEqual(dict[WorkspacePlaygroundsRequest.method], nil)
    default:
      XCTFail("Experimental capabilities expected to be a dictionary, got \(experimentalCapabilities as Any)")
    }
  }

  func testWorkspacePlaygroundsCapabilityNoSwiftPlay() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithoutSwiftPlay])
    let testClient = try await TestSourceKitLSPClient(toolchainRegistry: toolchainRegistry)
    let experimentalCapabilities = testClient.initializeResult?.capabilities.experimental
    switch experimentalCapabilities {
    case .dictionary(let dict):
      XCTAssertEqual(dict[WorkspacePlaygroundsRequest.method], nil)
    default:
      XCTFail("Experimental capabilities expected to be a dictionary, got \(experimentalCapabilities as Any)")
    }
  }
}
