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
import SemanticIndex
import SwiftSyntax

public enum TestStyle {
  public static let xcTest = "XCTest"
  public static let swiftTesting = "swift-testing"
}

public struct AnnotatedTestItem: Sendable {
  /// The test item to be annotated
  public var testItem: TestItem

  /// Whether the `TestItem` is an extension.
  public var isExtension: Bool

  public init(
    testItem: TestItem,
    isExtension: Bool
  ) {
    self.testItem = testItem
    self.isExtension = isExtension
  }
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
  documentSymbolsResponse: DocumentSymbolResponse
) -> Range<Position>? {
  switch documentSymbolsResponse {
  case .documentSymbols(let documentSymbols):
    return findInnermostSymbolRange(containing: position, documentSymbols: documentSymbols)
  case .symbolInformation(let symbolInformation):
    return findInnermostSymbolRange(containing: position, symbolInformation: symbolInformation)
  }
}

private func findInnermostSymbolRange(
  containing position: Position,
  documentSymbols: [DocumentSymbol]
) -> Range<Position>? {
  for documentSymbol in documentSymbols where documentSymbol.range.contains(position) {
    if let children = documentSymbol.children,
      let rangeOfChild = findInnermostSymbolRange(
        containing: position,
        documentSymbolsResponse: .documentSymbols(children)
      )
    {
      // If a child contains the position, prefer that because it's more specific.
      return rangeOfChild
    }
    return documentSymbol.range
  }
  return nil
}

/// Return the smallest range in `symbolInformation` containing `position`.
private func findInnermostSymbolRange(
  containing position: Position,
  symbolInformation symbolInformationArray: [SymbolInformation]
) -> Range<Position>? {
  var bestRange: Range<Position>? = nil
  for symbolInformation in symbolInformationArray where symbolInformation.location.range.contains(position) {
    let range = symbolInformation.location.range
    if bestRange == nil || (bestRange!.lowerBound < range.lowerBound && range.upperBound < bestRange!.upperBound) {
      bestRange = range
    }
  }
  return bestRange
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
  ) -> [AnnotatedTestItem] {
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
    ) -> AnnotatedTestItem {
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
      return AnnotatedTestItem(
        testItem: TestItem(
          id: id,
          label: testSymbolOccurrence.symbol.name,
          disabled: false,
          style: TestStyle.xcTest,
          location: location,
          children: children.map(\.testItem),
          tags: []
        ),
        isExtension: false
      )
    }

    let documentManager = self.documentManager
    return occurrencesByParent[nil, default: []]
      .sorted()
      .map { testItem(for: $0, documentManager: documentManager, context: []) }
  }

  /// Return all the tests in the given workspace.
  ///
  /// This merges tests from the semantic index, the syntactic index and in-memory file states.
  ///
  /// The returned list of tests is not sorted. It should be sorted before being returned to the editor.
  private func tests(in workspace: Workspace) async -> [AnnotatedTestItem] {
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

    let testsFromFilesWithInMemoryState = await filesWithInMemoryState.concurrentMap { (uri) -> [AnnotatedTestItem] in
      guard let languageService = workspace.documentService.value[uri] else {
        return []
      }
      return await orLog("Getting document tests for \(uri)") {
        try await self.documentTestsWithoutMergingExtensions(
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
    let filesWithTestsFromSemanticIndex = Set(testsFromSemanticIndex.map(\.testItem.location.uri))

    let indexOnlyDiscardingDeletedFiles = workspace.index(checkedFor: .deletedFiles)

    let syntacticTestsToInclude =
      testsFromSyntacticIndex
      .compactMap { (item) -> AnnotatedTestItem? in
        let testItem = item.testItem
        if testItem.style == TestStyle.swiftTesting {
          // Swift-testing tests aren't part of the semantic index. Always include them.
          return item
        }
        if filesWithTestsFromSemanticIndex.contains(testItem.location.uri) {
          // If we have an semantic tests from this file, then the semantic index is up-to-date for this file. We thus
          // don't need to include results from the syntactic index.
          return nil
        }
        if filesWithInMemoryState.contains(testItem.location.uri) {
          // If the file has been modified in the editor, the syntactic index (which indexes on-disk files) is no longer
          // up-to-date. Include the tests from `testsFromFilesWithInMemoryState`.
          return nil
        }
        if let fileUrl = testItem.location.uri.fileURL, index?.hasUpToDateUnit(for: fileUrl) ?? false {
          // We don't have a test for this file in the semantic index but an up-to-date unit file. This means that the
          // index is up-to-date and has more knowledge that identifies a `TestItem` as not actually being a test, eg.
          // because it starts with `test` but doesn't appear in a class inheriting from `XCTestCase`.
          return nil
        }
        // Filter out any test items that we know aren't actually tests based on the semantic index.
        // This might call `symbols(inFilePath:)` multiple times if there are multiple top-level test items (ie.
        // XCTestCase subclasses, swift-testing handled above) for the same file. In practice test files usually contain
        // a single XCTestCase subclass, so caching doesn't make sense here.
        // Also, this is only called for files containing test cases but for which the semantic index is out-of-date.
        if let filtered = testItem.filterUsing(
          semanticSymbols: indexOnlyDiscardingDeletedFiles?.symbols(inFilePath: testItem.location.uri.pseudoPath)
        ) {
          return AnnotatedTestItem(testItem: filtered, isExtension: item.isExtension)
        }
        return nil
      }

    // We don't need to sort the tests here because they will get
    return testsFromSemanticIndex + syntacticTestsToInclude + testsFromFilesWithInMemoryState
  }

  func workspaceTests(_ req: WorkspaceTestsRequest) async throws -> [TestItem] {
    return await self.workspaces
      .concurrentMap { await self.tests(in: $0) }
      .flatMap { $0 }
      .sorted { $0.testItem.location < $1.testItem.location }
      .mergingTestsInExtensions()
  }

  func documentTests(
    _ req: DocumentTestsRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [TestItem] {
    return try await documentTestsWithoutMergingExtensions(req, workspace: workspace, languageService: languageService)
      .mergingTestsInExtensions()
  }

  private func documentTestsWithoutMergingExtensions(
    _ req: DocumentTestsRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [AnnotatedTestItem] {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let mainFileUri = await workspace.buildSystemManager.mainFile(
      for: req.textDocument.uri,
      language: snapshot.language
    )

    let syntacticTests = try await languageService.syntacticDocumentTests(for: req.textDocument.uri, in: workspace)

    // We `syntacticDocumentTests` returns `nil`, it indicates that it doesn't support syntactic test discovery.
    // In that case, the semantic index is the only source of tests we have and we thus want to show tests from the
    // semantic index, even if they are out-of-date. The alternative would be showing now tests after an edit to a file.
    let indexCheckLevel: IndexCheckLevel =
      syntacticTests == nil ? .deletedFiles : .inMemoryModifiedFiles(documentManager)

    if let index = workspace.index(checkedFor: indexCheckLevel) {
      var syntacticSwiftTestingTests: [AnnotatedTestItem] {
        syntacticTests?.filter { $0.testItem.style == TestStyle.swiftTesting } ?? []
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
              let range = findInnermostSymbolRange(containing: position, documentSymbolsResponse: documentSymbols)
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
    return syntacticTests ?? []
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
  private var result: [AnnotatedTestItem] = []

  private init(snapshot: DocumentSnapshot) {
    self.snapshot = snapshot
    super.init(viewMode: .fixedUp)
  }

  public static func findTestSymbols(
    in snapshot: DocumentSnapshot,
    syntaxTreeManager: SyntaxTreeManager
  ) async -> [AnnotatedTestItem] {
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
    let testItem = AnnotatedTestItem(
      testItem: TestItem(
        id: node.name.text,
        label: node.name.text,
        disabled: false,
        style: TestStyle.xcTest,
        location: Location(uri: snapshot.uri, range: range),
        children: testMethods,
        tags: []
      ),
      isExtension: false
    )
    result.append(testItem)
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    result += findTestMethods(in: node.memberBlock.members, containerName: node.extendedType.trimmedDescription)
      .map { AnnotatedTestItem(testItem: $0, isExtension: true) }
    return .visitChildren
  }
}

extension TestItem {
  /// Use out-of-date semantic information to filter syntactic symbols.
  ///
  /// If the syntactic index found a test item, check if the semantic index knows about a symbol with that name. If it
  /// does and that item is not marked as a test symbol, we can reasonably assume that this item still looks like a test
  /// but is semantically known to not be a test. It will thus get filtered out.
  ///
  /// `semanticSymbols` should be all the symbols in the source file that this `TestItem` occurs in, retrieved using
  /// `symbols(inFilePath:)` from the index.
  fileprivate func filterUsing(semanticSymbols: [Symbol]?) -> TestItem? {
    guard let semanticSymbols else {
      return self
    }
    // We only check if we know of any symbol with the test item's name in this file. We could try to incorporate
    // structure here (ie. look for a method within a class) but that makes the index lookup more difficult and in
    // practice it is very unlikely that a test file will have two symbols with the same name, one of which is marked
    // as a unit test while the other one is not.
    let semanticSymbolsWithName = semanticSymbols.filter { $0.name == self.label }
    if !semanticSymbolsWithName.isEmpty,
      semanticSymbolsWithName.allSatisfy({ !$0.properties.contains(.unitTest) })
    {
      return nil
    }
    var test = self
    test.children = test.children.compactMap { $0.filterUsing(semanticSymbols: semanticSymbols) }
    return test
  }
}

extension AnnotatedTestItem {
  /// Use out-of-date semantic information to filter syntactic symbols.
  ///
  /// Delegates to the `TestItem`'s `filterUsing(semanticSymbols:)` method to perform the filtering.
  fileprivate func filterUsing(semanticSymbols: [Symbol]?) -> AnnotatedTestItem? {
    guard let testItem = self.testItem.filterUsing(semanticSymbols: semanticSymbols) else {
      return nil
    }
    var test = self
    test.testItem = testItem
    return test
  }
}

extension Array<AnnotatedTestItem> {
  /// When the test scanners discover tests in extensions they are captured in their own parent `TestItem`, not the
  /// `TestItem` generated from the class/struct's definition. This is largely because of the syntatic nature of the
  /// test scanners as they are today, which only know about tests within the context of the current file. Extensions
  /// defined in separate files must be organized in their own `TestItem` since at the time of their creation there
  /// isn't enough information to connect them back to the tests defined in the main type definition.
  ///
  /// This is a more syntatic than semantic view of the `TestItem` hierarchy than the end user likely wants.
  /// If we think of the enclosing class or struct as the test suite, then extensions on that class or struct should be
  /// additions to that suite, just like extensions on types are, from the user's perspective, transparently added to
  /// their type.
  ///
  /// This method walks the `AnnotatedTestItem` tree produced by the test scanners and merges in the tests defined in
  /// extensions into the final `TestItem`s that represent the type definition.
  ///
  /// This causes extensions to be merged into their type's definition if the type's definition exists in the list of
  /// test items. If the type's definition is not a test item in this collection, the first extension of that type will
  /// be used as the primary test location.
  ///
  /// For example if there are two files
  ///
  /// FileA.swift
  /// ```swift
  /// @Suite struct MyTests {
  ///   @Test func oneIsTwo {}
  /// }
  /// ```
  ///
  /// FileB.swift
  /// ```swift
  /// extension MyTests {
  ///   @Test func twoIsThree() {}
  /// }
  /// ```
  ///
  /// Then `workspace/tests` will return
  /// - `MyTests` (FileA.swift:1)
  ///   - `oneIsTwo`
  ///   - `twoIsThree`
  ///
  /// And `textDocument/tests` for FileB.swift will return
  /// - `MyTests` (FileB.swift:1)
  ///   - `twoIsThree`
  ///
  /// A node's parent is identified by the node's ID with the last component dropped.
  func mergingTestsInExtensions() -> [TestItem] {
    var itemDict: [String: AnnotatedTestItem] = [:]
    for item in self {
      let id = item.testItem.id
      if var rootItem = itemDict[id] {
        // If we've encountered an extension first, and this is the
        // type declaration, then use the type declaration TestItem
        // as the root item.
        if rootItem.isExtension && !item.isExtension {
          var newItem = item
          newItem.testItem.children += rootItem.testItem.children
          rootItem = newItem
        } else {
          rootItem.testItem.children += item.testItem.children
        }

        itemDict[id] = rootItem
      } else {
        itemDict[id] = item
      }
    }

    if itemDict.isEmpty {
      return []
    }

    var mergedIds = Set<String>()
    for item in self {
      let id = item.testItem.id
      let parentID = id.components(separatedBy: "/").dropLast().joined(separator: "/")
      // If the parent exists, add the current item to its children and remove it from the root
      if var parent = itemDict[parentID] {
        parent.testItem.children.append(item.testItem)
        mergedIds.insert(parent.testItem.id)
        itemDict[parent.testItem.id] = parent
        itemDict[id] = nil
      }
    }

    // Sort the tests by location, prioritizing TestItems not in extensions.
    let sortedItems = itemDict.values
      .sorted { ($0.isExtension != $1.isExtension) ? !$0.isExtension : ($0.testItem.location < $1.testItem.location) }

    let result = sortedItems.map {
      guard !$0.testItem.children.isEmpty, mergedIds.contains($0.testItem.id) else {
        return $0.testItem
      }
      var newItem = $0.testItem
      newItem.children = newItem.children
        .map { AnnotatedTestItem(testItem: $0, isExtension: false) }
        .mergingTestsInExtensions()
      return newItem
    }
    return result
  }
}

extension SwiftLanguageService {
  public func syntacticDocumentTests(
    for uri: DocumentURI,
    in workspace: Workspace
  ) async throws -> [AnnotatedTestItem]? {
    let snapshot = try documentManager.latestSnapshot(uri)
    let semanticSymbols = workspace.index(checkedFor: .deletedFiles)?.symbols(inFilePath: snapshot.uri.pseudoPath)
    let xctestSymbols = await SyntacticSwiftXCTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    .compactMap { $0.filterUsing(semanticSymbols: semanticSymbols) }

    let swiftTestingSymbols = await SyntacticSwiftTestingTestScanner.findTestSymbols(
      in: snapshot,
      syntaxTreeManager: syntaxTreeManager
    )
    return (xctestSymbols + swiftTestingSymbols).sorted { $0.testItem.location < $1.testItem.location }
  }
}

extension ClangLanguageService {
  public func syntacticDocumentTests(for uri: DocumentURI, in workspace: Workspace) async -> [AnnotatedTestItem]? {
    return nil
  }
}
