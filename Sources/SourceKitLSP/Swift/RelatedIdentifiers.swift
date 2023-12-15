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
  let usage: RenameLocation.Usage
}

extension RenameLocation.Usage {
  fileprivate init?(_ uid: sourcekitd_uid_t?, _ keys: sourcekitd_keys) {
    switch uid {
    case keys.syntacticRenameDefinition:
      self = .definition
    case keys.syntacticRenameReference:
      self = .reference
    case keys.syntacticRenameCall:
      self = .call
    case keys.syntacticRenameUnknown:
      self = .unknown
    default:
      return nil
    }
  }

  func uid(keys: sourcekitd_keys) -> sourcekitd_uid_t {
    switch self {
    case .definition:
      return keys.syntacticRenameDefinition
    case .reference:
      return keys.syntacticRenameReference
    case .call:
      return keys.syntacticRenameCall
    case .unknown:
      return keys.syntacticRenameUnknown
    }
  }
}

struct RelatedIdentifiersResponse {
  let relatedIdentifiers: [RelatedIdentifier]
  /// The compound decl name at the requested location. This can be used as `name` parameter to a
  /// `find-syntactic-rename-ranges` request.
  ///
  /// `nil` if `sourcekitd` is too old and doesn't return the `name` as part of the related identifiers request.
  let name: String?
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
    skreq[keys.includeNonEditableBaseNames] = includeNonEditableBaseNames ? 1 : 0

    // FIXME: SourceKit should probably cache this for us.
    if let compileCommand = await self.buildSettings(for: snapshot.uri) {
      skreq[keys.compilerargs] = compileCommand.compilerArgs
    }

    let dict = try await self.sourcekitd.send(skreq, fileContents: snapshot.text)

    guard let results: SKDResponseArray = dict[self.keys.results] else {
      throw ResponseError.internalError("sourcekitd response did not contain results")
    }
    let name: String? = dict[self.keys.name]

    try Task.checkCancellation()

    var relatedIdentifiers: [RelatedIdentifier] = []

    results.forEach { _, value in
      if let offset: Int = value[keys.offset],
        let start: Position = snapshot.positionOf(utf8Offset: offset),
        let length: Int = value[keys.length],
        let end: Position = snapshot.positionOf(utf8Offset: offset + length)
      {
        let usage = RenameLocation.Usage(value[keys.nameType], keys) ?? .unknown
        relatedIdentifiers.append(
          RelatedIdentifier(range: start..<end, usage: usage)
        )
      }
      return true
    }
    return RelatedIdentifiersResponse(relatedIdentifiers: relatedIdentifiers, name: name)
  }
}
