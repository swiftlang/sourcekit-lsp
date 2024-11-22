//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(SwiftDocC)
import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftDocC
import XCTest

final class ConvertDocumentationTests: XCTestCase {
  func testEmptySwiftFile() async throws {
    try await convertDocumentation(
      swiftFile: "0️⃣",
      expectedResponses: [
        .error(.noDocumentation)
      ]
    )
  }

  func testFunction() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// A function that do0️⃣es some important stuff.
        func func1️⃣tion() {
          // Some import2️⃣ant function contents.
        }3️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/function()")),
        .renderNode(.init(kind: .symbol, path: "test/function()")),
        .renderNode(.init(kind: .symbol, path: "test/function()")),
        .error(.noDocumentation),
      ]
    )
  }

  func testStructure() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// A structure contain0️⃣ing important information.
        public struct Struc1️⃣ture {
          /// The inte2️⃣ger `foo`
          var foo: I3️⃣nt

          /// The other integer `bar`4️⃣
          v5️⃣ar bar: Int

          /// Initiali6️⃣ze the structure.
          init(_ foo: Int,7️⃣ bar: Int) {
            self.foo = foo
            self.bar = bar
          }
        }8️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Structure")),
        .renderNode(.init(kind: .symbol, path: "test/Structure")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/init(_:bar:)")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/init(_:bar:)")),
        .error(.noDocumentation),
      ]
    )
  }

  func testEmptyStructure() async throws {
    try await convertDocumentation(
      swiftFile: """
        pub0️⃣lic struct Struc1️⃣ture {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Structure")),
        .renderNode(.init(kind: .symbol, path: "test/Structure")),
        .renderNode(.init(kind: .symbol, path: "test/Structure")),
        .error(.noDocumentation),
      ]
    )
  }

  func testClass() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// A class contain0️⃣ing important information.
        public class Cla1️⃣ss {
          /// The inte2️⃣ger `foo`
          var foo: I3️⃣nt

          /// The other integer `bar`4️⃣
          v5️⃣ar bar: Int

          /// Initiali6️⃣ze the class.
          init(_ foo: Int,7️⃣ bar: Int) {
            self.foo = foo
            self.bar = bar
          }8️⃣
        }9️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Class")),
        .renderNode(.init(kind: .symbol, path: "test/Class")),
        .renderNode(.init(kind: .symbol, path: "test/Class/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Class/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Class/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Class/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Class/init(_:bar:)")),
        .renderNode(.init(kind: .symbol, path: "test/Class/init(_:bar:)")),
        .renderNode(.init(kind: .symbol, path: "test/Class")),
        .error(.noDocumentation),
      ]
    )
  }

  func testEmptyClass() async throws {
    try await convertDocumentation(
      swiftFile: """
        pub0️⃣lic class Cla1️⃣ss {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Class")),
        .renderNode(.init(kind: .symbol, path: "test/Class")),
        .renderNode(.init(kind: .symbol, path: "test/Class")),
        .error(.noDocumentation),
      ]
    )
  }

  func testActor() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// An actor contain0️⃣ing important information.
        public actor Ac1️⃣tor {
          /// The inte2️⃣ger `foo`
          var foo: I3️⃣nt

          /// The other integer `bar`4️⃣
          v5️⃣ar bar: Int

          /// Initiali6️⃣ze the actor.
          init(_ foo: Int,7️⃣ bar: Int) {
            self.foo = foo
            self.bar = bar
          }
        }8️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Actor")),
        .renderNode(.init(kind: .symbol, path: "test/Actor")),
        .renderNode(.init(kind: .symbol, path: "test/Actor/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Actor/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Actor/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Actor/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Actor/init(_:bar:)")),
        .renderNode(.init(kind: .symbol, path: "test/Actor/init(_:bar:)")),
        .error(.noDocumentation),
      ]
    )
  }

  func testEmptyActor() async throws {
    try await convertDocumentation(
      swiftFile: """
        pub0️⃣lic class Act1️⃣or {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Actor")),
        .renderNode(.init(kind: .symbol, path: "test/Actor")),
        .renderNode(.init(kind: .symbol, path: "test/Actor")),
        .error(.noDocumentation),
      ]
    )
  }

  func testEnumeration() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// An enumeration contain0️⃣ing important information.
        public enum En1️⃣um {
          /// The 2️⃣first case.
          case fi3️⃣rst

          //4️⃣/ The second case.
          ca5️⃣se second

          // The third case.6️⃣
          case third(In7️⃣t)
        }8️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Enum")),
        .renderNode(.init(kind: .symbol, path: "test/Enum")),
        .renderNode(.init(kind: .symbol, path: "test/Enum/first")),
        .renderNode(.init(kind: .symbol, path: "test/Enum/first")),
        .renderNode(.init(kind: .symbol, path: "test/Enum/second")),
        .renderNode(.init(kind: .symbol, path: "test/Enum/second")),
        .renderNode(.init(kind: .symbol, path: "test/Enum/third(_:)")),
        .renderNode(.init(kind: .symbol, path: "test/Enum/third(_:)")),
        .error(.noDocumentation),
      ]
    )
  }

  func testProtocol() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// A protocol contain0️⃣ing important information.
        public protocol Proto1️⃣col {
          /// The inte2️⃣ger `foo`
          var foo: I3️⃣nt

          /// The other integer `bar`4️⃣
          v5️⃣ar bar: Int
        }6️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Protocol")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol/foo")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol/bar")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol/bar")),
        .error(.noDocumentation),
      ]
    )
  }

  func testEmptyProtocol() async throws {
    try await convertDocumentation(
      swiftFile: """
        pub0️⃣lic struct Prot1️⃣ocol {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        .renderNode(.init(kind: .symbol, path: "test/Protocol")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol")),
        .renderNode(.init(kind: .symbol, path: "test/Protocol")),
        .error(.noDocumentation),
      ]
    )
  }

  func testExtension() async throws {
    try await convertDocumentation(
      swiftFile: """
        /// A structure containing important information
        public struct Structure {
          let number: Int
        }

        extension Stru0️⃣cture {
          /// One more than the number
          var numberPlusOne: Int {1️⃣ number + 1 }

          /// The kind of2️⃣ this structure
          enum Kind {
            /// The fi3️⃣rst kind
            case first
            /// The se4️⃣cond kind
            case second
          }
        }5️⃣
        """,
      expectedResponses: [
        .error(.noDocumentation),
        .renderNode(.init(kind: .symbol, path: "test/Structure/numberPlusOne")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/Kind")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/Kind/first")),
        .renderNode(.init(kind: .symbol, path: "test/Structure/Kind/second")),
        .error(.noDocumentation),
      ]
    )
  }
}

fileprivate struct PartialRenderNode {
  let kind: RenderNode.Kind
  let path: String?

  init(kind: RenderNode.Kind, path: String? = nil) {
    self.kind = kind
    self.path = path
  }
}

fileprivate enum PartialConvertResponse {
  case renderNode(PartialRenderNode)
  case error(ConvertDocumentationError)
}

fileprivate func convertDocumentation(
  swiftFile markedText: String,
  expectedResponses: [PartialConvertResponse],
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: .swift)
  let positions = testClient.openDocument(markedText, uri: uri)

  await convertDocumentation(
    testClient: testClient,
    uri: uri,
    positions: positions,
    expectedResponses: expectedResponses,
    file: file,
    line: line
  )
}

fileprivate func convertDocumentation(
  testClient: TestSourceKitLSPClient,
  uri: DocumentURI,
  positions: DocumentPositions,
  expectedResponses: [PartialConvertResponse],
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  guard expectedResponses.count == positions.allMarkers.count else {
    XCTFail(
      "the number of expected render nodes did not match the number of positions in the text document",
      file: file,
      line: line
    )
    return
  }

  for (index, marker) in positions.allMarkers.enumerated() {
    let response: ConvertDocumentationResponse
    do {
      response = try await testClient.send(
        ConvertDocumentationRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: positions[marker]
        )
      )
    } catch {
      XCTFail(
        "textDocument/convertDocumentation failed at position \(marker): \(error.message)",
        file: file,
        line: line
      )
      return
    }
    switch response {
    case .renderNode(let renderNodeString):
      guard let renderNode = try? JSONDecoder().decode(RenderNode.self, from: renderNodeString) else {
        XCTFail("failed to decode response from textDocument/convertDocumentation at position \(marker)")
        return
      }
      switch expectedResponses[index] {
      case .renderNode(let expectedRenderNode):
        XCTAssertEqual(
          renderNode.kind,
          expectedRenderNode.kind,
          "render node kind did not match expected value at position \(marker)",
          file: file,
          line: line
        )
        if let expectedPath = expectedRenderNode.path {
          XCTAssertEqual(
            renderNode.identifier.path,
            "/documentation/\(expectedPath)",
            "render node path did not match expected value at position \(marker)",
            file: file,
            line: line
          )
        }
      case .error(let error):
        XCTFail(
          "expected error \(error.rawValue), but received a render node at position \(marker)",
          file: file,
          line: line
        )
      }
    case .error(let error):
      switch expectedResponses[index] {
      case .renderNode:
        XCTFail(
          "expected a render node, but received an error \(error.rawValue) at position \(marker)",
          file: file,
          line: line
        )
      case .error(let expectedError):
        XCTAssertEqual(error, expectedError, file: file, line: line)
      }
    }
  }
}

fileprivate extension ConvertDocumentationError {
  var rawValue: String {
    switch self {
    case .indexNotAvailable:
      return "indexNotAvailable"
    case .noDocumentation:
      return "noDocumentation"
    case .symbolNotFound:
      return "symbolNotFound"
    }
  }
}
#endif
