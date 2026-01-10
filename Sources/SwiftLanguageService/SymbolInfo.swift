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
    let snapshot = try documentManager.latestSnapshot(uri)
    let position = await self.adjustPositionToStartOfIdentifier(req.position, in: snapshot)

    // Check if position is on a literal token - return empty if so
    // This prevents jump-to-definition for literals like "hello", 25, true, nil, etc.
    if await isPositionOnLiteralToken(req.position, in: uri) {
      return []
    }

    return try await cursorInfo(uri, position..<position, fallbackSettingsAfterTimeout: false)
      .cursorInfo.map { $0.symbolInfo }
  }
}
