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
  /// Returns the type's symbol details for a symbol at the given position.
  package func typeSymbolInfo(_ request: TypeDefinitionRequest) async throws -> SymbolDetails? {
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

    guard let typeUsr: String = dict[keys.typeUsr] else {
      return nil
    }

    let typeInfo = try await cursorInfoFromTypeUSR(typeUsr, in: snapshot)
    return typeInfo?.symbolInfo
  }
}
