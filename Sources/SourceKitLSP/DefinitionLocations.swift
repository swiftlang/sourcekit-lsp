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

package import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
import Foundation
package import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SemanticIndex

/// The result of looking up definition locations for a symbol.
package struct DefinitionLocationsResult {
  /// The locations of the symbol's definition.
  package let locations: [Location]
  /// The occurrences from the index lookup, if any. Can be used by callers to avoid duplicate index lookups.
  package let indexOccurrences: [SymbolOccurrence]

  package init(locations: [Location], indexOccurrences: [SymbolOccurrence] = []) {
    self.locations = locations
    self.indexOccurrences = indexOccurrences
  }
}

/// Returns a source-backed definition location for `moduleName` if it is a module in the root SwiftPM package.
///
/// Swift does not have a source declaration for a module. For SwiftPM root targets,
/// use the package manifest as the source-backed definition location.
private func definitionLocationInWorkspacePackage(
  moduleName: String,
  buildServerManager: BuildServerManager?
) async -> Location? {
  guard let buildServerManager else {
    return nil
  }
  return await orLog("Determining source location for workspace module") {
    let sourceFiles = try await buildServerManager.sourceFiles(includeNonBuildableFiles: false)
    for (uri, sourceFileInfo) in sourceFiles.sorted(by: { $0.key.stringValue < $1.key.stringValue }) {
      guard sourceFileInfo.isPartOfRootProject else {
        continue
      }
      for target in sourceFileInfo.targets.sorted(by: { $0.uri.stringValue < $1.uri.stringValue }) {
        guard await buildServerManager.moduleName(for: uri, in: target) == moduleName else {
          continue
        }
        guard let packageManifest = await buildServerManager.configPath,
          packageManifest.lastPathComponent == "Package.swift"
        else {
          return nil
        }
        return Location(uri: DocumentURI(packageManifest), range: Range(Position(line: 0, utf16index: 0)))
      }
    }
    return nil
  }
}

/// Return the locations for jump to definition from the given `SymbolDetails`.
package func definitionLocations(
  for symbol: SymbolDetails,
  originatorUri: DocumentURI,
  index: CheckedIndex?,
  languageService: any LanguageService,
  buildServerManager: BuildServerManager?
) async throws -> DefinitionLocationsResult {
  // If this symbol is a module then generate a textual interface
  if symbol.kind == .module {
    if let bestLocalDeclaration = symbol.bestLocalDeclaration {
      return DefinitionLocationsResult(locations: [bestLocalDeclaration])
    }
    if let index, let usr = symbol.usr {
      logger.info("Performing indexed jump-to-definition with USR \(usr)")
      let occurrences = try index.definitionOrDeclarationOccurrences(ofUSR: usr)
      if !occurrences.isEmpty {
        return DefinitionLocationsResult(
          locations: occurrences.compactMap { $0.location.lspLocation }.sorted(),
          indexOccurrences: occurrences
        )
      }
    }

    // For module symbols, prefer using systemModule information if available
    let moduleName: String
    let groupName: String?

    if let systemModule = symbol.systemModule {
      moduleName = systemModule.moduleName
      groupName = systemModule.groupName
    } else if let name = symbol.name {
      moduleName = name
      groupName = nil
    } else {
      return DefinitionLocationsResult(locations: [])
    }

    if let workspacePackageLocation = await definitionLocationInWorkspacePackage(
      moduleName: moduleName,
      buildServerManager: buildServerManager
    ) {
      return DefinitionLocationsResult(locations: [workspacePackageLocation])
    }

    let location = try await definitionInInterface(
      moduleName: moduleName,
      groupName: groupName,
      symbolUSR: nil,
      originatorUri: originatorUri,
      languageService: languageService
    )
    return DefinitionLocationsResult(locations: [location])
  }

  // System symbols use generated interface
  if symbol.isSystem ?? false, let systemModule = symbol.systemModule {
    let location = try await definitionInInterface(
      moduleName: systemModule.moduleName,
      groupName: systemModule.groupName,
      symbolUSR: symbol.usr,
      originatorUri: originatorUri,
      languageService: languageService
    )
    return DefinitionLocationsResult(locations: [location])
  }

  guard let index else {
    if let bestLocalDeclaration = symbol.bestLocalDeclaration {
      return DefinitionLocationsResult(locations: [bestLocalDeclaration])
    }
    return DefinitionLocationsResult(locations: [])
  }

  guard let usr = symbol.usr else { return DefinitionLocationsResult(locations: []) }
  logger.info("Performing indexed jump-to-definition with USR \(usr)")

  let occurrences = try index.definitionOrDeclarationOccurrences(ofUSR: usr)

  if occurrences.isEmpty {
    if let bestLocalDeclaration = symbol.bestLocalDeclaration {
      return DefinitionLocationsResult(locations: [bestLocalDeclaration])
    }
    // Fallback: The symbol was not found in the index. This often happens with
    // third-party binary frameworks or libraries where indexing data is missing.
    // If module info is available, fallback to generating the textual interface.
    if let systemModule = symbol.systemModule {
      let location = try await definitionInInterface(
        moduleName: systemModule.moduleName,
        groupName: systemModule.groupName,
        symbolUSR: symbol.usr,
        originatorUri: originatorUri,
        languageService: languageService
      )
      return DefinitionLocationsResult(locations: [location])
    }
  }

  return DefinitionLocationsResult(
    locations: occurrences.compactMap { $0.location.lspLocation }.sorted(),
    indexOccurrences: occurrences
  )
}

/// Generate the generated interface for the given module, write it to disk and return the location to which to jump
/// to get to the definition of `symbolUSR`.
///
/// `originatorUri` is the URI of the file from which the definition request is performed. It is used to determine the
/// compiler arguments to generate the generated interface.
package func definitionInInterface(
  moduleName: String,
  groupName: String?,
  symbolUSR: String?,
  originatorUri: DocumentURI,
  languageService: any LanguageService
) async throws -> Location {
  let documentForBuildSettings = originatorUri.buildSettingsFile

  guard
    let interfaceDetails = try await languageService.openGeneratedInterface(
      document: documentForBuildSettings,
      moduleName: moduleName,
      groupName: groupName,
      symbolUSR: symbolUSR
    )
  else {
    throw ResponseError.unknown("Could not generate Swift Interface for \(moduleName)")
  }
  let position = interfaceDetails.position ?? Position(line: 0, utf16index: 0)
  return Location(uri: interfaceDetails.uri, range: Range(position))
}
