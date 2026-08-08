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

import BuildServerIntegration
import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

extension SourceKitLSPServer {
  /// The names of all the symbols in the indexes of all workspaces, sorted and de-duplicated.
  func symbolNames() async -> [String] {
    var symbols = await self.workspaces
      .concurrentMap { workspace in
        await orLog("Getting symbol names in workspace") {
          try await workspace.uncheckedIndex?.allSymbolNames() ?? []
        } ?? []
      }
      .flatMap { $0 }
    if !symbols.isSortedAndUnique {
      symbols.sortAndDedupe()
    }
    return symbols
  }

  /// For each name in `names`, look up all canonical occurrences in every workspace index and convert them to
  /// `WorkspaceSymbolItem` values:
  /// - Source-file symbols get a `file://` URI with the exact 0-based line/column from the index.
  /// - SDK/stdlib symbols (index location ends in `.swiftinterface` or `.swiftmodule`) get a
  ///   `WorkspaceSymbol` with `location: .uri(file:// URL?module=...)` and the USR in `data`, provided
  ///   the client advertises `workspace.symbol.resolveSupport`. The client should call
  ///   `workspaceSymbol/resolve` to obtain the exact location within the interface.
  ///   Without that capability the raw `file://` URI from the index record is returned instead.
  ///
  /// The results are ordered by the position of their name in `names`; a name with no occurrences contributes
  /// no items.
  func symbolItems(forNames names: [String]) async throws -> [WorkspaceSymbolItem] {
    // Emitting a generated-interface reference document requires both that the client can open it and that
    // it will call `workspaceSymbol/resolve` to fill in the range.
    let canUseGeneratedInterfaceReferenceDocument =
      (self.capabilityRegistry?.clientHasWorkspaceGetReferenceDocumentSupport ?? false)
      && (self.capabilityRegistry?.clientSupportsWorkspaceSymbolResolve ?? false)

    let groupedResultPerWorkspace = await workspaces.concurrentMap { workspace -> [String: [WorkspaceSymbolItem]] in
      guard let index = await workspace.index(checkedFor: .deletedFiles) else {
        return [:]
      }
      var occurrencesByName: [String: [SymbolOccurrence]] = [:]
      for name in names {
        if Task.isCancelled { return [:] }
        var symbols: [SymbolOccurrence] = []
        _ = orLog("Getting symbol occurrences") {
          try index.forEachCanonicalSymbolOccurrence(byName: name) { symbolOccurrence in
            symbols.append(symbolOccurrence)
            return true
          }
        }
        occurrencesByName[name] = symbols
      }

      var mainFiles: [DocumentURI: DocumentURI] = [:]
      if canUseGeneratedInterfaceReferenceDocument {
        let occurrences = occurrencesByName.values.flatMap { $0 }
        mainFiles =
          await orLog("Resolving generated interface main files") {
            try await self.generatedInterfaceMainFiles(for: occurrences, in: workspace)
          } ?? [:]
      }
      if Task.isCancelled { return [:] }

      var result: [String: [WorkspaceSymbolItem]] = [:]
      let copiedFileMap = await workspace.buildServerManager.cachedCopiedFileMap
      for name in names {
        result[name] = (occurrencesByName[name] ?? []).compactMap { symbol in
          orLog("Getting symbol information") {
            try self.workspaceSymbolItem(
              for: symbol,
              in: index,
              copiedFileMap: copiedFileMap,
              referenceDocumentMainFile: symbol.location.uri.flatMap { mainFiles[$0] }
            )
          }
        }
      }
      return result
    }

    try Task.checkCancellation()

    // Flatten the result.
    var result: [WorkspaceSymbolItem] = []
    for name in names {
      for grouped in groupedResultPerWorkspace {
        if let items = grouped[name] {
          result.append(contentsOf: items)
        }
      }
    }
    return result
  }

  /// If the symbol has a `location: .uri(sourcekit-lsp://generated-swift-interface?...)` (as emitted by
  /// `workspace/symbol` and `workspace/symbolInfo` for SDK/stdlib symbols), open the generated Swift
  /// interface, resolve the symbol position using `data["usr"]`, and return the symbol with the exact
  /// range. Symbols with an already-resolved `location: .location(...)` are returned unchanged.
  func resolveGeneratedInterfaceLocation(of symbol: WorkspaceSymbol) async throws -> WorkspaceSymbol {
    var symbol = symbol
    guard
      case .uri(let uriOnly) = symbol.location,
      let referenceURL = try? ReferenceDocumentURL(from: uriOnly.uri),
      case .generatedInterface(let urlData) = referenceURL
    else {
      return symbol
    }

    // A USR is always present in practice; this only guards against a malformed `data` payload with an
    // empty USR string, treating it as absent so we don't run a position lookup that can't match.
    let usr = (symbol.sourceKitData?.usr).flatMap { $0.isEmpty ? nil : $0 }
    let buildSettingsFile = urlData.buildSettingsFrom
    guard let workspace = await self.workspaceForDocument(uri: buildSettingsFile) else {
      return symbol
    }
    let languageService = try await workspace.primaryLanguageService(for: buildSettingsFile, .swift)
    let details = await orLog("Opening generated interface in workspaceSymbol/resolve") {
      try await languageService.openGeneratedInterface(
        document: buildSettingsFile,
        moduleName: urlData.moduleName,
        groupName: urlData.groupName,
        symbolUSR: usr
      )
    }
    symbol.location = .location(
      Location(uri: uriOnly.uri, range: Range(details?.position ?? Position(line: 0, utf16index: 0)))
    )
    return symbol
  }

  /// The symbols in the indexes of all workspaces that match `query`.
  ///
  /// A query containing a qualifier separator (`.` or `::`) is resolved as a container chain plus a member
  /// name; any other query is matched as a subsequence against the symbol name.
  func symbolItems(matching query: String) async throws -> [WorkspaceSymbolItem] {
    // Ignore short queries since they are:
    // - noisy and slow, since they can match many symbols
    // - normally unintentional, triggered when the user types slowly or if the editor doesn't
    //   debounce events while the user is typing
    guard query.count >= minWorkspaceSymbolPatternLength else {
      return []
    }
    if let qualified = QualifiedWorkspaceSymbolQuery(query) {
      return try await qualifiedWorkspaceSymbols(qualified)
    }
    return try await unqualifiedWorkspaceSymbols(query: query)
  }

  private func unqualifiedWorkspaceSymbols(query: String) async throws -> [WorkspaceSymbolItem] {
    var items: [WorkspaceSymbolItem] = []
    for workspace in workspaces {
      guard let index = await workspace.index(checkedFor: .deletedFiles) else {
        continue
      }
      let copiedFileMap = await workspace.buildServerManager.cachedCopiedFileMap
      var symbols: [SymbolOccurrence] = []
      try index.forEachCanonicalSymbolOccurrence(
        containing: query,
        anchorStart: false,
        anchorEnd: false,
        subsequence: true,
        ignoreCase: true
      ) { symbol in
        if Task.isCancelled {
          return false
        }
        guard !symbol.location.isSystem && !symbol.roles.contains(.accessorOf) else {
          return true
        }
        symbols.append(symbol)
        return true
      }
      try Task.checkCancellation()
      // `workspace/symbol` filters out system symbols above, so no result points into a generated
      // interface and there is no main file to resolve.
      items += try symbols.sorted(by: <).compactMap {
        try self.workspaceSymbolItem(
          for: $0,
          in: index,
          copiedFileMap: copiedFileMap,
          referenceDocumentMainFile: nil
        )
      }
    }
    return items
  }

  /// Handle a `workspace/symbol` request whose query contains a qualifier separator (`.` or `::`).
  ///
  /// Resolves the container named by the query's container chain and returns the container's members whose
  /// name matches the query's member component.
  /// See `members(ofContainerChain:matching:includeSystemSymbols:in:)`.
  private func qualifiedWorkspaceSymbols(
    _ query: QualifiedWorkspaceSymbolQuery
  ) async throws -> [WorkspaceSymbolItem] {
    // Emitting a generated-interface reference document requires both that the client can open it and that
    // it will call `workspaceSymbol/resolve` to fill in the range. Unlike `unqualifiedWorkspaceSymbols`,
    // qualified queries can match SDK/stdlib members (e.g. `String.count`), so they need main files.
    let canUseGeneratedInterfaceReferenceDocument =
      (self.capabilityRegistry?.clientHasWorkspaceGetReferenceDocumentSupport ?? false)
      && (self.capabilityRegistry?.clientSupportsWorkspaceSymbolResolve ?? false)
    var items: [WorkspaceSymbolItem] = []
    for workspace in workspaces {
      guard let index = await workspace.index(checkedFor: .deletedFiles) else {
        continue
      }
      let copiedFileMap = await workspace.buildServerManager.cachedCopiedFileMap
      // Resolve the container named by the container chain, then take its direct members, keeping those
      // whose name matches `query.member`. An empty member (e.g. the query `Foo.`) lists all members.
      // System members are only useful if we can point at their generated interface.
      let symbols = try self.members(
        ofContainerChain: query.containerChain,
        fuzzyMatching: query.member,
        includeSystemSymbols: canUseGeneratedInterfaceReferenceDocument,
        in: index
      )
      var mainFiles: [DocumentURI: DocumentURI] = [:]
      if canUseGeneratedInterfaceReferenceDocument {
        mainFiles =
          await orLog("Resolving generated interface main files") {
            try await self.generatedInterfaceMainFiles(for: symbols, in: workspace)
          } ?? [:]
      }
      items += try symbols.sorted(by: <).compactMap {
        try self.workspaceSymbolItem(
          for: $0,
          in: index,
          copiedFileMap: copiedFileMap,
          referenceDocumentMainFile: $0.location.uri.flatMap { mainFiles[$0] },
          useQualifiedName: true
        )
      }
    }
    return items
  }

  /// Map a `SymbolOccurrence` from the index to a `WorkspaceSymbolItem`, or `nil` if it has no
  /// representable location.
  ///
  /// If `useQualifiedName` is `true` and the symbol has a container, the item's `name` is the fully-qualified
  /// name (e.g. `Foo.bar`) and `containerName` is dropped. This is used for qualified queries so that clients
  /// which filter workspace symbols by matching the query against the item's `name` (e.g. VS Code) keep the
  /// result — the qualified query wouldn't match the bare member name otherwise.
  ///
  /// - Parameter referenceDocumentMainFile: The project file whose build settings are used to open the
  ///   symbol's generated interface. **Passing a non-`nil` value changes the shape of the result**: the
  ///   symbol is returned as a `WorkspaceSymbol` with a `sourcekit-lsp://generated-swift-interface`
  ///   reference-document location (its range resolved lazily via `workspaceSymbol/resolve`) and the USR
  ///   in `data`, instead of a `SymbolInformation` with a plain `file://` location. A non-`nil` value must
  ///   therefore only be passed when the client supports **both** `workspace/getReferenceDocument` and
  ///   `workspaceSymbol/resolve`; enforcing that is the caller's responsibility.
  private nonisolated func workspaceSymbolItem(
    for symbolOccurrence: SymbolOccurrence,
    in index: CheckedIndex,
    copiedFileMap: CopiedFileMap,
    referenceDocumentMainFile: DocumentURI?,
    useQualifiedName: Bool = false
  ) throws -> WorkspaceSymbolItem? {
    let containerNames = try index.containerNames(of: symbolOccurrence)
    let separator =
      switch symbolOccurrence.symbol.language {
      case .cxx, .c, .objc: "::"
      case .swift: "."
      }
    let containerName: String? = containerNames.isEmpty ? nil : containerNames.joined(separator: separator)

    // For qualified queries, put the qualified name in the label (which clients filter against) and drop the
    // now-redundant container name.
    let name: String
    let displayContainerName: String?
    if useQualifiedName, let containerName {
      name = "\(containerName)\(separator)\(symbolOccurrence.symbol.name)"
      displayContainerName = nil
    } else {
      name = symbolOccurrence.symbol.name
      displayContainerName = containerName
    }

    if let referenceDocumentMainFile {
      let (interfaceModuleName, groupName) = Self.splitModuleNameAndGroup(symbolOccurrence.location.moduleName)
      let urlData = GeneratedInterfaceDocumentURLData(
        moduleName: interfaceModuleName,
        groupName: groupName,
        primaryFile: referenceDocumentMainFile
      )
      let usr = symbolOccurrence.symbol.usr
      // Include the interface path and module name in `data` so clients can render the candidate without
      // parsing the opaque location URI.
      let data = SourceKitWorkspaceSymbolData(
        usr: usr,
        interfaceURI: symbolOccurrence.location.uri,
        moduleName: symbolOccurrence.location.moduleName
      )
      return WorkspaceSymbolItem.workspaceSymbol(
        WorkspaceSymbol(
          name: name,
          kind: symbolOccurrence.symbol.kind.asLspSymbolKind(),
          containerName: displayContainerName,
          location: .uri(.init(uri: try urlData.uri)),
          data: data.encodeToLSPAny()
        )
      )
    }

    guard let symbolLocation = symbolOccurrence.location.lspLocation else { return nil }
    let location = symbolLocation.adjusted(for: copiedFileMap)
    return WorkspaceSymbolItem.symbolInformation(
      SymbolInformation(
        name: name,
        kind: symbolOccurrence.symbol.kind.asLspSymbolKind(),
        deprecated: nil,
        location: location,
        containerName: displayContainerName
      )
    )
  }

  /// Split an index module name into its module and optional group components.
  private nonisolated static func splitModuleNameAndGroup(
    _ fullModuleName: String
  ) -> (module: String, group: String?) {
    // A dotted index module name is ambiguous: `Foo.Bar` could be module `Foo` with group `Bar`, or a real
    // submodule named `Foo.Bar`, and SourceKit-LSP can't tell the two apart. In practice only the `Swift`
    // module is divided into groups (and it has no submodules), so only there is the trailing component
    // treated as a group; every other module name is kept whole.
    let swiftModulePrefix = "Swift."
    guard fullModuleName.hasPrefix(swiftModulePrefix) else {
      return (fullModuleName, nil)
    }
    // The index spells a group's levels with `.` (`Swift.Math.Integers`) but sourcekitd expects '/'
    // separated group name.
    let group = fullModuleName.dropFirst(swiftModulePrefix.count).replacing(".", with: "/")
    return ("Swift", String(group))
  }

  /// For each distinct SDK interface (`.swiftinterface`/`.swiftmodule`) among `symbols`, resolve the main
  /// file — a project file that imports the module, found via `mainFiles(containing:)` — whose build
  /// settings are used to open the generated interface. The lookup runs once per interface so a
  /// `workspace/symbol` response with many members of the same module doesn't repeat it. Interfaces with no
  /// main file are omitted, so callers skip those symbols.
  private func generatedInterfaceMainFiles(
    for symbols: [SymbolOccurrence],
    in workspace: Workspace
  ) async throws -> [DocumentURI: DocumentURI] {
    var mainFiles: [DocumentURI: DocumentURI] = [:]
    for symbol in symbols {
      let path = symbol.location.path
      guard path.hasSuffix(".swiftinterface") || path.hasSuffix(".swiftmodule"),
        let interfaceURI = symbol.location.uri,
        mainFiles[interfaceURI] == nil
      else {
        continue
      }
      try Task.checkCancellation()
      let mainFile = await workspace.buildServerManager
        .mainFiles(containing: interfaceURI)
        .sorted(by: { $0.arbitrarySchemeURL.absoluteString < $1.arbitrarySchemeURL.absoluteString })
        .first
      if let mainFile {
        mainFiles[interfaceURI] = mainFile
      }
    }
    return mainFiles
  }

  /// Resolve the container named by `chain` (outer-to-inner) and return its direct members (`childOf`)
  /// whose name fuzzily contains `member`.
  ///
  /// The innermost name in the chain is matched exactly (case-insensitive) and its `ancestors` — the
  /// container chain minus that innermost name — must match its enclosing scopes. `member` is matched as a
  /// case-insensitive subsequence; an empty `member` matches all members. Members declared in extensions
  /// are included. Members from all matching containers are unioned and de-duplicated by USR.
  ///
  /// System (SDK/stdlib) members are only included if `includeSystemSymbols` is `true`. They can only be
  /// navigated to through a generated interface, so callers pass `false` when the client can't open one.
  private nonisolated func members(
    ofContainerChain chain: [String],
    fuzzyMatching member: String,
    includeSystemSymbols: Bool,
    in index: CheckedIndex
  ) throws -> [SymbolOccurrence] {
    guard let containerName = chain.last else {
      throw ResponseError.internalError("\(#function) requires a non-empty chain")
    }

    // Lowercased once here because the enclosing scopes of every candidate container are compared against it.
    let lowercasedAncestors = chain.dropLast().map { $0.lowercased() }

    // Resolve the innermost container(s) by exact name, verifying the outer scope chain.
    //
    // `containerUSRs` holds every resolved container, including system ones, because a system type can be
    // extended from the user's own modules and those members stay reachable even when system symbols are
    // excluded. `containerUSRsForMemberLookup` is the subset whose children are actually walked.
    var containerUSRs: Set<String> = []
    var containerUSRsForMemberLookup: Set<String> = []
    try index.forEachCanonicalSymbolOccurrence(
      containing: containerName,
      anchorStart: true,
      anchorEnd: true,
      subsequence: false,
      ignoreCase: true
    ) { symbol in
      if Task.isCancelled {
        return false
      }
      // Resolving a system namespace (e.g. `std`, or a whole module) would enumerate an entire system scope,
      // so skip those.
      let isSystemNamespace: Bool =
        switch symbol.symbol.kind {
        case .namespace, .namespaceAlias, .module:
          symbol.location.isSystem
        default:
          false
        }
      // Match only the suffix of the enclosing scopes, so a chain may name just the inner scopes, e.g.
      // `Inner` for a container declared as `Outer.Inner`.
      let enclosingScopes = ((try? index.containerNames(of: symbol)) ?? []).suffix(lowercasedAncestors.count)
      guard !isSystemNamespace, enclosingScopes.map({ $0.lowercased() }) == lowercasedAncestors else {
        return true
      }
      containerUSRs.insert(symbol.symbol.usr)
      if includeSystemSymbols || !symbol.location.isSystem {
        containerUSRsForMemberLookup.insert(symbol.symbol.usr)
      }
      return true
    }
    try Task.checkCancellation()

    // Members declared in an extension are `childOf` the extension symbol, not the extended type. A
    // type's occurrences at `extension` sites carry `extendedBy` relations pointing at those extensions,
    // so add the extension USRs to the set of containers whose children we enumerate. Filtering the
    // occurrences by the `.extendedBy` role restricts the lookup to those extension sites instead of
    // returning every reference of the type.
    //
    // The extension site's location distinguishes the user's extensions from the SDK's, so system
    // extensions are skipped before any of their members are enumerated.
    for typeUSR in containerUSRs {
      try Task.checkCancellation()
      for occurrence in try index.occurrences(ofUSR: typeUSR, roles: .extendedBy) {
        guard includeSystemSymbols || !occurrence.location.isSystem else {
          continue
        }
        for relation in occurrence.relations where relation.roles.contains(.extendedBy) {
          containerUSRsForMemberLookup.insert(relation.symbol.usr)
        }
      }
    }

    var members: [SymbolOccurrence] = []
    var seenUSRs: Set<String> = []
    for containerUSR in containerUSRsForMemberLookup {
      try Task.checkCancellation()
      let children = try index.occurrences(relatedToUSR: containerUSR, roles: .childOf)
      for child in children {
        guard
          !child.roles.contains(.accessorOf),
          includeSystemSymbols || !child.location.isSystem,
          child.symbol.name.fuzzilyContains(subsequence: member),
          seenUSRs.insert(child.symbol.usr).inserted
        else {
          continue
        }
        switch child.symbol.language {
        case .c, .cxx, .objc:
          // A C-family symbol can have separate declaration and definition occurrences.
          members.append((try? index.primaryDefinitionOrDeclarationOccurrence(ofUSR: child.symbol.usr)) ?? child)
        case .swift:
          // Swift members have a single declaration site, so use the occurrence directly.
          members.append(child)
        }
      }
    }
    return members
  }
}

/// A `workspace/symbol` query split into its qualified parts.
///
/// For example:
///   `"String.description"`   → `containerChain: ["String"], member: "description"`
///   `"Foo::bar"`             → `containerChain: ["Foo"], member: "bar"`
///   `"Outer.Inner.method"`   → `containerChain: ["Outer", "Inner"], member: "method"`
///   `"Foo."`                 → `containerChain: ["Foo"], member: ""`
///   `"Foo.bar(baz:)"`        → `containerChain: ["Foo"], member: "bar(baz:)"` (a lone `:` is literal)
///
/// An unqualified query (no separator, e.g. `"description"`) fails to parse and returns `nil`.
package struct QualifiedWorkspaceSymbolQuery: Equatable {
  /// Container chain in outer-to-inner order. Always non-empty for a successfully-parsed query.
  package let containerChain: [String]

  /// The trailing component the user is searching for. May be empty (e.g. for the query `Foo.`).
  package let member: String

  /// Parse a `workspace/symbol` query, splitting on the trailing `.` or `::` qualifier separators.
  ///
  /// Returns `nil` if the query has no qualifier or the container chain is empty (so callers can fall
  /// back to the unqualified search path). A trailing separator with an empty member (e.g. `Foo.`)
  /// is a valid qualified query that lists all members of the container.
  package init?(_ query: String) {
    // Split the query into components on the `.` and `::` separators. The last component is the member
    // being searched for; the preceding components are the container chain. A lone `:` is not a separator
    // — it is a literal character, e.g. an argument label in `Collection.append(contentsOf:)`.
    var components =
      query
      .replacing("::", with: ".")
      .split(separator: ".", omittingEmptySubsequences: false)
      .map(String.init)

    // Without a separator the query isn't qualified; callers fall back to the unqualified search path.
    guard components.count >= 2 else { return nil }
    let member = components.removeLast()
    let containerChain = components
    // Container chain segments must be non-empty (rejects leading and doubled separators). An empty
    // member is allowed (e.g. `Foo.` lists all members of the container).
    guard !containerChain.contains(where: \.isEmpty) else { return nil }

    self.containerChain = containerChain
    self.member = member
  }
}

extension String {
  /// Returns `true` if the characters of `subsequence` appear in order within `self`, compared
  /// case-insensitively. An empty `subsequence` always matches.
  package func fuzzilyContains(subsequence: String) -> Bool {
    var remaining = Substring(subsequence.lowercased())
    for character in self.lowercased() where character == remaining.first {
      remaining = remaining.dropFirst()
    }
    return remaining.isEmpty
  }
}

/// Minimum supported pattern length for a `workspace/symbol` request, smaller pattern
/// strings are not queried and instead we return no results.
private let minWorkspaceSymbolPatternLength = 3

/// The maximum number of results to return from a `workspace/symbol` request.
private let maxWorkspaceSymbolResults = 4096
