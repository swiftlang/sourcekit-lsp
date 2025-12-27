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

@_spi(SourceKitLSP) package import LanguageServerProtocol
import SourceKitLSP

extension SwiftLanguageService {
  package func symbolInfo(_ req: SymbolInfoRequest) async throws -> [SymbolDetails] {
    let uri = req.textDocument.uri
    
    // Check if position is on a literal token - return empty if so.
    // This prevents jump-to-definition for literals like "hello", 42, 3.14, true, false, nil, etc.
    // By checking tokenKind directly, we avoid blocking jump-to-definition for identifiers inside
    // literals (e.g., variables in string interpolation or array literals).
    if await isPositionOnLiteral(req.position, in: uri) {
      return []
    }
    
    let snapshot = try documentManager.latestSnapshot(uri)
    let position = await self.adjustPositionToStartOfIdentifier(req.position, in: snapshot)
    return try await cursorInfo(uri, position..<position, fallbackSettingsAfterTimeout: false)
      .cursorInfo.map { $0.symbolInfo }
  }
}
