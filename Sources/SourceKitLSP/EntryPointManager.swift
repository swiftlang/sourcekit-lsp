import LanguageServerProtocol
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import SemanticIndex
import IndexStoreDB
import SwiftExtensions
@_spi(SourceKitLSP) import SKLogging
import Foundation
internal import BuildServerIntegration

/// Manages discovered tests and playgrounds.
actor EntryPointManager {
  weak let sourceKitLSPServer: SourceKitLSPServer?
  private var currentTask: Task<Void, Never>? = nil

  private let onWorkspaceTestsChanged: () -> Void
  private let onWorkspacePlaygroundsChanged: () -> Void

  private(set) var latestWorkspaceTests: [TestItem] = []
  private(set) var playgrounds: [Playground] = []

  init(
    sourceKitLSPServer: SourceKitLSPServer,
    onWorkspaceTestsChanged: @escaping () -> Void,
    onWorkspacePlaygroundsChanged: @escaping () -> Void,
  ) {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.onWorkspaceTestsChanged = onWorkspaceTestsChanged
    self.onWorkspacePlaygroundsChanged = onWorkspacePlaygroundsChanged
  }

  /// Trigger refreshing.
  nonisolated func refresh() {
    _ = Task {
      await self.refreshImpl()
    }
  }

  /// Refresh, wait for completion, and return the result.
  func refreshAndWait() async {
    self.refreshImpl()
    await self.currentTask?.value
  }

  private func refreshImpl() {
    if let currentTask {
      currentTask.cancel()
    }
    self.currentTask = Task {
      if Task.isCancelled {
        return
      }
      if let newTests = await self.workspaceTests(), newTests != latestWorkspaceTests {
        latestWorkspaceTests = newTests
        self.onWorkspaceTestsChanged()
      }
      if let newPlaygrounds = await self.discoverPlaygrounds(), newPlaygrounds != playgrounds {
        playgrounds = newPlaygrounds
        self.onWorkspacePlaygroundsChanged()
      }
    }
  }
}

extension EntryPointManager {
  private func discoverPlaygrounds(in workspace: Workspace) async -> [Playground] {
    let playgroundsFromSyntacticIndex = await workspace.syntacticIndex.playgrounds()

    // We don't need to sort the playgrounds here because they will get sorted by `workspacePlaygrounds` request handler
    return playgroundsFromSyntacticIndex
  }

  private func discoverPlaygrounds() async -> [Playground]? {
    return await sourceKitLSPServer?.workspaces
      .concurrentMap { await self.discoverPlaygrounds(in: $0) }
      .flatMap { $0 }
      .sorted { $0.location < $1.location }
  }
}

extension EntryPointManager {
//  private func discoverTests() async -> [TestItem]? {
//    return await sourceKitLSPServer?.workspaces
//      .concurrentMap { workspace in await self.discoverTests(in: workspace) }
//      .flatMap({ $0 })
//      .mergingTestsInExtensions()
//      .prefixTestsWithModuleName(workspace: workspace)
//      .sorted { $0.location < $1.location }
//  }

//  private func discoverTests(in workspace: Workspace) async -> [AnnotatedTestItem] {
//    if Task.isCancelled {
//      return []
//    }
//
//    await workspace.buildServerManager.waitForUpToDateBuildGraph()
//    await workspace.semanticIndexManager?.waitForUpToDateIndex()
//
//    if Task.isCancelled {
//      return []
//    }
//
//    let index = await workspace.index(checkedFor: .deletedFiles)
//    let testsFromSemanticIndex = testItems(
//      for: index?.unitTests().filter { return $0.canBeTestDefinition } ?? [],
//      index: index,
//      // FIXME: Correct 'range'.
//      resolveLocation: { uri, position in Location(uri: uri, range: Range(position)) }
//    )
//
//    if Task.isCancelled {
//      return []
//    }
//
//    let testsFromSyntacticIndex = await workspace.syntacticIndex.tests()
//    let filesWithTestsFromSemanticIndex = Set(testsFromSemanticIndex.map(\.testItem.location.uri))
//
//    if Task.isCancelled {
//      return []
//    }
//
//    let syntacticTestsToInclude = testsFromSyntacticIndex
//      .compactMap { (item) -> AnnotatedTestItem? in
//        let testItem = item.testItem
//        if testItem.style == TestStyle.swiftTesting {
//          // Swift-testing tests aren't part of the semantic index. Always include them.
//          return item
//        }
//        if filesWithTestsFromSemanticIndex.contains(testItem.location.uri) {
//          // If we have an semantic tests from this file, then the semantic index is up-to-date for this file. We thus
//          // don't need to include results from the syntactic index.
//          return nil
//        }
//        if index?.hasAnyUpToDateUnit(for: testItem.location.uri) ?? false {
//          // We don't have a test for this file in the semantic index but an up-to-date unit file. This means that the
//          // index is up-to-date and has more knowledge that identifies a `TestItem` as not actually being a test, eg.
//          // because it starts with `test` but doesn't appear in a class inheriting from `XCTestCase`.
//          return nil
//        }
//        // Filter out any test items that we know aren't actually tests based on the semantic index.
//        // This might call `symbols(inFilePath:)` multiple times if there are multiple top-level test items (ie.
//        // XCTestCase subclasses, swift-testing handled above) for the same file. In practice test files usually contain
//        // a single XCTestCase subclass, so caching doesn't make sense here.
//        // Also, this is only called for files containing test cases but for which the semantic index is out-of-date.
//        if let filtered = testItem.filterUsing(
//          semanticSymbols: index?.symbols(inFilePath: testItem.location.uri.pseudoPath)
//        ) {
//          return AnnotatedTestItem(testItem: filtered, isExtension: item.isExtension)
//        }
//        return nil
//      }
//
//    return (testsFromSemanticIndex + syntacticTestsToInclude)
//  }

//  /// Converts a flat list of test symbol occurrences to a hierarchical `TestItem` array, inferring the hierarchical
//  /// structure from `childOf` relations between the symbol occurrences.
//  ///
//  /// `resolvePositions` resolves the position of a test to a `Location` that is effectively a range. This allows us to
//  /// provide ranges for the test cases in source code instead of only the test's location that we get from the index.
//  private func testItems(
//    for testSymbolOccurrences: [SymbolOccurrence],
//    index: CheckedIndex?,
//    resolveLocation: (DocumentURI, Position) -> Location
//  ) -> [AnnotatedTestItem] {
//    // Arrange tests by the USR they are contained in. This allows us to emit test methods as children of test classes.
//    // `occurrencesByParent[nil]` are the root test symbols that aren't a child of another test symbol.
//    var occurrencesByParent: [String?: [SymbolOccurrence]] = [:]
//
//    var testSymbolUsrs = Set(testSymbolOccurrences.map(\.symbol.usr))
//
//    // Gather any extension declarations that contains tests and add them to `occurrencesByParent` so we can properly
//    // arrange their test items as the extension's children.
//    for testSymbolOccurrence in testSymbolOccurrences {
//      for parentSymbol in testSymbolOccurrence.relations.filter({ $0.roles.contains(.childOf) }).map(\.symbol) {
//        guard parentSymbol.kind == .extension else {
//          continue
//        }
//        guard let definition = index?.primaryDefinitionOrDeclarationOccurrence(ofUSR: parentSymbol.usr) else {
//          logger.fault("Unable to find primary definition of extension '\(parentSymbol.usr)' containing tests")
//          continue
//        }
//        testSymbolUsrs.insert(parentSymbol.usr)
//        occurrencesByParent[nil, default: []].append(definition)
//      }
//    }
//
//    for testSymbolOccurrence in testSymbolOccurrences {
//      let childOfUsrs = testSymbolOccurrence.relations
//        .filter { $0.roles.contains(.childOf) }.map(\.symbol.usr).filter { testSymbolUsrs.contains($0) }
//      if childOfUsrs.count > 1 {
//        logger.fault(
//          "Test symbol \(testSymbolOccurrence.symbol.usr) is child or multiple symbols: \(childOfUsrs.joined(separator: ", "))"
//        )
//      }
//      occurrencesByParent[childOfUsrs.sorted().first, default: []].append(testSymbolOccurrence)
//    }
//
//    /// Returns a test item for the given `testSymbolOccurrence`.
//    ///
//    /// Also includes test items for all tests that are children of this test.
//    ///
//    /// `context` is used to build the test's ID. It is an array containing the names of all parent symbols. These will
//    /// be joined with the test symbol's name using `/` to form the test ID. The test ID can be used to run an
//    /// individual test.
//    func testItem(
//      for testSymbolOccurrence: SymbolOccurrence,
//      context: [String]
//    ) -> AnnotatedTestItem {
//      // Technically, we always need to convert UTF-8 columns to UTF-16 columns, which requires reading the file.
//      // In practice, they are almost always the same.
//      // We chose to avoid hitting the file system even if it means that we might report an incorrect column.
//      let symbolPosition = Position(
//        line: testSymbolOccurrence.location.line - 1,  // 1-based -> 0-based
//        utf16index: testSymbolOccurrence.location.utf8Column - 1
//      )
//
//      let id = (context + [testSymbolOccurrence.symbol.name]).joined(separator: "/")
//      let location = resolveLocation(testSymbolOccurrence.location.documentUri, symbolPosition)
//
//      let children =
//        occurrencesByParent[testSymbolOccurrence.symbol.usr, default: []]
//        .sorted()
//        .map {
//          testItem(for: $0, context: context + [testSymbolOccurrence.symbol.name])
//        }
//      return AnnotatedTestItem(
//        testItem: TestItem(
//          id: id,
//          label: testSymbolOccurrence.symbol.name,
//          disabled: false,
//          style: TestStyle.xcTest,
//          location: location,
//          children: children.map(\.testItem),
//          tags: []
//        ),
//        isExtension: testSymbolOccurrence.symbol.kind == .extension
//      )
//    }
//
//    return occurrencesByParent[nil, default: []]
//      .sorted()
//      .map { testItem(for: $0, context: []) }
//  }
}


//fileprivate extension SymbolOccurrence {
//  /// Assuming that this is a symbol occurrence returned by the index, return whether it can constitute the definition
//  /// of a test case.
//  ///
//  /// The primary intention for this is to filter out references to test cases and extension declarations of test cases.
//  /// The latter is important to filter so we don't include extension declarations for the derived `DiscoveredTests`
//  /// files on non-Darwin platforms.
//  var canBeTestDefinition: Bool {
//    guard roles.contains(.definition) else {
//      return false
//    }
//    guard symbol.kind == .class || symbol.kind == .instanceMethod else {
//      return false
//    }
//    return true
//  }
//}
//
//extension TestItem {
//  /// Use out-of-date semantic information to filter syntactic symbols.
//  ///
//  /// If the syntactic index found a test item, check if the semantic index knows about a symbol with that name. If it
//  /// does and that item is not marked as a test symbol, we can reasonably assume that this item still looks like a test
//  /// but is semantically known to not be a test. It will thus get filtered out.
//  ///
//  /// `semanticSymbols` should be all the symbols in the source file that this `TestItem` occurs in, retrieved using
//  /// `symbols(inFilePath:)` from the index.
//  fileprivate func filterUsing(semanticSymbols: [Symbol]?) -> TestItem? {
//    guard let semanticSymbols else {
//      return self
//    }
//    // We only check if we know of any symbol with the test item's name in this file. We could try to incorporate
//    // structure here (ie. look for a method within a class) but that makes the index lookup more difficult and in
//    // practice it is very unlikely that a test file will have two symbols with the same name, one of which is marked
//    // as a unit test while the other one is not.
//    let semanticSymbolsWithName = semanticSymbols.filter { $0.name == self.label }
//    if !semanticSymbolsWithName.isEmpty,
//      semanticSymbolsWithName.allSatisfy({ !$0.properties.contains(.unitTest) })
//    {
//      return nil
//    }
//    var test = self
//    test.children = test.children.compactMap { $0.filterUsing(semanticSymbols: semanticSymbols) }
//    return test
//  }
//}
//
//fileprivate extension [AnnotatedTestItem] {
//  /// When the test scanners discover tests in extensions they are captured in their own parent `TestItem`, not the
//  /// `TestItem` generated from the class/struct's definition. This is largely because of the syntatic nature of the
//  /// test scanners as they are today, which only know about tests within the context of the current file. Extensions
//  /// defined in separate files must be organized in their own `TestItem` since at the time of their creation there
//  /// isn't enough information to connect them back to the tests defined in the main type definition.
//  ///
//  /// This is a more syntatic than semantic view of the `TestItem` hierarchy than the end user likely wants.
//  /// If we think of the enclosing class or struct as the test suite, then extensions on that class or struct should be
//  /// additions to that suite, just like extensions on types are, from the user's perspective, transparently added to
//  /// their type.
//  ///
//  /// This method walks the `AnnotatedTestItem` tree produced by the test scanners and merges in the tests defined in
//  /// extensions into the final `TestItem`s that represent the type definition.
//  ///
//  /// This causes extensions to be merged into their type's definition if the type's definition exists in the list of
//  /// test items. If the type's definition is not a test item in this collection, the first extension of that type will
//  /// be used as the primary test location.
//  ///
//  /// For example if there are two files
//  ///
//  /// FileA.swift
//  /// ```swift
//  /// @Suite struct MyTests {
//  ///   @Test func oneIsTwo {}
//  /// }
//  /// ```
//  ///
//  /// FileB.swift
//  /// ```swift
//  /// extension MyTests {
//  ///   @Test func twoIsThree() {}
//  /// }
//  /// ```
//  ///
//  /// Then `workspace/tests` will return
//  /// - `MyTests` (FileA.swift:1)
//  ///   - `oneIsTwo`
//  ///   - `twoIsThree`
//  ///
//  /// And `textDocument/tests` for FileB.swift will return
//  /// - `MyTests` (FileB.swift:1)
//  ///   - `twoIsThree`
//  ///
//  /// A node's parent is identified by the node's ID with the last component dropped.
//  func mergingTestsInExtensions() -> [TestItem] {
//    var itemDict: [String: AnnotatedTestItem] = [:]
//    for item in self {
//      let id = item.testItem.id
//      if var rootItem = itemDict[id] {
//        // If we've encountered an extension first, and this is the
//        // type declaration, then use the type declaration TestItem
//        // as the root item.
//        if rootItem.isExtension && !item.isExtension {
//          var newItem = item
//          newItem.testItem.children += rootItem.testItem.children
//          rootItem = newItem
//        } else {
//          rootItem.testItem.children += item.testItem.children
//        }
//
//        // If this item shares an ID with a sibling and both are leaf
//        // test items, store it by its disambiguated id to ensure we
//        // don't overwrite the existing element.
//        if rootItem.testItem.children.isEmpty && item.testItem.children.isEmpty {
//          itemDict[item.testItem.ambiguousTestDifferentiator] = item
//        } else {
//          itemDict[id] = rootItem
//        }
//      } else {
//        itemDict[id] = item
//      }
//    }
//
//    if itemDict.isEmpty {
//      return []
//    }
//
//    var mergedIds = Set<String>()
//    for item in self {
//      let id = item.testItem.id
//      let parentID = id.components(separatedBy: "/").dropLast().joined(separator: "/")
//      // If the parent exists, add the current item to its children and remove it from the root
//      if var parent = itemDict[parentID] {
//        parent.testItem.children.append(item.testItem)
//        mergedIds.insert(parent.testItem.id)
//        itemDict[parent.testItem.id] = parent
//        itemDict[id] = nil
//      }
//    }
//
//    // Sort the tests by location, prioritizing TestItems not in extensions.
//    let sortedItems = itemDict.values
//      .sorted { ($0.isExtension != $1.isExtension) ? !$0.isExtension : ($0.testItem.location < $1.testItem.location) }
//
//    let result = sortedItems.map {
//      guard !$0.testItem.children.isEmpty, mergedIds.contains($0.testItem.id) else {
//        return $0.testItem
//      }
//      var newItem = $0.testItem
//      newItem.children = newItem.children
//        .map { AnnotatedTestItem(testItem: $0, isExtension: false) }
//        .mergingTestsInExtensions()
//      return newItem
//    }
//    return result
//  }
//
//  func prefixTestsWithModuleName(workspace: Workspace) async -> Self {
//    return await self.asyncMap({
//      return AnnotatedTestItem(
//        testItem: await $0.testItem.prefixIDWithModuleName(workspace: workspace),
//        isExtension: $0.isExtension
//      )
//    })
//  }
//}
//
//extension TestItem {
//  /// A fully qualified name to disambiguate identical TestItem IDs.
//  /// This matches the IDs produced by `swift test list` when there are
//  /// tests that cannot be disambiguated by their simple ID.
//  fileprivate var ambiguousTestDifferentiator: String {
//    let filename = self.location.uri.arbitrarySchemeURL.lastPathComponent
//    let position = location.range.lowerBound
//    // Lines and columns start at 1.
//    // swift-testing tests start from _after_ the @ symbol in @Test, so we need to add an extra column.
//    // see https://github.com/swiftlang/swift-testing/blob/cca6de2be617aded98ecdecb0b3b3a81eec013f3/Sources/TestingMacros/Support/AttributeDiscovery.swift#L153
//    let columnOffset = self.style == TestStyle.swiftTesting ? 2 : 1
//    return "\(self.id)/\(filename):\(position.line + 1):\(position.utf16index + columnOffset)"
//  }
//
//  fileprivate func prefixIDWithModuleName(workspace: Workspace) async -> TestItem {
//    guard let canonicalTarget = await workspace.buildServerManager.canonicalTarget(for: self.location.uri),
//      let moduleName = await workspace.buildServerManager.moduleName(for: self.location.uri, in: canonicalTarget)
//    else {
//      return self
//    }
//
//    var newTest = self
//    newTest.id = "\(moduleName).\(newTest.id)"
//    newTest.children = await newTest.children.asyncMap({ await $0.prefixIDWithModuleName(workspace: workspace) })
//    return newTest
//  }
//}
