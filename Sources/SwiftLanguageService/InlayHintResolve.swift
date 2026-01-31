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

import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
import SemanticIndex
import SourceKitD
import SourceKitLSP
import SwiftExtensions

extension SwiftLanguageService {
  /// Resolves an inlay hint by looking up the type definition location.
  package func inlayHintResolve(_ req: InlayHintResolveRequest) async throws -> InlayHint {
    let hint = req.inlayHint

    guard hint.kind == .type,
      let resolveData = InlayHintResolveData(fromLSPAny: hint.data)
    else {
      return hint
    }

    // Fail if document version has changed since the hint was created
    let currentSnapshot = try await self.latestSnapshot(for: resolveData.uri)
    guard currentSnapshot.version == resolveData.version else {
      return hint
    }

    let typeLocation = try await lookupTypeDefinitionLocation(
      snapshot: currentSnapshot,
      position: resolveData.position
    )

    guard let typeLocation else {
      return hint
    }

    if case .string(let labelText) = hint.label {
      return InlayHint(
        position: hint.position,
        label: .parts([InlayHintLabelPart(value: labelText, location: typeLocation)]),
        kind: hint.kind,
        textEdits: hint.textEdits,
        tooltip: hint.tooltip,
        paddingLeft: hint.paddingLeft,
        paddingRight: hint.paddingRight,
        data: hint.data
      )
    }

    return hint
  }

  /// Looks up the definition location for the type at the given position.
  ///
  /// This is used by inlay hint resolution to enable go-to-definition on type hints.
  /// For SDK types, this returns a location in the generated interface.
  func lookupTypeDefinitionLocation(
    snapshot: DocumentSnapshot,
    position: Position
  ) async throws -> Location? {
    let compileCommand = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false)

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

    guard let typeInfo = try await cursorInfoFromTypeUSR(typeUsr, in: snapshot) else {
      return nil
    }

    let locations = try await SourceKitLSP.definitionLocations(
      for: typeInfo.symbolInfo,
      originatorUri: snapshot.uri,
      index: nil,
      languageService: self
    )

    return locations.only
  }
}
