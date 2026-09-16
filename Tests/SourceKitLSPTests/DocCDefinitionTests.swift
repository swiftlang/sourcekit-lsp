//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import XCTest

final class DocCDefinitionTests: XCTestCase {

  // MARK: Line comments (`///`)

  func testJumpToDefinitionFromLineCommentSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct 1️⃣Foo {}

      /// See ``2️⃣Foo``
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  /// Two `///` comment groups separated by a blank line are parsed as two separate
  /// `DocTriviaGroup.lines` groups. Clicking in the second group should still resolve,
  /// unaffected by the unrelated first group.
  func testJumpToDefinitionIgnoresUnrelatedLineCommentGroup() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct 1️⃣Foo {}
      public struct Bar {}

      /// Unrelated comment mentioning ``Bar``, detached by a blank line below.

      /// See ``2️⃣Foo`` here instead.
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  // MARK: Block comments (`/** ... */`)

  func testJumpToDefinitionFromBlockCommentSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct 1️⃣Foo {}

      /**
       See ``2️⃣Foo`` for more information.
       */
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  /// Symbol link on the same line as the opening `/**`.
  func testJumpToDefinitionFromSingleLineBlockCommentSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct 1️⃣Foo {}

      /** See ``2️⃣Foo`` for more information. */
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  // MARK: Nested / multi-component links (``Foo/bar()``)

  /// Clicking the parent component of a nested link resolves to the parent symbol.
  func testJumpToDefinitionFromNestedSymbolLinkParentComponent() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct 1️⃣Foo {
        public func bar() {}
      }

      /// See ``2️⃣Foo/bar()``
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  /// Clicking the child component of a nested link resolves to the child symbol.
  func testJumpToDefinitionFromNestedSymbolLinkChildComponent() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {
        public func 1️⃣bar() {}
      }
      public struct Link {
        public func bar() {}
      }

      /// See ``Foo/2️⃣bar()``
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  // MARK: Negative cases

  func testJumpToDefinitionIsNilWhenNotOnSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {}

      /// This 1️⃣comment has no symbol link.
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
    )
    XCTAssertNil(response)
  }

  func testJumpToDefinitionIsNilForUnresolvedSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      /// See ``1️⃣DoesNotExist``
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
    )
    XCTAssertNil(response)
  }

  /// The cursor sitting in a plain (non-doc) comment should not be treated as a doc-comment
  /// symbol link at all.
  func testJumpToDefinitionIsNilInNonDocComment() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {}

      // This is a regular comment mentioning 1️⃣Foo, not a doc comment.
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
    )
    XCTAssertNil(response)
  }

  /// Invoking the action somewhere that isn't a symbol link at all (e.g. plain code, not
  /// inside any comment) should return nil.
  func testJumpToDefinitionIsNilWhenNotOnAnySymbol() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {}

      public func 1️⃣ useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
    )
    XCTAssertNil(response)
  }

  // MARK: DocC catalog files (tutorials and markdown)

  func testJumpToDefinitionInDocCTutorialFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyFile.swift": """
        public struct 1️⃣Foo {}
        """,
        "MyLibrary/MyLibrary.docc/MyTutorial.tutorial": """
        @Tutorial(time: 30) {
          @Intro(title: "My Custom Tutorial") {
            See ``2️⃣Foo`` for more information.
          }
        }
        """,
      ],
      enableBackgroundIndexing: true
    )

    let (tutorialURI, tutorialPositions) = try project.openDocument("MyTutorial.tutorial")

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(tutorialURI), position: tutorialPositions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "MyFile.swift")])
    )
  }

  func testJumpToDefinitionInDocCMarkdownFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/MyFile.swift": """
        public struct 1️⃣Foo {}
        """,
        "MyLibrary/MyLibrary.docc/Overview.md": """
        # Overview

        See ``2️⃣Foo`` for more information.
        """,
      ],
      enableBackgroundIndexing: true
    )

    let (overviewURI, overviewPositions) = try project.openDocument("Overview.md")

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(overviewURI), position: overviewPositions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "MyFile.swift")])
    )
  }

  // MARK: Cross-file / cross-module

  /// The doc comment lives in one file, the symbol it links to is defined in another file
  /// (same target).
  func testJumpToDefinitionAcrossFilesInSameModule() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/Foo.swift": """
        public struct 1️⃣Foo {}
        """,
        "MyLibrary/Bar.swift": """
        /// See ``2️⃣Foo``
        public func useFoo() {}
        """,
      ],
      enableBackgroundIndexing: true
    )

    let (barURI, barPositions) = try project.openDocument("Bar.swift")

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(barURI), position: barPositions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "Foo.swift")])
    )
  }

  /// The doc comment lives in one target, the symbol it links to is defined in a different
  /// target that the first one depends on.
  func testJumpToDefinitionAcrossModules() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "OtherLibrary/Foo.swift": """
        public struct 1️⃣Foo {}
        """,
        "MyLibrary/Bar.swift": """
        import OtherLibrary

        /// See ``2️⃣Foo``
        public func useFoo() {}
        """,
      ],
      manifest: """
        // swift-tools-version: 5.10

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(name: "OtherLibrary"),
            .target(name: "MyLibrary", dependencies: ["OtherLibrary"]),
          ]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (barURI, barPositions) = try project.openDocument("Bar.swift")

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(barURI), position: barPositions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([try project.location(from: "1️⃣", to: "1️⃣", in: "Foo.swift")])
    )
  }

  // MARK: Overload disambiguation

  /// A symbol link that includes parameter/return disambiguation should resolve to the
  /// specific overload, not just the first symbol with a matching base name.
  func testJumpToDefinitionDisambiguatesOverloads() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {
       public func bar(x: Int) {}
        public func 1️⃣bar(x: String) {}
      }

      /// See ``Foo/2️⃣bar(x:)-(String)``
      public func useFoo() {}
      """
    )

    let response = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["2️⃣"])
    )
    XCTAssertEqual(
      response,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )
  }

  // MARK: Suffix disambiguation

  /// A symbol link using an explicit disambiguation suffix (e.g. a hash or kind suffix)
  /// should still resolve to the correct symbol.
  func testJumpToDefinitionResolvesKindDisambiguatedLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {
        public static var 1️⃣bar: Int = 0
        public var 2️⃣bar: Int = 0
      }

      /// See ``Foo/3️⃣bar-swift.type.property`` and ``Foo/4️⃣bar-swift.property``
      public func useFoo() {}
      """
    )

    let staticResponse = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["3️⃣"])
    )
    XCTAssertEqual(
      staticResponse,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))])
    )

    let instanceResponse = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["4️⃣"])
    )
    XCTAssertEqual(
      instanceResponse,
      .locations([Location(uri: project.fileURI, range: Range(project.positions["2️⃣"]))])
    )
  }
}
