//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import IndexStoreDB
import LSPLogging
import LanguageServerProtocol
import SwiftSyntax

public enum TestStyle {
  public static let xcTest = "XCTest"
  public static let swiftTesting = "swift-testing"
}

fileprivate extension SymbolOccurrence {
  /// Assuming that this is a symbol occurrence returned by the index, return whether it can constitute the definition
  /// of a test case.
  ///
  /// The primary intention for this is to filter out references to test cases and extension declarations of test cases.
  /// The latter is important to filter so we don't include extension declarations for the derived `DiscoveredTests`
  /// files on non-Darwin platforms.
  var canBeTestDefinition: Bool {
    guard roles.contains(.definition) else {
      return false
    }
    guard symbol.kind == .class || symbol.kind == .instanceMethod else {
      return false
    }
    return true
  }
}

/// Find the innermost range of a document symbol that contains the given position.
private func findInnermostSymbolRange(
  containing position: Position,
  documentSymbols documentSymbolsResponse: DocumentSymbolResponse
) -> Range<Position>? {
  guard case .documentSymbols(let documentSymbols) = documentSymbolsResponse else {
    // Both `ClangLanguageService` and `SwiftLanguageService` return `documentSymbols` so we don't need to handle the
    // .symbolInformation case.
    logger.fault(
      """
      Expected documentSymbols response from language service to resolve test ranges but got \
      \(documentSymbolsResponse.forLogging)
      """
    )
    return nil
  }
  for documentSymbol in documentSymbols where documentSymbol.range.contains(position) {
    if let children = documentSymbol.children,
      let rangeOfChild = findInnermostSymbolRange(containing: position, documentSymbols: .documentSymbols(children))
    {
      // If a child contains the position, prefer that because it's more specific.
      return rangeOfChild
    }
    return documentSymbol.range
  }
  return nil
}

extension SourceKitLSPServer {
  /// Converts a flat list of test symbol occurrences to a hierarchical `TestItem` array, inferring the hierarchical
  /// structure from `childOf` relations between the symbol occurrences.
  ///
  /// `resolvePositions` resolves the position of a test to a `Location` that is effectively a range. This allows us to
  /// provide ranges for the test cases in source code instead of only the test's location that we get from the index.
  private func testItems(
    for testSymbolOccurrences: [SymbolOccurrence],
    resolveLocation: (DocumentURI, Position) -> Location
  ) -> [TestItem] {
    // Arrange tests by the USR they are contained in. This allows us to emit test methods as children of test classes.
    // `occurrencesByParent[nil]` are the root test symbols that aren't a child of another test symbol.
    var occurrencesByParent: [String?: [SymbolOccurrence]] = [:]

    let testSymbolUsrs = Set(testSymbolOccurrences.map(\.symbol.usr))

    for testSymbolOccurrence in testSymbolOccurrences {
      let childOfUsrs = testSymbolOccurrence.relations
        .filter { $0.roles.contains(.childOf) }
        .map(\.symbol.usr)
        .filter { testSymbolUsrs.contains($0) }
      if childOfUsrs.count > 1 {
        logger.fault(
          "Test symbol \(testSymbolOccurrence.symbol.usr) is child or multiple symbols: \(childOfUsrs.joined(separator: ", "))"
        )
      }
      occurrencesByParent[childOfUsrs.sorted().first, default: []].append(testSymbolOccurrence)
    }

    /// Returns a test item for the given `testSymbolOccurrence`.
    ///
    /// Also includes test items for all tests that are children of this test.
    ///
    /// `context` is used to build the test's ID. It is an array containing the names of all parent symbols. These will
    /// be joined with the test symbol's name using `/` to form the test ID. The test ID can be used to run an
    /// individual test.
    func testItem(
      for testSymbolOccurrence: SymbolOccurrence,
      documentManager: DocumentManager,
      context: [String]
    ) -> TestItem {
      let symbolPosition: Position
      if let snapshot = try? documentManager.latestSnapshot(
        testSymbolOccurrence.location.documentUri
      ) {
        symbolPosition = snapshot.position(of: testSymbolOccurrence.location)
      } else {
        // Technically, we always need to convert UTF-8 columns to UTF-16 columns, which requires reading the file.
        // In practice, they are almost always the same.
        // We chose to avoid hitting the file system even if it means that we might report an incorrect column.
        symbolPosition = Position(
          line: testSymbolOccurrence.location.line - 1,  // 1-based -> 0-based
          utf16index: testSymbolOccurrence.location.utf8Column - 1
        )
      }
      let id = (context + [testSymbolOccurrence.symbol.name]).joined(separator: "/")
      let location = resolveLocation(testSymbolOccurrence.location.documentUri, symbolPosition)

      let children =
        occurrencesByParent[testSymbolOccurrence.symbol.usr, default: []]
        .sorted()
        .map {
          testItem(for: $0, documentManager: documentManager, context: context + [testSymbolOccurrence.symbol.name])
        }
      return TestItem(
        id: id,
        label: testSymbolOccurrence.symbol.name,
        disabled: false,
        style: TestStyle.xcTest,
        location: location,
        children: children,
        tags: []
      )
    }

    return occurrencesByParent[nil, default: []]
      .sorted()
      .map { testItem(for: $0, documentManager: documentManager, context: []) }
  }

  /// Return all the tests in the given workspace.
  ///
  /// This merges tests from the semantic index, the syntactic index and in-memory file states.
  ///
  /// The returned list of tests is not sorted. It should be sorted before being returned to the editor.
  private func tests(in workspace: Workspace) async -> [TestItem] {
    // Gather all tests classes and test methods. We include test from different sources:
    //  - For all files that have been not been modified since they were last indexed in the semantic index, include
    //    XCTests from the semantic index.
    //  - For all files that have been modified since the last semantic index but that don't have any in-memory
    //    modifications (ie. modifications that the user has made in the editor but not saved), include XCTests from
    //    the syntactic test index
    //  - For all files that don't have any in-memory modifications, include swift-testing tests from the syntactic test
    //    index.
    //  - All files that have in-memory modifications are syntactically scanned for tests here.
    let index = workspace.index(checkedFor: .inMemoryModifiedFiles(documentManager))

    let filesWithInMemoryState = documentManager.documents.keys.filter { uri in
      guard let url = uri.fileURL else {
        return true
      }
      // Use the index to check for in-memory modifications so we can re-use its cache. If no index exits, ask the
      // document manager directly.
      return index?.fileHasInMemoryModifications(url) ?? documentManager.fileHasInMemoryModifications(url)
    }

    let testsFromFilesWithInMemoryState = await filesWithInMemoryState.concurrentMap { (uri) -> [TestItem] in
      guard let languageService = workspace.documentService[uri] else {
        return []
      }
      return await orLog("Getting document tests for \(uri)") {
        try await self.documentTests(
          DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)),
          workspace: workspace,
          languageService: languageService
        )
      } ?? []
    }.flatMap { $0 }

    let semanticTestSymbolOccurrences = index?.unitTests().filter { return $0.canBeTestDefinition } ?? []

    let testsFromSyntacticIndex = await workspace.syntacticTestIndex.tests()
    let testsFromSemanticIndex = testItems(
      for: semanticTestSymbolOccurrences,
      resolveLocation: { uri, position in Location(uri: uri, range: Range(position)) }
    )
    let filesWithTestsFromSemanticIndex = Set(testsFromSemanticIndex.map(\.location.uri))

    let syntacticTestsToInclude =
      testsFromSyntacticIndex
      .filter { testItem in
        if testItem.style == TestStyle.swiftTesting {
          // Swift-testing tests aren't part of the semantic index. Always include them.
          return true
        }
        if filesWithTestsFromSemanticIndex.contains(testItem.location.uri) {
          // If we have an semantic tests from this file, then the semantic index is up-to-date for this file. We thus
          // don't need to include results from the syntactic index.
          return false
        }
        if filesWithInMemoryState.contains(testItem.location.uri) {
          // If the file has been modified in the editor, the syntactic index (which indexes on-disk files) is no longer
          // up-to-date. Include the tests from `testsFromFilesWithInMemoryState`.
          return false
        }
        if let fileUrl = testItem.location.uri.fileURL, index?.hasUpToDateUnit(for: fileUrl) ?? false {
          // We don't have a test for this file in the semantic index but an up-to-date unit file. This means that the
          // index is up-to-date and has more knowledge that identifies a `TestItem` as not actually being a test, eg.
          // because it starts with `test` but doesn't appear in a class inheriting from `XCTestCase`.
          return false
        }
        return true
      }

    // We don't need to sort the tests here because they will get
    return testsFromSemanticIndex + syntacticTestsToInclude + testsFromFilesWithInMemoryState
  }

  func workspaceTests(_ req: WorkspaceTestsRequest) async throws -> [TestItem] {
    return await self.workspaces
      .concurrentMap { await self.tests(in: $0) }
      .flatMap { $0 }
      .sorted { $0.location < $1.location }
  }

  /// Extracts a flat dictionary mapping test IDs to their locations from the given `testItems`.
  private func testLocations(from testItems: [TestItem]) -> [String: Location] {
    var result: [String: Location] = [:]
    for testItem in testItems {
      result[testItem.id] = testItem.location
      result.merge(testLocations(from: testItem.children)) { old, new in new }
    }
    return result
  }

  func documentTests(
    _ req: DocumentTestsRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [TestItem] {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let mainFileUri = await workspace.buildSystemManager.mainFile(
      for: req.textDocument.uri,
      language: snapshot.language
    )

    let syntacticTests = try await languageService.syntacticDocumentTests(for: req.textDocument.uri)

    if let index = workspace.index(checkedFor: .inMemoryModifiedFiles(documentManager)) {
      var syntacticSwiftTestingTests: [TestItem] {
        syntacticTests.filter { $0.style == TestStyle.swiftTesting }
      }

      let testSymbols =
        index.unitTests(referencedByMainFiles: [mainFileUri.pseudoPath])
        .filter { $0.canBeTestDefinition }

      if !testSymbols.isEmpty {
        let documentSymbols = await orLog("Getting document symbols for test ranges") {
          try await languageService.documentSymbol(DocumentSymbolRequest(textDocument: req.textDocument))
        }

        // We have test symbols from the semantic index. Return them but also include the syntactically discovered
        // swift-testing tests, which aren't part of the semantic index.
        return testItems(
          for: testSymbols,
          resolveLocation: { uri, position in
            if uri == snapshot.uri, let documentSymbols,
              let range = findInnermostSymbolRange(containing: position, documentSymbols: documentSymbols)
            {
              return Location(uri: uri, range: range)
            }
            return Location(uri: uri, range: Range(position))
          }
        ) + syntacticSwiftTestingTests
      }
      if let fileURL = mainFileUri.fileURL, index.hasUpToDateUnit(for: fileURL) {
        // The semantic index is up-to-date and doesn't contain any tests. We don't need to do a syntactic fallback for
        // XCTest. We do still need to return swift-testing tests which don't have a semantic index.
        return syntacticSwiftTestingTests
      }
    }
    // We don't have any up-to-date semantic index entries for this file. Syntactically look for tests.
    return syntacticTests
  }
}

/// Scans a source file for `XCTestCase` classes and test methods.
///
/// The syntax visitor scans from class and extension declarations that could be `XCTestCase` classes or extensions
/// thereof. It then calls into `findTestMethods` to find the actual test methods.
final class SyntacticSwiftXCTestScanner: SyntaxVisitor {
  /// The document snapshot of the syntax tree that is being walked.
  private var snapshot: DocumentSnapshot

  /// The workspace symbols representing the found `XCTestCase` subclasses and test methods.
  private var result: [TestItem] = []

  private init(snapshot: DocumentSnapshot) {
    self.snapshot = snapshot
    super.init(viewMode: .fixedUp)
  }

  public static func findTestSymbols(
    in snapshot: DocumentSnapshot,
    syntaxTreeManager: SyntaxTreeManager
  ) async -> [TestItem] {
    guard snapshot.text.contains("XCTestCase") || snapshot.text.contains("test") else {
      // If the file contains tests that can be discovered syntactically, it needs to have a class inheriting from
      // `XCTestCase` or a function starting with `test`.
      // This is intended to filter out files that obviously do not contain tests.
      return []
    }
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let visitor = SyntacticSwiftXCTestScanner(snapshot: snapshot)
    visitor.walk(syntaxTree)
    return visitor.result
  }

  private func findTestMethods(in members: MemberBlockItemListSyntax, containerName: String) -> [TestItem] {
    return members.compactMap { (member) -> TestItem? in
      guard let function = member.decl.as(FunctionDeclSyntax.self) else {
        return nil
      }
      guard function.name.text.starts(with: "test") else {
        return nil
      }
      guard function.modifiers.map(\.name.tokenKind).allSatisfy({ $0 != .keyword(.static) && $0 != .keyword(.class) })
      else {
        // Test methods can't be static.
        return nil
      }
      guard function.signature.returnClause == nil, function.signature.parameterClause.parameters.isEmpty else {
        // Test methods can't have a return type or have parameters.
        // Technically we are also filtering out functions that have an explicit `Void` return type here but such
        // declarations are probably less common than helper functions that start with `test` and have a return type.
        return nil
      }
      let range = snapshot.range(
        of: function.positionAfterSkippingLeadingTrivia..<function.endPositionBeforeTrailingTrivia
      )

      return TestItem(
        id: "\(containerName)/\(function.name.text)()",
        label: "\(function.name.text)()",
        disabled: false,
        style: TestStyle.xcTest,
        location: Location(uri: snapshot.uri, range: range),
        children: [],
        tags: []
      )
    }
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    guard let inheritedTypes = node.inheritanceClause?.inheritedTypes, let superclass = inheritedTypes.first else {
      // The class has no superclass and thus can't inherit from XCTestCase.
      // Continue scanning its children in case it has a nested subclass that inherits from XCTestCase.
      return .visitChildren
    }
    let superclassName = superclass.type.as(IdentifierTypeSyntax.self)?.name.text
    if superclassName == "NSObject" {
      // We know that the class can't be an subclass of `XCTestCase` so don't visit it.
      // We can't explicitly check for the `XCTestCase` superclass because the class might inherit from a class that in
      // turn inherits from `XCTestCase`. Resolving that inheritance hierarchy would be semantic.
      return .visitChildren
    }
    let testMethods = findTestMethods(in: node.memberBlock.members, containerName: node.name.text)
    guard !testMethods.isEmpty || superclassName == "XCTestCase" else {
      // Don't report a test class if it doesn't contain any test methods.
      return .visitChildren
    }
    let range = snapshot.range(of: node.positionAfterSkippingLeadingTrivia..<node.endPositionBeforeTrailingTrivia)
    let testItem = TestItem(
      id: node.name.text,
      label: node.name.text,
      disabled: false,
      style: TestStyle.xcTest,
      location: Location(uri: snapshot.uri, range: range),
      children: testMethods,
      tags: []
    )
    result.append(testItem)
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    result += findTestMethods(in: node.memberBlock.members, containerName: node.extendedType.trimmedDescription)
    return .visitChildren
  }
}

extension SwiftLanguageService {
  public func syntacticDocumentTests(for uri: DocumentURI) async throws -> [TestItem] {
    let snapshot = try documentManager.latestSnapshot(uri)
    let xctestSymbols = await SyntacticSwiftXCTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    let swiftTestingSymbols = await SyntacticSwiftTestingTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    return (xctestSymbols + swiftTestingSymbols).sorted { $0.location < $1.location }
  }
}

extension ClangLanguageService {
  public func syntacticDocumentTests(for uri: DocumentURI) async -> [TestItem] {
    return []
  }
}
