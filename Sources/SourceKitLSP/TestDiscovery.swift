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

import BuildServerIntegration
import Foundation
package import IndexStoreDB
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

package enum TestStyle {
  package static let xcTest = "XCTest"
  package static let swiftTesting = "swift-testing"
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

struct TestDiscovery {
  let sourceKitLSPServer: SourceKitLSPServer

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
  }

  /// Converts a flat list of test symbol occurrences to a hierarchical `TestItem` array, inferring the hierarchical
  /// structure from `childOf` relations between the symbol occurrences.
  private func testItems(
    for testSymbolOccurrences: [SymbolOccurrence],
    index: CheckedIndex?
  ) -> [AnnotatedTestItem] {
    let testSymbolOccurrences = testSymbolOccurrences.filter { $0.canBeTestDefinition }

    // Arrange tests by the USR they are contained in. This allows us to emit test methods as children of test classes.
    // `occurrencesByParent[nil]` are the root test symbols that aren't a child of another test symbol.
    var occurrencesByParent: [String?: [SymbolOccurrence]] = [:]

    var testSymbolUsrs = Set(testSymbolOccurrences.map(\.symbol.usr))

    // Gather any extension declarations that contains tests and add them to `occurrencesByParent` so we can properly
    // arrange their test items as the extension's children.
    for testSymbolOccurrence in testSymbolOccurrences {
      for parentSymbol in testSymbolOccurrence.relations.filter({ $0.roles.contains(.childOf) }).map(\.symbol) {
        guard parentSymbol.kind == .extension else {
          continue
        }
        guard let definition = index?.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentSymbol.usr) else {
          logger.fault("Unable to find primary definition of extension '\(parentSymbol.usr)' containing tests")
          continue
        }
        testSymbolUsrs.insert(parentSymbol.usr)
        occurrencesByParent[nil, default: []].append(definition)
      }
    }

    for testSymbolOccurrence in testSymbolOccurrences {
      let childOfUsrs = testSymbolOccurrence.relations
        .filter { $0.roles.contains(.childOf) }.map(\.symbol.usr).filter { testSymbolUsrs.contains($0) }
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
      context: [String]
    ) -> AnnotatedTestItem {
      let id = (context + [testSymbolOccurrence.symbol.name]).joined(separator: "/")

      // Technically, we always need to convert UTF-8 columns to UTF-16 columns, which requires reading the file.
      // In practice, they are almost always the same.
      // We chose to avoid hitting the file system even if it means that we might report an incorrect column.
      let position = Position(
        line: testSymbolOccurrence.location.line - 1,  // 1-based -> 0-based
        utf16index: testSymbolOccurrence.location.utf8Column - 1
      )
      let location = Location(
        uri: testSymbolOccurrence.location.documentUri,
        range: Range(position)
      )

      let children =
        occurrencesByParent[testSymbolOccurrence.symbol.usr, default: []]
        .sorted()
        .map {
          testItem(for: $0, context: context + [testSymbolOccurrence.symbol.name])
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
        isExtension: testSymbolOccurrence.symbol.kind == .extension
      )
    }

    return occurrencesByParent[nil, default: []]
      .sorted()
      .map { testItem(for: $0, context: []) }
  }

  /// Fix the 'location.range' of test cases from the semantic index using 'textDocument/symbol' results.
  private func fixSemanticTestRanges(
    tests: [AnnotatedTestItem],
    workspace: Workspace
  ) async -> [AnnotatedTestItem] {

    // Cached 'textDocument/symbol' result per document.
    var _documentSymbols: [DocumentURI: DocumentSymbolResponse?] = [:]
    func documentSymbols(in uri: DocumentURI) async throws -> DocumentSymbolResponse? {
      if let cached = _documentSymbols[uri] {
        return cached
      }
      guard let languageService = workspace.primaryLanguageService(for: uri) else {
        return nil
      }
      let symbols = try await languageService.documentSymbol(
        DocumentSymbolRequest(textDocument: TextDocumentIdentifier(uri))
      )
      _documentSymbols[uri] = symbols
      return symbols
    }

    // Recursively fix up 'TestItem.location.range'.
    func fixupLocation(item: inout TestItem, using documentSymbols: DocumentSymbolResponse) {
      let fixedRange = findInnermostSymbolRange(
        containing: item.location.range.lowerBound,
        documentSymbolsResponse: documentSymbols
      )
      if let fixedRange {
        item.location.range = fixedRange
      }
      for idx in item.children.indices {
        fixupLocation(item: &item.children[idx], using: documentSymbols)
      }
    }

    return await tests.asyncMap { (item) async -> AnnotatedTestItem in
      var item = item
      if let symbols = try? await documentSymbols(in: item.testItem.location.uri) {
        fixupLocation(item: &item.testItem, using: symbols)
      }
      return item
    }
  }

  /// Combine 'syntacticTests' and 'semanticTests'.
  ///
  ///  * Use 'syntacticTests' primarily
  ///  * Filter out known non-tests from 'syntacticTests' based on 'maybeOutdatedIndex'
  ///  * Use 'semanticTests' items only if it's not in 'syntacticTests'.
  private func combineTests(
    syntacticTests: [AnnotatedTestItem],
    semanticTests: [AnnotatedTestItem]?,
    maybeOutdatedIndex: CheckedIndex?,
    workspace: Workspace
  ) async -> [AnnotatedTestItem] {
    guard let semanticTests else {
      return syntacticTests
    }

    var semanticTestsMap = [String: [AnnotatedTestItem]](grouping: semanticTests, by: { $0.testItem.id })

    let syntacticTests = syntacticTests.compactMap { item in
      // swift-testing test cases are only discovered by syntactic scans.
      if item.testItem.style == TestStyle.swiftTesting {
        return item
      }

      // Drop the semantic test cases. We prefer syntactic TestItem instances because it holds the correct location ranges.
      semanticTestsMap[item.testItem.id] = nil

      // Filter out any test items that we know aren't actually tests based on the semantic index.
      // This might call `symbols(inFilePath:)` multiple times if there are multiple top-level test items (ie.
      // XCTestCase subclasses, swift-testing handled above) for the same file. In practice test files usually contain
      // a single XCTestCase subclass, so caching doesn't make sense here.
      // Also, this is only called for files containing test cases but for which the semantic index is out-of-date.
      return item.filterUsing(
        semanticSymbols: maybeOutdatedIndex?.symbols(inFilePath: item.testItem.location.uri.pseudoPath)
      )
    }

    // 'semanticTestsMap.values' now contains the results to include. Fix-up the range info.
    let semanticTestsFixed = await fixSemanticTestRanges(
      tests: semanticTestsMap.values.flatMap({ $0 }),
      workspace: workspace
    )

    return syntacticTests + semanticTestsFixed
  }

  /// Return all the tests in the given workspace.
  ///
  /// This merges tests from the semantic index, the syntactic index and in-memory file states.
  ///
  /// The returned list of tests is not sorted. It should be sorted before being returned to the editor.
  private func tests(in workspace: Workspace) async -> [AnnotatedTestItem] {
    // If files have recently been added to the workspace (which is communicated by a `workspace/didChangeWatchedFiles`
    // notification, wait these changes to be reflected in the build server so we can include the updated files in the
    // tests.
    await workspace.buildServerManager.waitForUpToDateBuildGraph()

    let documentManager = sourceKitLSPServer.documentManager

    var testFiles = (try? await workspace.buildServerManager.projectTestFiles()) ?? Array(documentManager.openDocuments)

    let index = await workspace.index(checkedFor: .inMemoryModifiedFiles(documentManager))
    let maybeOutdatedIndex = await workspace.index(checkedFor: .deletedFiles);

    // Collect syntactic tests from the syntactic index, or scan on-demand if the file has in-memory modifications.
    let partitionIdx = testFiles.partition(by: { uri in
      index?.fileHasInMemoryModifications(uri) ?? documentManager.fileHasInMemoryModifications(uri)
    })
    let filesInSyntacticIndex = testFiles[..<partitionIdx]
    let filesInMemory = testFiles[partitionIdx...]

    let testsFromSyntacticIndex = await workspace.syntacticIndex.tests(in: Array(filesInSyntacticIndex))
    var testsFromInMemoryScan: [AnnotatedTestItem] = []
    var filesToUseSemanticIndex: [DocumentURI] = []
    for uri in filesInMemory {
      guard let snapshot = try? documentManager.latestSnapshot(uri) else {
        continue
      }
      if let scannedTests = await workspace.primaryLanguageService(for: uri)?.syntacticTestItems(for: snapshot) {
        testsFromInMemoryScan += scannedTests
      } else {
        // When `syntacticTestItems` returns `nil`, it indicates that it doesn't support syntactic test discovery.
        // Fallback to semantic index even if it's outdated.
        filesToUseSemanticIndex.append(uri)
      }
    }

    // Collect tests from semantic index.
    var symbolOccurrences: [SymbolOccurrence] = []
    if let index, let maybeOutdatedIndex {
      // FIXME: Instead of querying two times, get all the symbolOccurences and filter them here.
      symbolOccurrences += index.unitTests()
      symbolOccurrences += maybeOutdatedIndex.unitTests(
        referencedByMainFiles: filesToUseSemanticIndex.map(\.pseudoPath)
      )
    }
    let testsFromSemanticIndex = testItems(
      for: symbolOccurrences,
      index: index
    )

    return await combineTests(
      syntacticTests: (testsFromSyntacticIndex + testsFromInMemoryScan),
      semanticTests: testsFromSemanticIndex,
      maybeOutdatedIndex: maybeOutdatedIndex,
      workspace: workspace
    )
  }

  /// Collect all test cases from all the workspaces and merge it into a sorted list of the test cases.
  func workspaceTests() async -> [TestItem] {
    return await self.sourceKitLSPServer.workspaces
      .concurrentMap {
        await self.tests(in: $0).prefixTestsWithModuleName(workspace: $0)
      }
      .flatMap({ $0 })
      .mergingTestsInExtensions()
      .sorted { $0.location < $1.location }
      .deduplicatingIds()
  }

  /// Collect test cases in a document.
  func documentTests(
    _ uri: DocumentURI,
    workspace: Workspace,
    languageService: any LanguageService
  ) async throws -> [TestItem] {
    return try await documentTestsWithoutMergingExtensions(uri, workspace: workspace, languageService: languageService)
      .prefixTestsWithModuleName(workspace: workspace)
      .mergingTestsInExtensions()
      .sorted { $0.location < $1.location }
      .deduplicatingIds()
  }

  private func documentTestsWithoutMergingExtensions(
    _ uri: DocumentURI,
    workspace: Workspace,
    languageService: any LanguageService
  ) async throws -> [AnnotatedTestItem] {
    let documentManager = sourceKitLSPServer.documentManager
    let snapshot = try documentManager.latestSnapshot(uri)
    let mainFileUri = await workspace.buildServerManager.mainFile(
      for: uri,
      language: snapshot.language
    )

    // If we know how to build the file and it's not part of a test target, don't bother to scan it.
    let sourceFileInfo = await workspace.buildServerManager.sourceFileInfo(for: mainFileUri)
    if let sourceFileInfo, !sourceFileInfo.mayContainTests {
      return []
    }

    let syntacticTests = await languageService.syntacticTestItems(for: snapshot)

    // When `syntacticTestItems` returns `nil`, it indicates that it doesn't support syntactic test discovery.
    // In that case, the semantic index is the only source of tests we have and we thus want to show tests from the
    // semantic index, even if they are out-of-date. The alternative would be showing no tests after an edit to a file.
    let indexCheckLevel: IndexCheckLevel =
      syntacticTests == nil ? .deletedFiles : .inMemoryModifiedFiles(documentManager)
    let index = await workspace.index(checkedFor: indexCheckLevel)

    return await combineTests(
      syntacticTests: syntacticTests ?? [],
      semanticTests: testItems(
        for: index?.unitTests(referencedByMainFiles: [mainFileUri.pseudoPath]) ?? [],
        index: index
      ),
      maybeOutdatedIndex: await workspace.index(checkedFor: .deletedFiles),
      workspace: workspace
    )
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
  package func filterUsing(semanticSymbols: [Symbol]?) -> AnnotatedTestItem? {
    guard let testItem = self.testItem.filterUsing(semanticSymbols: semanticSymbols) else {
      return nil
    }
    var test = self
    test.testItem = testItem
    return test
  }
}

fileprivate extension [AnnotatedTestItem] {
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

        // If this item shares an ID with a sibling and both are leaf
        // test items, store it by its disambiguated id to ensure we
        // don't overwrite the existing element.
        if rootItem.testItem.children.isEmpty && item.testItem.children.isEmpty {
          itemDict[item.testItem.ambiguousTestDifferentiator] = item
        } else {
          itemDict[id] = rootItem
        }
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

  func prefixTestsWithModuleName(workspace: Workspace) async -> Self {
    return await self.asyncMap({
      return AnnotatedTestItem(
        testItem: await $0.testItem.prefixIDWithModuleName(workspace: workspace),
        isExtension: $0.isExtension
      )
    })
  }
}

fileprivate extension [TestItem] {
  /// If multiple testItems share the same ID we add more context to make it unique.
  /// Two tests can share the same ID when two swift testing tests accept
  /// arguments of different types, i.e:
  /// ```
  /// @Test(arguments: [1,2,3]) func foo(_ x: Int) {}
  /// @Test(arguments: ["a", "b", "c"]) func foo(_ x: String) {}
  /// ```
  ///
  /// or when tests are in separate files but don't conflict because they are marked
  /// private, i.e:
  /// ```
  /// File1.swift: @Test private func foo() {}
  /// File2.swift: @Test private func foo() {}
  /// ```
  ///
  /// If we encounter one of these cases, we need to deduplicate the ID
  /// by appending `/filename:filename:lineNumber`.
  func deduplicatingIds() -> [TestItem] {
    var idCounts: [String: Int] = [:]
    for element in self where element.children.isEmpty {
      idCounts[element.id, default: 0] += 1
    }

    return self.map {
      var newItem = $0
      newItem.children = newItem.children.deduplicatingIds()
      if idCounts[newItem.id, default: 0] > 1 {
        newItem.id = newItem.ambiguousTestDifferentiator
      }
      return newItem
    }
  }
}

extension TestItem {
  /// A fully qualified name to disambiguate identical TestItem IDs.
  /// This matches the IDs produced by `swift test list` when there are
  /// tests that cannot be disambiguated by their simple ID.
  fileprivate var ambiguousTestDifferentiator: String {
    let filename = self.location.uri.arbitrarySchemeURL.lastPathComponent
    let position = location.range.lowerBound
    // Lines and columns start at 1.
    // swift-testing tests start from _after_ the @ symbol in @Test, so we need to add an extra column.
    // see https://github.com/swiftlang/swift-testing/blob/cca6de2be617aded98ecdecb0b3b3a81eec013f3/Sources/TestingMacros/Support/AttributeDiscovery.swift#L153
    let columnOffset = self.style == TestStyle.swiftTesting ? 2 : 1
    return "\(self.id)/\(filename):\(position.line + 1):\(position.utf16index + columnOffset)"
  }

  fileprivate func prefixIDWithModuleName(workspace: Workspace) async -> TestItem {
    guard let canonicalTarget = await workspace.buildServerManager.canonicalTarget(for: self.location.uri),
      let moduleName = await workspace.buildServerManager.moduleName(for: self.location.uri, in: canonicalTarget)
    else {
      return self
    }

    var newTest = self
    newTest.id = "\(moduleName).\(newTest.id)"
    newTest.children = await newTest.children.asyncMap({ await $0.prefixIDWithModuleName(workspace: workspace) })
    return newTest
  }
}
