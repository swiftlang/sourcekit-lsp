//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import XCTest

final class TypeDefinitionTests: SourceKitLSPTestCase {
  func testTypeDefinitionLocalType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct 1️⃣MyType {}
      let 2️⃣x = MyType()
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }

  func testTypeDefinitionCrossModule() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/MyType.swift": """
        public struct 1️⃣MyType {
          public init() {}
        }
        """,
        "LibB/UseType.swift": """
        import LibA
        let 2️⃣x = MyType()
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("UseType.swift")

    let response = try await project.testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, try project.uri(for: "MyType.swift"))
    XCTAssertEqual(location.range, try Range(project.position(of: "1️⃣", in: "MyType.swift")))
  }

  func testTypeDefinitionGenericType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct 1️⃣Container<T> {
        var value: T
      }
      let 2️⃣x = Container(value: 42)
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }

  func testTypeDefinitionOnTypeAnnotation() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct 1️⃣MyType {}
      let x: 2️⃣MyType = MyType()
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }

  func testTypeDefinitionFunctionParameter() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct 1️⃣MyType {}
      func process(_ 2️⃣value: MyType) {}
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }

  func testTypeDefinitionFunctionReturnType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct 1️⃣MyType {}
      func 2️⃣create() -> MyType { MyType() }
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }

  func testTypeDefinitionClassType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      class 1️⃣MyClass {}
      let 2️⃣instance = MyClass()
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }

  func testTypeDefinitionEnumType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      enum 1️⃣Status { case active, inactive }
      let 2️⃣current = Status.active
      """,
      uri: uri
    )

    let response = try await testClient.send(
      TypeDefinitionRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["2️⃣"]
      )
    )

    guard case .locations(let locations) = response, let location = locations.first else {
      XCTFail("Expected location response")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range, Range(positions["1️⃣"]))
  }
}
