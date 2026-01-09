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
  /// It works by:
  /// 1. Getting the type USR (mangled name) from cursorInfo at the position
  /// 2. Converting the mangled type ($s prefix) to a proper USR (s: prefix)
  /// 3. Looking up the type definition in the index or via cursorInfo 
  func lookupTypeDefinitionLocation(
    uri: DocumentURI,
    position: Position
  ) async throws -> Location? {
    // Step 1: Get type USR from cursor info at the position
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

    // Get the type USR (this is of a mangled type like "$sSS" for String)
    guard let typeUsr: String = dict[keys.typeUsr] else {
      return nil
    }

    // step 2: Convert mangled type to proper USR
    // The typeUsr is a mangled type like "$s4test6MyTypeVD" for struct MyType
    // To get the declaration USR, we need to:
    // 1. Replace "$s" prefix with "s:"
    // 2. Strip the trailing "D" which is a mangling suffix (type descriptor)
    var mangledName = typeUsr
    if mangledName.hasPrefix("$s") {
      mangledName = "s:" + mangledName.dropFirst(2)
    }
    // Strip trailing 'D' (type descriptor suffix in mangling)
    if mangledName.hasSuffix("D") {
      mangledName = String(mangledName.dropLast())
    }
    let usr = mangledName

    // step 3: Try index lookup first (works well for local and external types)
    if let workspace = await sourceKitLSPServer?.workspaceForDocument(uri: uri),
      let index = await workspace.index(checkedFor: .deletedFiles),
      let occurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr)
    {
      let definitionUri = DocumentURI(filePath: occurrence.location.path, isDirectory: false)
      let definitionPosition = Position(
        line: occurrence.location.line - 1,
        utf16index: occurrence.location.utf8Column - 1
      )
      return Location(uri: definitionUri, range: Range(definitionPosition))
    }

    // Fallback: Try cursorInfo with USR (for types not in index)
    if let typeInfo = try await cursorInfoFromTypeUSR(typeUsr, in: uri),
      let location = typeInfo.symbolInfo.bestLocalDeclaration
    {
      return location
    }

    return nil
  }
}
