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

final class DocumentationDefinitionTests: SourceKitLSPTestCase {

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

  func testDefinitionIsNilWhenNotOnSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct Foo {}

      /// This 1️⃣comment has no symbol link.
      public func useFoo() {}
      """
    )

    await assertThrowsError(
      try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
      )
    )
  }

  func testDefinitionIsNilForUnresolvedSymbolLink() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      /// See ``1️⃣DoesNotExist``
      public func useFoo() {}
      """
    )

    await assertThrowsError(
      try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(project.fileURI), position: project.positions["1️⃣"])
      )
    )
  }
}
