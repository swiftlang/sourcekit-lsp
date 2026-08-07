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

import Dispatch
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKOptions
import SourceKitD
import SourceKitLSP

/// One inferred actor isolation as returned by sourcekitd's
/// `source.request.inferred_isolation.collect`. Currently covers explicit
/// closures only.
struct InferredIsolationInfo {
  /// Range of the entity to which the inferred isolation applies and the inlay
  /// should be attached.
  var range: Range<Position>

  /// Pretty-printed actor isolation (e.g. `@MainActor`, `nonisolated`).
  var isolation: String

  /// What kind of entity this isolation is attached to. Currently always
  /// `"closure"`.
  var kind: String

  init?(_ dict: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = dict.sourcekitd.keys

    guard let offset: Int = dict[keys.offset],
      let length: Int = dict[keys.length],
      let isolation: String = dict[keys.actorIsolation],
      let kind: String = dict[keys.kind]
    else {
      return nil
    }

    self.range = snapshot.positionOf(utf8Offset: offset)..<snapshot.positionOf(utf8Offset: offset + length)
    self.isolation = isolation
    self.kind = kind
  }
}

extension SwiftLanguageService {
  /// Collects inferred actor isolation for every explicit closure in the file.
  /// Skips closures whose isolation is written explicitly in the signature.
  ///
  /// - Parameter range: Restrict collection to closures overlapping this range
  ///   of the source file. If `nil`, the entire file is collected.
  func inferredIsolations(
    _ uri: DocumentURI,
    _ range: Range<Position>? = nil
  ) async throws -> [InferredIsolationInfo] {
    // TODO: too defensive?
    guard options.hasExperimentalFeature(.inferredClosureIsolationInlayHints) else {
      return []
    }

    let snapshot = try await self.latestSnapshot(for: uri)

    let skreq = sourcekitd.dictionary([
      keys.cancelOnSubsequentRequest: 0,
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: await self.compileCommand(for: uri, fallbackAfterTimeout: false)?.compilerArgs
        as [any SKDRequestValue]?,
    ])

    if let range = range {
      let start = snapshot.utf8Offset(of: range.lowerBound)
      let end = snapshot.utf8Offset(of: range.upperBound)
      skreq.set(keys.offset, to: start)
      skreq.set(keys.length, to: end - start)
    }

    let dict = try await send(sourcekitdRequest: \.collectInferredIsolation, skreq, snapshot: snapshot)
    guard let skResults: SKDResponseArray = dict[keys.results] else {
      return []
    }

    var results: [InferredIsolationInfo] = []
    results.reserveCapacity(skResults.count)
    // swift-format-ignore: ReplaceForEachWithForLoop
    skResults.forEach { (_, skItem) -> Bool in
      guard let info = InferredIsolationInfo(skItem, in: snapshot) else {
        assertionFailure("InferredIsolationInfo failed to deserialize")
        return true
      }
      results.append(info)
      return true
    }
    return results
  }
}
