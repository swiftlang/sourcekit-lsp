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

import LanguageServerProtocol

extension SwiftLanguageService {
  package func symbolInfo(_ req: SymbolInfoRequest) async throws -> [SymbolDetails] {
    let uri = req.textDocument.uri
    let snapshot = try documentManager.latestSnapshot(uri)
    let position = await self.adjustPositionToStartOfIdentifier(req.position, in: snapshot)
    return try await cursorInfo(uri, position..<position).cursorInfo.map { $0.symbolInfo }
  }
}
