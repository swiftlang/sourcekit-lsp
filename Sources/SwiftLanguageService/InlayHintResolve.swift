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

extension SwiftLanguageService {
  /// resolves an inlay hint by looking up the type definition location
  package func inlayHintResolve(_ req: InlayHintResolveRequest) async throws -> InlayHint {
    var hint = req.inlayHint

    // only resolve type hints that have stored data
    // extract uri and position from the lspany dictionary
    guard hint.kind == .type,
      case .dictionary(let dict) = hint.data,
      case .string(let uriString) = dict["uri"],
      let uri = try? DocumentURI(string: uriString),
      case .dictionary(let posDict) = dict["position"],
      case .int(let line) = posDict["line"],
      case .int(let character) = posDict["character"]
    else {
      return hint
    }
    let position = Position(line: line, utf16index: character)

    // get the type usr by calling cursor info at the variable position
    let typeLocation = try await lookupTypeDefinitionLocation(
      uri: uri,
      position: position
    )

    guard let typeLocation else {
      return hint
    }

    // return new hint with label parts that have location for go-to-definition
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
  /// This is used by both inlay hint resolution and the typeDefinition request.
  func lookupTypeDefinitionLocation(
    uri: DocumentURI,
    position: Position
  ) async throws -> Location? {
    let snapshot = try await self.latestSnapshot(for: uri)
    let compileCommand = await self.compileCommand(for: uri, fallbackAfterTimeout: false)

    // call cursor info at the variable position to get the type declaration location
    let skreq = sourcekitd.dictionary([
      keys.cancelOnSubsequentRequest: 0,
      keys.offset: snapshot.utf8Offset(of: position),
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compileCommand?.compilerArgs as [any SKDRequestValue]?,
    ])

    let dict = try await send(sourcekitdRequest: \.cursorInfo, skreq, snapshot: snapshot)

    if let filepath: String = dict[keys.typeDeclFilePath],
      let line: Int = dict[keys.typeDeclLine],
      let column: Int = dict[keys.typeDeclColumn]
    {
      let definitionUri = DocumentURI(filePath: filepath, isDirectory: false)
      let definitionPosition = Position(line: line - 1, utf16index: column - 1)
      return Location(uri: definitionUri, range: Range(definitionPosition))
    }

    // fallback: use the type declaration USR with index lookup

    guard let typeDeclUsr: String = dict[keys.typeDeclUsr] else {
      return nil
    }

    // look up the type definition in the index
    guard let workspace = await sourceKitLSPServer?.workspaceForDocument(uri: uri),
      let index = await workspace.index(checkedFor: .deletedFiles)
    else {
      return nil
    }

    guard let occurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: typeDeclUsr) else {
      return nil
    }

    let definitionUri = DocumentURI(filePath: occurrence.location.path, isDirectory: false)
    let definitionPosition = Position(
      line: occurrence.location.line - 1,
      utf16index: occurrence.location.utf8Column - 1
    )

    return Location(uri: definitionUri, range: Range(definitionPosition))
  }
}
