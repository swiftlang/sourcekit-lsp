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
import Foundation
import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftDocC
import XCTest

final class DoccDocumentationTests: XCTestCase {
  func testEmptySwiftFile() async throws {
    try await renderDocumentation(
      swiftFile: "0️⃣",
      expectedResponses: [
        "0️⃣": .error(.noDocumentation)
      ]
    )
  }

  func testFunction() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A function that do0️⃣es some important stuff.
        func func1️⃣tion() {
          // Some import2️⃣ant function contents.
        }3️⃣
        """,
      expectedResponses: [
        "0️⃣": .renderNode(kind: .symbol, path: "test/function()"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/function()"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/function()"),
        "3️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testStructure() async throws {
    try await renderDocumentation(
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
        "0️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Structure/foo"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Structure/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Structure/bar"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Structure/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Structure/init(_:bar:)"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Structure/init(_:bar:)"),
        "8️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyStructure() async throws {
    try await renderDocumentation(
      swiftFile: """
        pub0️⃣lic struct Struc1️⃣ture {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        "0️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "3️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testClass() async throws {
    try await renderDocumentation(
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
        "0️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Class/foo"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Class/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Class/bar"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Class/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Class/init(_:bar:)"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Class/init(_:bar:)"),
        "8️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "9️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyClass() async throws {
    try await renderDocumentation(
      swiftFile: """
        pub0️⃣lic class Cla1️⃣ss {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        "0️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "3️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testActor() async throws {
    try await renderDocumentation(
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
        "0️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Actor/foo"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Actor/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Actor/bar"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Actor/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Actor/init(_:bar:)"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Actor/init(_:bar:)"),
        "8️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyActor() async throws {
    try await renderDocumentation(
      swiftFile: """
        pub0️⃣lic class Act1️⃣or {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        "0️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "3️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEnumeration() async throws {
    try await renderDocumentation(
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
        "0️⃣": .renderNode(kind: .symbol, path: "test/Enum"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Enum"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Enum/first"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Enum/first"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Enum/second"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Enum/second"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Enum/third(_:)"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Enum/third(_:)"),
        "8️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEditDocLineCommentAboveEnumCaseElement() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      /// An enumeration containing important information.
      public enum Enum {
        /// The first case.
        case first

        /// The 0️⃣second case.
        case second

        // The third case.
        case third(Int)
      }
      """,
      uri: uri
    )

    // Make sure that the initial documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "The second case")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: positions["0️⃣"]..<positions["0️⃣"], text: "very ")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "The very second case")]
    )
  }

  func testProtocol() async throws {
    try await renderDocumentation(
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
        "0️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Protocol/foo"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Protocol/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Protocol/bar"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Protocol/bar"),
        "6️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyProtocol() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A protocol containing important information
        pub0️⃣lic struct Prot1️⃣ocol {
          2️⃣
        }3️⃣
        """,
      expectedResponses: [
        "0️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "3️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testExtension() async throws {
    try await renderDocumentation(
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
        "0️⃣": .error(.noDocumentation),
        "1️⃣": .renderNode(kind: .symbol, path: "test/Structure/numberPlusOne"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Structure/Kind"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Structure/Kind/first"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Structure/Kind/second"),
        "5️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEditDocLineCommentInSwiftFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      /// A structure containing0️⃣ important information
      public struct Structure {
        let number: Int
      }
      """,
      uri: uri
    )

    // Make sure that the initial documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "A structure containing important information")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: positions["0️⃣"]..<positions["0️⃣"], text: " very")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: [
        "0️⃣": .renderNode(kind: .symbol, containing: "A structure containing very important information")
      ]
    )
  }

  func testEditMultipleDocLineCommentsInSwiftFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      /// A structure containing important information
      ///
      /// This is a0️⃣ description
      public struct Structure {
        let number: Int
      }
      """,
      uri: uri
    )

    // Make sure that the initial documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "This is a description")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: positions["0️⃣"]..<positions["0️⃣"], text: "n amazing")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "This is an amazing description")]
    )
  }

  func testEditDocBlockCommentInSwiftFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      /**
      A structure containing important information

      This is a0️⃣ description
      */
      public struct Structure {
        let number: Int
      }
      """,
      uri: uri
    )

    // Make sure that the initial documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "This is a description")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: positions["0️⃣"]..<positions["0️⃣"], text: "n amazing")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["0️⃣": .renderNode(kind: .symbol, containing: "This is an amazing description")]
    )
  }
}

fileprivate enum PartialConvertResponse {
  case renderNode(kind: RenderNode.Kind, path: String? = nil, containing: String? = nil)
  case error(ConvertDocumentationError)
}

fileprivate func renderDocumentation(
  swiftFile markedText: String,
  expectedResponses: [String: PartialConvertResponse],
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: .swift)
  let positions = testClient.openDocument(markedText, uri: uri)

  await renderDocumentation(
    testClient: testClient,
    uri: uri,
    positions: positions,
    expectedResponses: expectedResponses,
    file: file,
    line: line
  )
}

fileprivate func renderDocumentation(
  testClient: TestSourceKitLSPClient,
  uri: DocumentURI,
  positions: DocumentPositions,
  expectedResponses: [String: PartialConvertResponse],
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  for marker in positions.allMarkers {
    guard let expectedResponse = expectedResponses[marker] else {
      XCTFail("No expected response was given for marker \(marker)", file: file, line: line)
      return
    }
    let actualResponse = await testClient.sendWithRawResponse(
      DoccDocumentationRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions[marker]
      )
    )
    switch actualResponse {
    case .success(let response):
      let renderNodeString = response.renderNode
      guard let renderNodeData = renderNodeString.data(using: .utf8),
        let renderNode = try? JSONDecoder().decode(RenderNode.self, from: renderNodeData)
      else {
        XCTFail("failed to decode response from textDocument/doccDocumentation at position \(marker)")
        return
      }
      switch expectedResponse {
      case .renderNode(let expectedKind, let expectedPath, let expectedContents):
        XCTAssertEqual(
          renderNode.kind,
          expectedKind,
          "render node kind did not match expected value at position \(marker)",
          file: file,
          line: line
        )
        if let expectedPath = expectedPath {
          XCTAssertEqual(
            renderNode.identifier.path,
            "/documentation/\(expectedPath)",
            "render node path did not match expected value at position \(marker)",
            file: file,
            line: line
          )
        }
        if let expectedContents = expectedContents {
          XCTAssertTrue(
            renderNodeString.contains(expectedContents),
            "render node did not contain text \"\(expectedContents)\" at position \(marker)",
            file: file,
            line: line
          )
        }
      case .error(let error):
        XCTFail(
          "expected error \(error.message), but received a render node at position \(marker)",
          file: file,
          line: line
        )
      }
    case .failure(let error):
      switch expectedResponse {
      case .renderNode:
        XCTFail(
          "textDocument/doccDocumentation failed at position \(marker): \(error.localizedDescription)",
          file: file,
          line: line
        )
      case .error(let expectedError):
        XCTAssertEqual(
          error.code,
          .requestFailed,
          "expected a responseFailed error code at position \(marker)",
          file: file,
          line: line
        )
        XCTAssertEqual(
          error.message,
          expectedError.message,
          "expected an error with message \(expectedError.message) at position \(marker)",
          file: file,
          line: line
        )
      }
    }
  }
}
#endif
