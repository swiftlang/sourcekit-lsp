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

import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SemanticIndex

/// converts a symbol index location to an LSP location
func indexToLSPLocation(_ location: SymbolLocation) -> Location? {
  guard !location.path.isEmpty else { return nil }
  return Location(
    uri: location.documentUri,
    range: Range(
      Position(
        line: max(0, location.line - 1),
        utf16index: max(0, location.utf8Column - 1)
      )
    )
  )
}

/// returns the definition location for a symbol, handling generated interfaces for SDK types
package func definitionLocations(
  for symbol: SymbolDetails,
  originatorUri: DocumentURI,
  index: CheckedIndex?,
  openGeneratedInterface:
    @escaping (
      _ document: DocumentURI,
      _ moduleName: String,
      _ groupName: String?,
      _ symbolUSR: String?
    ) async throws -> GeneratedInterfaceDetails?
) async throws -> [Location] {
  // module symbols generate a textual interface
  if symbol.kind == .module {
    let moduleName: String
    let groupName: String?

    if let systemModule = symbol.systemModule {
      moduleName = systemModule.moduleName
      groupName = systemModule.groupName
    } else if let name = symbol.name {
      moduleName = name
      groupName = nil
    } else {
      return []
    }

    let location = try await definitionInInterface(
      moduleName: moduleName,
      groupName: groupName,
      symbolUSR: nil,
      originatorUri: originatorUri,
      openGeneratedInterface: openGeneratedInterface
    )
    return [location]
  }

  // system symbols use generated interface
  if symbol.isSystem ?? false, let systemModule = symbol.systemModule {
    let location = try await definitionInInterface(
      moduleName: systemModule.moduleName,
      groupName: systemModule.groupName,
      symbolUSR: symbol.usr,
      originatorUri: originatorUri,
      openGeneratedInterface: openGeneratedInterface
    )
    return [location]
  }

  // try local declaration first
  guard let index else {
    if let bestLocalDeclaration = symbol.bestLocalDeclaration {
      return [bestLocalDeclaration]
    }
    return []
  }

  guard let usr = symbol.usr else { return [] }
  logger.info("Performing indexed jump-to-definition with USR \(usr)")

  let occurrences = index.definitionOrDeclarationOccurrences(ofUSR: usr)

  if occurrences.isEmpty {
    if let bestLocalDeclaration = symbol.bestLocalDeclaration {
      return [bestLocalDeclaration]
    }
    // fallback to generated interface for SDK types without index data
    if let systemModule = symbol.systemModule {
      let location = try await definitionInInterface(
        moduleName: systemModule.moduleName,
        groupName: systemModule.groupName,
        symbolUSR: symbol.usr,
        originatorUri: originatorUri,
        openGeneratedInterface: openGeneratedInterface
      )
      return [location]
    }
  }

  return occurrences.compactMap { indexToLSPLocation($0.location) }.sorted()
}

/// generates a swift interface and returns location for the given symbol
package func definitionInInterface(
  moduleName: String,
  groupName: String?,
  symbolUSR: String?,
  originatorUri: DocumentURI,
  openGeneratedInterface:
    @escaping (
      _ document: DocumentURI,
      _ moduleName: String,
      _ groupName: String?,
      _ symbolUSR: String?
    ) async throws -> GeneratedInterfaceDetails?
) async throws -> Location {
  let documentForBuildSettings = originatorUri.buildSettingsFile

  guard
    let interfaceDetails = try await openGeneratedInterface(
      documentForBuildSettings,
      moduleName,
      groupName,
      symbolUSR
    )
  else {
    throw ResponseError.unknown("Could not generate Swift Interface for \(moduleName)")
  }
  let position = interfaceDetails.position ?? Position(line: 0, utf16index: 0)
  return Location(uri: interfaceDetails.uri, range: Range(position))
}
