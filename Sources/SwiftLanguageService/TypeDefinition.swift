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
import SemanticIndex
import SourceKitD
import SourceKitLSP

extension SwiftLanguageService {
  /// Handles the textDocument/typeDefinition request.
  package func typeDefinition(_ request: TypeDefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    let uri = request.textDocument.uri
    let position = request.position

    let snapshot = try await self.latestSnapshot(for: uri)
    let compileCommand = await self.compileCommand(for: uri, fallbackAfterTimeout: false)

    let skreq = sourcekitd.dictionary([
      keys.cancelOnSubsequentRequest: 0,
      keys.offset: snapshot.utf8Offset(of: position),
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compileCommand?.compilerArgs as [any SKDRequestValue]?,
    ])

    let dict = try await send(sourcekitdRequest: \.cursorInfo, skreq, snapshot: snapshot)
    let documentManager = try self.documentManager

    // If the cursor is on a type symbol itself, use its USR directly.
    // Otherwise get the type of the symbol at this position.
    let symbol: SymbolDetails
    if let cursorInfo = CursorInfo(dict, snapshot: snapshot, documentManager: documentManager, sourcekitd: sourcekitd) {
      switch cursorInfo.symbolInfo.kind {
      case .class, .struct, .enum, .interface, .typeParameter:
        symbol = cursorInfo.symbolInfo
      default:
        guard let typeUsr: String = dict[keys.typeUsr],
              let typeSymbol = try await cursorInfoFromTypeUSR(typeUsr, in: snapshot)?.symbolInfo else {
          return nil
        }
        symbol = typeSymbol
      }
    } else {
      guard let typeUsr: String = dict[keys.typeUsr],
            let typeSymbol = try await cursorInfoFromTypeUSR(typeUsr, in: snapshot)?.symbolInfo else {
        return nil
      }
      symbol = typeSymbol
    }

    let index = await sourceKitLSPServer?.workspaceForDocument(uri: uri)?.index(checkedFor: .deletedFiles)
    let locations = try await SourceKitLSP.definitionLocations(
      for: symbol,
      originatorUri: uri,
      index: index,
      languageService: self
    ).locations

    if locations.isEmpty {
      return nil
    }

    return .locations(locations)
  }
}
