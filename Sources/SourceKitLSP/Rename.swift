//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

// MARK: - Helper types

private extension RenameLocation.Usage {
  init(roles: SymbolRole) {
    if roles.contains(.definition) || roles.contains(.declaration) {
      self = .definition
    } else if roles.contains(.call) {
      self = .call
    } else {
      self = .reference
    }
  }
}

private extension IndexSymbolKind {
  var isMethod: Bool {
    switch self {
    case .instanceMethod, .classMethod, .staticMethod:
      return true
    default: return false
    }
  }
}

// MARK: - Name translation

/// A name that has a representation both in Swift and clang-based languages.
///
/// These names might differ. For example, an Objective-C method gets translated by the clang importer to form the Swift
/// name or it could have a `SWIFT_NAME` attribute that defines the method's name in Swift. Similarly, a Swift symbol
/// might specify the name by which it gets exposed to Objective-C using the `@objc` attribute.
package struct CrossLanguageName: Sendable {
  package init(clangName: String? = nil, swiftName: String? = nil, definitionLanguage: Language) {
    self.clangName = clangName
    self.swiftName = swiftName
    self.definitionLanguage = definitionLanguage
  }

  /// The name of the symbol in clang languages or `nil` if the symbol is defined in Swift, doesn't have any references
  /// from clang languages and thus hasn't been translated.
  package let clangName: String?

  /// The name of the symbol in Swift or `nil` if the symbol is defined in clang, doesn't have any references from
  /// Swift and thus hasn't been translated.
  package let swiftName: String?

  /// the language that the symbol is defined in.
  package let definitionLanguage: Language

  /// The name of the symbol in the language that it is defined in.
  package var definitionName: String? {
    switch definitionLanguage {
    case .c, .cpp, .objective_c, .objective_cpp:
      return clangName
    case .swift:
      return swiftName
    default:
      return nil
    }
  }
}

package protocol NameTranslatorService: Sendable {
  func translateClangNameToSwift(
    at symbolLocation: SymbolLocation,
    in snapshot: DocumentSnapshot,
    isObjectiveCSelector: Bool,
    name: String
  ) async throws -> String

  func translateSwiftNameToClang(
    at symbolLocation: SymbolLocation,
    in uri: DocumentURI,
    name: String
  ) async throws -> String
}

// MARK: - SourceKitLSPServer

/// The kinds of symbol occurrence roles that should be renamed.
private let renameRoles: SymbolRole = [.declaration, .definition, .reference]

extension SourceKitLSPServer {
  /// Returns a `DocumentSnapshot`, a position and the corresponding language service that references
  /// `usr` from a Swift file. If `usr` is not referenced from Swift, returns `nil`.
  private func getReferenceFromSwift(
    usr: String,
    index: CheckedIndex,
    workspace: Workspace
  ) async throws -> (
    swiftLanguageService: any NameTranslatorService, snapshot: DocumentSnapshot, location: SymbolLocation
  )? {
    var reference: SymbolOccurrence? = nil
    try index.forEachSymbolOccurrence(byUSR: usr, roles: renameRoles) {
      if $0.symbolProvider == .swift {
        reference = $0
        // We have found a reference from Swift. Stop iteration.
        return false
      }
      return true
    }

    guard let reference else {
      return nil
    }
    let uri = reference.location.documentUri
    guard let snapshot = self.documentManager.latestSnapshotOrDisk(uri, language: .swift) else {
      return nil
    }
    let swiftLanguageService = await orLog("Getting NameTranslatorService") {
      try await self.primaryLanguageService(for: uri, .swift, in: workspace) as? (any NameTranslatorService)
    }
    guard let swiftLanguageService else {
      return nil
    }
    return (swiftLanguageService, snapshot, reference.location)
  }

  /// Returns a `CrossLanguageName` for the symbol with the given USR.
  ///
  /// If the symbol is used across clang/Swift languages, the cross-language name will have both a `swiftName` and a
  /// `clangName` set. Otherwise it only has the name of the language it's defined in set.
  ///
  /// If `overrideName` is passed, the name of the symbol will be assumed to be `overrideName` in its native language.
  /// This is used to create a `CrossLanguageName` for the new name of a renamed symbol.
  private func getCrossLanguageName(
    forUsr usr: String,
    overrideName: String? = nil,
    workspace: Workspace,
    index: CheckedIndex
  ) async throws -> CrossLanguageName? {
    let definitions = try index.occurrences(ofUSR: usr, roles: [.definition])
    if definitions.isEmpty {
      logger.error("No definitions for \(usr) found")
      return nil
    }
    if definitions.count > 1 {
      logger.log("Multiple definitions for \(usr) found")
    }
    // There might be multiple definitions of the same symbol eg. in different `#if` branches. In this case pick any of
    // them because with very high likelihood they all translate to the same clang and Swift name. Sort the entries to
    // ensure that we deterministically pick the same entry every time.
    for definitionOccurrence in definitions.sorted() {
      do {
        return try await getCrossLanguageName(
          forDefinitionOccurrence: definitionOccurrence,
          overrideName: overrideName,
          workspace: workspace,
          index: index
        )
      } catch {
        // If getting the cross-language name fails for this occurrence, try the next definition, if there are multiple.
        logger.log(
          "Getting cross-language name for occurrence at \(definitionOccurrence.location) failed. \(error.forLogging)"
        )
      }
    }
    return nil
  }

  private func getCrossLanguageName(
    forDefinitionOccurrence definitionOccurrence: SymbolOccurrence,
    overrideName: String? = nil,
    workspace: Workspace,
    index: CheckedIndex
  ) async throws -> CrossLanguageName {
    let definitionSymbol = definitionOccurrence.symbol
    let usr = definitionSymbol.usr
    let definitionLanguage: Language =
      switch definitionSymbol.language {
      case .c: .c
      case .cxx: .cpp
      case .objc: .objective_c
      case .swift: .swift
      }
    let definitionDocumentUri = definitionOccurrence.location.documentUri

    let definitionName = overrideName ?? definitionSymbol.name

    switch definitionLanguage.semanticKind {
    case .clang:
      let swiftName: String?
      if let swiftReference = try await getReferenceFromSwift(usr: usr, index: index, workspace: workspace) {
        let isObjectiveCSelector = definitionLanguage == .objective_c && definitionSymbol.kind.isMethod
        swiftName = try await swiftReference.swiftLanguageService.translateClangNameToSwift(
          at: swiftReference.location,
          in: swiftReference.snapshot,
          isObjectiveCSelector: isObjectiveCSelector,
          name: definitionName
        )
      } else {
        logger.debug("Not translating \(definitionSymbol) to Swift because it is not referenced from Swift")
        swiftName = nil
      }
      return CrossLanguageName(clangName: definitionName, swiftName: swiftName, definitionLanguage: definitionLanguage)
    case .swift:
      guard
        let swiftLanguageService = try await self.primaryLanguageService(
          for: definitionDocumentUri,
          definitionLanguage,
          in: workspace
        ) as? (any NameTranslatorService)
      else {
        throw ResponseError.unknown("Failed to get language service for the document defining \(usr)")
      }
      // Continue iteration if the symbol provider is not clang.
      // If we terminate early by returning `false` from the closure, `forEachSymbolOccurrence` returns `true`,
      // indicating that we have found a reference from clang.
      let hasReferenceFromClang = try !index.forEachSymbolOccurrence(byUSR: usr, roles: renameRoles) {
        return $0.symbolProvider != .clang
      }
      let clangName: String?
      if hasReferenceFromClang {
        clangName = try await swiftLanguageService.translateSwiftNameToClang(
          at: definitionOccurrence.location,
          in: definitionDocumentUri,
          name: definitionName
        )
      } else {
        clangName = nil
      }
      return CrossLanguageName(clangName: clangName, swiftName: definitionName, definitionLanguage: definitionLanguage)
    default:
      throw ResponseError.unknown("Cannot rename symbol because it is defined in an unknown language")
    }
  }

  /// Starting from the given USR, compute the transitive closure of all declarations that are overridden or override
  /// the symbol, including the USR itself.
  ///
  /// This includes symbols that need to traverse the inheritance hierarchy up and down. For example, it includes all
  /// occurrences of `foo` in the following when started from `Inherited.foo`.
  ///
  /// ```swift
  /// class Base { func foo() {} }
  /// class Inherited: Base { override func foo() {} }
  /// class OtherInherited: Base { override func foo() {} }
  /// ```
  private func overridingAndOverriddenUsrs(of usr: String, index: CheckedIndex) throws -> [String] {
    var workList = [usr]
    var usrs: [String] = []
    while let usr = workList.popLast() {
      usrs.append(usr)
      var relatedUsrs = try index.occurrences(relatedToUSR: usr, roles: .overrideOf).map(\.symbol.usr)
      relatedUsrs += try index.occurrences(ofUSR: usr, roles: .overrideOf).flatMap { occurrence in
        occurrence.relations.filter { $0.roles.contains(.overrideOf) }.map(\.symbol.usr)
      }
      for overriddenUsr in relatedUsrs {
        if usrs.contains(overriddenUsr) || workList.contains(overriddenUsr) {
          // Already handling this USR. Nothing to do.
          continue
        }
        workList.append(overriddenUsr)
      }
    }
    return usrs
  }

  func rename(_ request: RenameRequest) async throws -> WorkspaceEdit? {
    let uri = request.textDocument.uri
    let snapshot = try documentManager.latestSnapshot(uri)

    guard let workspace = await workspaceForDocument(uri: uri) else {
      throw ResponseError.workspaceNotOpen(uri)
    }
    let primaryFileLanguageService = try await primaryLanguageService(for: uri, snapshot.language, in: workspace)

    // Determine the local edits and the USR to rename
    let renameResult = try await primaryFileLanguageService.rename(request)

    // We only check if the files exist. If a source file has been modified on disk, we will still try to perform a
    // rename. Rename will check if the expected old name exists at the location in the index and, if not, ignore that
    // location. This way we are still able to rename occurrences in files where eg. only one line has been modified but
    // all the line:column locations of occurrences are still up-to-date.
    // This should match the check level in prepareRename.
    guard let usr = renameResult.usr, let index = await workspace.index(checkedFor: .deletedFiles) else {
      // We don't have enough information to perform a cross-file rename.
      return renameResult.edits
    }

    let oldName = try await getCrossLanguageName(forUsr: usr, workspace: workspace, index: index)
    let newName = try await getCrossLanguageName(
      forUsr: usr,
      overrideName: request.newName,
      workspace: workspace,
      index: index
    )

    guard let oldName, let newName else {
      // We failed to get the translated name, so we can't to global rename.
      // Do local rename within the current file instead as fallback.
      return renameResult.edits
    }

    var changes: [DocumentURI: [TextEdit]] = [:]
    if oldName.definitionLanguage == snapshot.language {
      // If this is not a cross-language rename, we can use the local edits returned by
      // the language service's rename function.
      // If this is cross-language rename, that's not possible because the user would eg.
      // enter a new clang name, which needs to be translated to the Swift name before
      // changing the current file.
      changes = renameResult.edits.changes ?? [:]
    }

    // If we have a USR + old name, perform an index lookup to find workspace-wide symbols to rename.
    // First, group all occurrences of that USR by the files they occur in.
    var locationsByFile: [DocumentURI: (renameLocations: [RenameLocation], symbolProvider: SymbolProviderKind)] = [:]

    let usrsToRename = try overridingAndOverriddenUsrs(of: usr, index: index)
    let occurrencesToRename = try usrsToRename.flatMap { try index.occurrences(ofUSR: $0, roles: renameRoles) }
    for occurrence in occurrencesToRename {
      let uri = occurrence.location.documentUri

      // Determine whether we should add the location produced by the index to those that will be renamed, or if it has
      // already been handled by the set provided by the AST.
      if changes[uri] != nil {
        if occurrence.symbol.usr == usr {
          // If the language server's rename function already produced AST-based locations for this symbol, no need to
          // perform an indexed rename for it.
          continue
        }
        switch occurrence.symbolProvider {
        case .swift:
          // sourcekitd only produces AST-based results for the direct calls to this USR. This is because the Swift
          // AST only has upwards references to superclasses and overridden methods, not the other way round. It is
          // thus not possible to (easily) compute an up-down closure like described in `overridingAndOverriddenUsrs`.
          // We thus need to perform an indexed rename for other, related USRs.
          break
        case .clang:
          // clangd produces AST-based results for the entire class hierarchy, so nothing to do.
          continue
        }
      }

      let renameLocation = RenameLocation(
        line: occurrence.location.line,
        utf8Column: occurrence.location.utf8Column,
        usage: RenameLocation.Usage(roles: occurrence.roles)
      )
      if let existingLocations = locationsByFile[uri] {
        if existingLocations.symbolProvider != occurrence.symbolProvider {
          logger.fault(
            """
            Found mismatching symbol providers for \(uri.forLogging): \
            \(String(describing: existingLocations.symbolProvider), privacy: .public) vs \
            \(String(describing: occurrence.symbolProvider), privacy: .public)
            """
          )
        }
        locationsByFile[uri] = (existingLocations.renameLocations + [renameLocation], occurrence.symbolProvider)
      } else {
        locationsByFile[uri] = ([renameLocation], occurrence.symbolProvider)
      }
    }

    // Now, call `editsToRename(locations:in:oldName:newName:)` on the language service to convert these ranges into
    // edits.
    let urisAndEdits =
      await locationsByFile
      .concurrentMap {
        (
          uri: DocumentURI,
          value: (renameLocations: [RenameLocation], symbolProvider: SymbolProviderKind)
        ) -> (DocumentURI, [TextEdit])? in
        let language: Language
        switch value.symbolProvider {
        case .clang:
          // Technically, we still don't know the language of the source file but defaulting to C is sufficient to
          // ensure we get the clang toolchain language server, which is all we care about.
          language = .c
        case .swift:
          language = .swift
        }
        // Create a document snapshot to operate on. If the document is open, load it from the document manager,
        // otherwise conjure one from the file on disk. We need the file in memory to perform UTF-8 to UTF-16 column
        // conversions.
        guard let snapshot = self.documentManager.latestSnapshotOrDisk(uri, language: language) else {
          logger.error("Failed to get document snapshot for \(uri.forLogging)")
          return nil
        }
        let languageService = await orLog("Getting language service to compute edits in file") {
          try await self.primaryLanguageService(for: uri, language, in: workspace)
        }
        guard let languageService else {
          return nil
        }

        var edits: [TextEdit] =
          await orLog("Getting edits for rename location") {
            return try await languageService.editsToRename(
              locations: value.renameLocations,
              in: snapshot,
              oldName: oldName,
              newName: newName
            )
          } ?? []
        for location in value.renameLocations where location.usage == .definition {
          edits += await languageService.editsToRenameParametersInFunctionBody(
            snapshot: snapshot,
            renameLocation: location,
            newName: newName
          )
        }
        edits = edits.filter { !$0.isNoOp(in: snapshot) }
        return (uri, edits)
      }.compactMap { $0 }
    for (uri, editsForUri) in urisAndEdits {
      if !editsForUri.isEmpty {
        changes[uri, default: []] += editsForUri
      }
    }
    var edits = renameResult.edits
    edits.changes = changes
    return edits
  }

  func prepareRename(
    _ request: PrepareRenameRequest,
    workspace: Workspace,
    languageService: any LanguageService
  ) async throws -> PrepareRenameResponse? {
    guard let languageServicePrepareRename = try await languageService.prepareRename(request) else {
      return nil
    }
    var prepareRenameResult = languageServicePrepareRename.prepareRename

    guard
      let index = await workspace.index(checkedFor: .deletedFiles),
      let usr = languageServicePrepareRename.usr,
      let oldName = try await self.getCrossLanguageName(forUsr: usr, workspace: workspace, index: index),
      var definitionName = oldName.definitionName
    else {
      return prepareRenameResult
    }
    if oldName.definitionLanguage == .swift, definitionName.hasSuffix("()") {
      definitionName = String(definitionName.dropLast(2))
    }

    // Get the name of the symbol's definition, if possible.
    // This is necessary for cross-language rename. Eg. when renaming an Objective-C method from Swift,
    // the user still needs to enter the new Objective-C name.
    prepareRenameResult.placeholder = definitionName
    return prepareRenameResult
  }

  func indexedRename(
    _ request: IndexedRenameRequest,
    workspace: Workspace,
    languageService: any LanguageService
  ) async throws -> WorkspaceEdit? {
    return try await languageService.indexedRename(request)
  }
}
