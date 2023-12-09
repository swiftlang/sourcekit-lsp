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

import LSPLogging
import LanguageServerProtocol
import SourceKitD

struct RelatedIdentifier {
  let range: Range<Position>
}

struct RelatedIdentifiersResponse {
  let relatedIdentifiers: [RelatedIdentifier]
}

extension SwiftLanguageServer {
  func relatedIdentifiers(at position: Position, in snapshot: DocumentSnapshot, includeNonEditableBaseNames: Bool)
    async throws -> RelatedIdentifiersResponse
  {
    guard let offset = snapshot.utf8Offset(of: position) else {
      throw ResponseError.unknown("invalid position \(position)")
    }

    let skreq = SKDRequestDictionary(sourcekitd: self.sourcekitd)
    skreq[keys.request] = self.requests.relatedidents
    skreq[keys.cancelOnSubsequentRequest] = 0
    skreq[keys.offset] = offset
    skreq[keys.sourcefile] = snapshot.uri.pseudoPath

    // FIXME: SourceKit should probably cache this for us.
    if let compileCommand = await self.buildSettings(for: snapshot.uri) {
      skreq[keys.compilerargs] = compileCommand.compilerArgs
    }

    let dict = try await self.sourcekitd.send(skreq, fileContents: snapshot.text)

    guard
      let results: SKDResponseArray = dict[self.keys.results]
    else {
      throw ResponseError.internalError("sourcekitd response did not contain results or name")
    }

    try Task.checkCancellation()

    var relatedIdentifiers: [RelatedIdentifier] = []

    results.forEach { _, value in
      if let offset: Int = value[keys.offset],
        let start: Position = snapshot.positionOf(utf8Offset: offset),
        let length: Int = value[keys.length],
        let end: Position = snapshot.positionOf(utf8Offset: offset + length)
      {
        relatedIdentifiers.append(RelatedIdentifier(range: start..<end))
      }
      return true
    }
    return RelatedIdentifiersResponse(relatedIdentifiers: relatedIdentifiers)
  }
}
