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

@_spi(Testing) import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SemanticIndex
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import struct TSCBasic.AbsolutePath

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

  private var workspaceFiles: [RelativeFileLocation: String] = [
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
  ]

  private let packageManifestWithTestTarget = """
    let package = Package(
      name: "MyLibrary",
      targets: [.target(name: "MyLibrary"), .target(name: "MyApp")]
    )
    """

  func testWorkspacePlaygroundsScanned() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let project = try await SwiftPMTestProject(
      files: workspaceFiles,
      manifest: packageManifestWithTestTarget,
      toolchainRegistry: toolchainRegistry
    )

    let response = try await project.testClient.send(
      WorkspacePlaygroundsRequest()
    )

    let (testUri, testPositions) = try project.openDocument("Test.swift")
    let (barUri, barPositions) = try project.openDocument("bar.swift")
    let (bazUri, bazPositions) = try project.openDocument("baz.swift")

    // Notice sorted order
    XCTAssertEqual(
      response,
      [
        Playground(
          id: "MyApp/baz.swift:3:2",
          label: "baz",
          location: .init(uri: bazUri, range: bazPositions["1️⃣"]..<bazPositions["2️⃣"]),
        ),
        Playground(
          id: "MyLibrary/Test.swift:7:1",
          label: "foo",
          location: .init(uri: testUri, range: testPositions["1️⃣"]..<testPositions["2️⃣"]),
        ),
        Playground(
          id: "MyLibrary/Test.swift:11:1",
          label: nil,
          location: .init(uri: testUri, range: testPositions["3️⃣"]..<testPositions["4️⃣"]),
        ),
        Playground(
          id: "MyLibrary/Test.swift:19:1",
          label: "bar",
          location: .init(uri: testUri, range: testPositions["5️⃣"]..<testPositions["6️⃣"]),
        ),
        Playground(
          id: "MyLibrary/bar.swift:3:1",
          label: "bar2",
          location: .init(uri: barUri, range: barPositions["1️⃣"]..<barPositions["2️⃣"]),
        ),
      ]
    )
  }

  func testWorkspacePlaygroundsCapability() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithSwiftPlay])
    let initializeResult = ThreadSafeBox<InitializeResult?>(initialValue: nil)
    let _ = try await SwiftPMTestProject(
      files: workspaceFiles,
      manifest: packageManifestWithTestTarget,
      toolchainRegistry: toolchainRegistry,
      postInitialization: { result in
        initializeResult.withLock {
          $0 = result
        }
      }
    )

    switch initializeResult.value?.capabilities.experimental {
    case .dictionary(let dict):
      XCTAssertNotEqual(dict[WorkspacePlaygroundsRequest.method], nil)
    default:
      XCTFail("Experminental capabilities is not a dictionary")
    }
  }

  func testWorkspacePlaygroundsCapabilityNoSwiftPlay() async throws {
    let toolchainRegistry = ToolchainRegistry(toolchains: [try await Toolchain.forTestingWithoutSwiftPlay])
    let initializeResult = ThreadSafeBox<InitializeResult?>(initialValue: nil)
    let _ = try await SwiftPMTestProject(
      files: workspaceFiles,
      manifest: packageManifestWithTestTarget,
      toolchainRegistry: toolchainRegistry,
      postInitialization: { result in
        initializeResult.withLock {
          $0 = result
        }
      }
    )

    switch initializeResult.value?.capabilities.experimental {
    case .dictionary(let dict):
      XCTAssertEqual(dict[WorkspacePlaygroundsRequest.method], nil)
    default:
      XCTFail("Experminental capabilities is not a dictionary")
    }
  }
}
