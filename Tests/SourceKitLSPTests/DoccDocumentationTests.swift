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
  // MARK: Swift Documentation

  func testEmptySwiftFile() async throws {
    try await renderDocumentation(
      swiftFile: "1️⃣",
      expectedResponses: [
        "1️⃣": .error(.noDocumentation)
      ]
    )
  }

  func testFunction() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A function that do1️⃣es some important stuff.
        func func2️⃣tion() {
          // Some import3️⃣ant function contents.
        }4️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/function()"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/function()"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/function()"),
        "4️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testStructure() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A structure contain1️⃣ing important information.
        public struct Struc2️⃣ture {
          /// The inte3️⃣ger `foo`
          var foo: I4️⃣nt

          /// The other integer `bar`5️⃣
          v6️⃣ar bar: Int

          /// Initiali7️⃣ze the structure.
          init(_ foo: Int,8️⃣ bar: Int) {
            self.foo = foo
            self.bar = bar
          }
        }9️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Structure/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Structure/foo"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Structure/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Structure/bar"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Structure/init(_:bar:)"),
        "8️⃣": .renderNode(kind: .symbol, path: "test/Structure/init(_:bar:)"),
        "9️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyStructure() async throws {
    try await renderDocumentation(
      swiftFile: """
        pub1️⃣lic struct Struc2️⃣ture {
          3️⃣
        }4️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Structure"),
        "4️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testClass() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A class contain1️⃣ing important information.
        public class Cla2️⃣ss {
          /// The inte3️⃣ger `foo`
          var foo: I4️⃣nt

          /// The other integer `bar`5️⃣
          v6️⃣ar bar: Int

          /// Initiali7️⃣ze the class.
          init(_ foo: Int,8️⃣ bar: Int) {
            self.foo = foo
            self.bar = bar
          }9️⃣
        }0️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Class/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Class/foo"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Class/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Class/bar"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Class/init(_:bar:)"),
        "8️⃣": .renderNode(kind: .symbol, path: "test/Class/init(_:bar:)"),
        "9️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "0️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyClass() async throws {
    try await renderDocumentation(
      swiftFile: """
        pub1️⃣lic class Cla2️⃣ss {
          3️⃣
        }4️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Class"),
        "4️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testActor() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// An actor contain1️⃣ing important information.
        public actor Ac2️⃣tor {
          /// The inte3️⃣ger `foo`
          var foo: I4️⃣nt

          /// The other integer `bar`5️⃣
          v6️⃣ar bar: Int

          /// Initiali7️⃣ze the actor.
          init(_ foo: Int,8️⃣ bar: Int) {
            self.foo = foo
            self.bar = bar
          }
        }9️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Actor/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Actor/foo"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Actor/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Actor/bar"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Actor/init(_:bar:)"),
        "8️⃣": .renderNode(kind: .symbol, path: "test/Actor/init(_:bar:)"),
        "9️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyActor() async throws {
    try await renderDocumentation(
      swiftFile: """
        pub1️⃣lic class Act2️⃣or {
          3️⃣
        }4️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Actor"),
        "4️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEnumeration() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// An enumeration contain1️⃣ing important information.
        public enum En2️⃣um {
          /// The 3️⃣first case.
          case fi4️⃣rst

          //5️⃣/ The second case.
          ca6️⃣se second

          // The third case.7️⃣
          case third(In8️⃣t)
        }9️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Enum"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Enum"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Enum/first"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Enum/first"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Enum/second"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Enum/second"),
        "7️⃣": .renderNode(kind: .symbol, path: "test/Enum/third(_:)"),
        "8️⃣": .renderNode(kind: .symbol, path: "test/Enum/third(_:)"),
        "9️⃣": .error(.noDocumentation),
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

        /// The 1️⃣second case.
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
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "The second case")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(positions["1️⃣"]), text: "very ")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "The very second case")]
    )
  }

  func testProtocol() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A protocol contain1️⃣ing important information.
        public protocol Proto2️⃣col {
          /// The inte3️⃣ger `foo`
          var foo: I4️⃣nt

          /// The other integer `bar`5️⃣
          v6️⃣ar bar: Int
        }7️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Protocol/foo"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Protocol/foo"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Protocol/bar"),
        "6️⃣": .renderNode(kind: .symbol, path: "test/Protocol/bar"),
        "7️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEmptyProtocol() async throws {
    try await renderDocumentation(
      swiftFile: """
        /// A protocol containing important information
        pub1️⃣lic struct Prot2️⃣ocol {
          3️⃣
        }4️⃣
        """,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Protocol"),
        "4️⃣": .error(.noDocumentation),
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

        extension Stru1️⃣cture {
          /// One more than the number
          var numberPlusOne: Int {2️⃣ number + 1 }

          /// The kind of3️⃣ this structure
          enum Kind {
            /// The fi4️⃣rst kind
            case first
            /// The se5️⃣cond kind
            case second
          }
        }6️⃣
        """,
      expectedResponses: [
        "1️⃣": .error(.noDocumentation),
        "2️⃣": .renderNode(kind: .symbol, path: "test/Structure/numberPlusOne"),
        "3️⃣": .renderNode(kind: .symbol, path: "test/Structure/Kind"),
        "4️⃣": .renderNode(kind: .symbol, path: "test/Structure/Kind/first"),
        "5️⃣": .renderNode(kind: .symbol, path: "test/Structure/Kind/second"),
        "6️⃣": .error(.noDocumentation),
      ]
    )
  }

  func testEditDocLineCommentInSwiftFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      /// A structure containing1️⃣ important information
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
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "A structure containing important information")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(positions["1️⃣"]), text: " very")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, containing: "A structure containing very important information")
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
      /// This is a1️⃣ description
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
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "This is a description")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(positions["1️⃣"]), text: "n amazing")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "This is an amazing description")]
    )
  }

  func testEditDocBlockCommentInSwiftFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      /**
      A structure containing important information

      This is a1️⃣ description
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
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "This is a description")]
    )

    // Change the content of the documentation comment
    testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(positions["1️⃣"]), text: "n amazing")
        ]
      )
    )

    // Make sure that the new documentation comment is present in the response
    await renderDocumentation(
      testClient: testClient,
      uri: uri,
      positions: positions,
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, containing: "This is an amazing description")]
    )
  }

  // MARK: Markdown Articles and Extensions

  func testMarkdownArticle() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyFile.swift": "",
        "MyLibrary/MyLibrary.docc/Getting Started.md": """
        1️⃣# Getting Started with MyLibrary

        This is a getting started article not associated with any symbol.
        """,
      ],
      enableBackgroundIndexing: true
    )
    try await renderDocumentation(
      fileName: "Getting Started.md",
      project: project,
      expectedResponses: ["1️⃣": .renderNode(kind: .article, containing: "This is a getting started article")]
    )
  }

  func testMarkdownExtension() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyFile.swift": """
        /// Documentation for foo()
        public func 1️⃣foo() {}

        /// Documentation for bar()
        public func 2️⃣bar() {}

        public struct Foo {
          /// Documentation for Foo.bar
          var b3️⃣ar: String
        }
        """,
        "MyLibrary/MyLibrary.docc/Module.md": """
        1️⃣# ``MyLibrary``
        """,
        "MyLibrary/MyLibrary.docc/foo().md": """
        1️⃣# ``MyLibrary/foo()``

        # Additional information for foo()

        This will be appended to the end of foo()'s documentation page
        """,
        "MyLibrary/MyLibrary.docc/bar().md": """
        1️⃣# ``MyLibrary/bar()``

        # Additional information for bar()

        This will be appended to the end of bar()'s documentation page
        """,
        "MyLibrary/MyLibrary.docc/Foo.bar.md": """
        1️⃣# ``MyLibrary/Foo/bar``

        # Additional information for Foo.bar

        This will be appended to the end of Foo.bar's documentation page
        """,
        "MyLibrary/MyLibrary.docc/SymbolNotFound.md": """
        1️⃣# ``MyLibrary/thisIsNotAValidSymbol``
        """,
      ],
      enableBackgroundIndexing: true
    )
    try await renderDocumentation(
      fileName: "MyFile.swift",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "MyLibrary/foo()", containing: "Additional information for foo()"),
        "2️⃣": .renderNode(kind: .symbol, path: "MyLibrary/bar()", containing: "Additional information for bar()"),
        "3️⃣": .renderNode(kind: .symbol, path: "MyLibrary/Foo/bar", containing: "Additional information for Foo.bar"),
      ]
    )
    try await renderDocumentation(
      fileName: "Module.md",
      project: project,
      expectedResponses: ["1️⃣": .renderNode(kind: .symbol, path: "MyLibrary")]
    )
    try await renderDocumentation(
      fileName: "foo().md",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "MyLibrary/foo()", containing: "Documentation for foo()")
      ]
    )
    try await renderDocumentation(
      fileName: "bar().md",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "MyLibrary/bar()", containing: "Documentation for bar()")
      ]
    )
    try await renderDocumentation(
      fileName: "Foo.bar.md",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "MyLibrary/Foo/bar", containing: "Documentation for Foo.bar")
      ]
    )
    try await renderDocumentation(
      fileName: "SymbolNotFound.md",
      project: project,
      expectedResponses: ["1️⃣": .error(.symbolNotFound("MyLibrary/thisIsNotAValidSymbol"))]
    )
  }

  func testMarkdownExtensionForExtendedStruct() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/Foo.swift": """
        public struct Foo {
          let bar: String
        }
        """,
        "MyLibrary/Color.swift": """
        extension Foo {
          /// The color of Foo
          1️⃣enum Color {
            /// A red color
            case red

            /// A blue color
            case blue

            /// A green color
            case green
          }
        }
        """,
        "MyLibrary/MyLibrary.docc/Color.md": """
        1️⃣# ``MyLibrary/Foo/Color-swift.enum``

        # Additional information for the Color enum

        This will be appended to the end of Foo.bar's documentation page
        """,
      ],
      enableBackgroundIndexing: true
    )
    try await renderDocumentation(
      fileName: "Color.swift",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(
          kind: .symbol,
          path: "MyLibrary/Foo/Color",
          containing: "Additional information for the Color enum"
        )
      ]
    )
    try await renderDocumentation(
      fileName: "Color.md",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .symbol, path: "MyLibrary/Foo/Color", containing: "The color of Foo")
      ]
    )
  }

  // MARK: Tutorials

  func testTutorial() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyFile.swift": "",
        "MyLibrary/MyLibrary.docc/MyTutorial.tutorial": """
        1️⃣@Tutorial(time: 30) {
          @Intro(title: "My Custom Tutorial") {
            This tutorial will show you how to use MyLibrary
          }
        }
        """,
      ],
      enableBackgroundIndexing: true
    )
    try await renderDocumentation(
      fileName: "MyTutorial.tutorial",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .tutorial, containing: "This tutorial will show you how to use MyLibrary")
      ]
    )
  }

  func testTutorialOverview() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyFile.swift": "",
        "MyLibrary/MyLibrary.docc/MyTutorialOverview.tutorial": """
        1️⃣@Tutorials(name: "MyTutorialOverview") {
          @Intro(title: "My Custom Tutorial Overview") {
            These tutorials will help you understand MyLibrary
          }
        }
        """,
      ],
      enableBackgroundIndexing: true
    )
    try await renderDocumentation(
      fileName: "MyTutorialOverview.tutorial",
      project: project,
      expectedResponses: [
        "1️⃣": .renderNode(kind: .overview, containing: "These tutorials will help you understand MyLibrary")
      ]
    )
  }
}

fileprivate enum PartialConvertResponse {
  case renderNode(kind: RenderNode.Kind, path: String? = nil, containing: String? = nil)
  case error(DoccDocumentationError)
}

fileprivate func renderDocumentation(
  fileName: String,
  project: SwiftPMTestProject,
  expectedResponses: [String: PartialConvertResponse],
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let (uri, positions) = try project.openDocument(fileName)

  await renderDocumentation(
    testClient: project.testClient,
    uri: uri,
    positions: positions,
    expectedResponses: expectedResponses,
    file: file,
    line: line
  )
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
    do {
      let response = try await testClient.send(
        DoccDocumentationRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: positions[marker]
        )
      )
      let renderNodeString = response.renderNode
      guard let renderNodeData = renderNodeString.data(using: .utf8),
        let renderNode = try? JSONDecoder().decode(RenderNode.self, from: renderNodeData)
      else {
        XCTFail("failed to decode response from \(DoccDocumentationRequest.method) at position \(marker)")
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
        if let expectedPath {
          XCTAssertEqual(
            renderNode.identifier.path,
            "/documentation/\(expectedPath)",
            "render node path did not match expected value at position \(marker)",
            file: file,
            line: line
          )
        }
        if let expectedContents {
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
    } catch {
      switch expectedResponse {
      case .renderNode:
        XCTFail(
          "\(DoccDocumentationRequest.method) failed at position \(marker): \(error.message)",
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
