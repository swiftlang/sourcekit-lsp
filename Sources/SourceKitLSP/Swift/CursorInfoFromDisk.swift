//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildSystemIntegration
import Csourcekitd
import Foundation
import LanguageServerProtocol
import SKLogging
import SourceKitD

extension SwiftLanguageService {
  fileprivate func openHelperDocument(_ snapshot: DocumentSnapshot) async throws -> String {
    let sourceFile = "\(UUID().uuidString):\(snapshot.uri.pseudoPath)"
    let skreq = sourcekitd.dictionary([
      keys.request: self.requests.editorOpen,
      keys.name: sourceFile,
      keys.sourceText: snapshot.text,
      keys.syntacticOnly: 1,
    ])
    _ = try await sendSourcekitdRequest(skreq, fileContents: snapshot.text)
    return sourceFile
  }

  fileprivate func closeHelperDocument(_ sourceFile: String, _ snapshot: DocumentSnapshot) async {
    let skreq = sourcekitd.dictionary([
      keys.request: requests.editorClose,
      keys.name: sourceFile,
      keys.cancelBuilds: 0,
    ])
    _ = await orLog("Close helper document \"\(sourceFile)\" for cursorInfoFromDisk()") {
      try await sendSourcekitdRequest(skreq, fileContents: snapshot.text)
    }
  }

  /// Ensures that the snapshot is open in sourcekitd before calling body(_:).
  ///
  /// - Parameters:
  ///   - uri: The URI of the document to be opened.
  ///   - body: A closure that accepts the DocumentSnapshot as a parameter.
  fileprivate func withSnapshotFromDisk<Result>(
    prefix: String,
    uri: DocumentURI,
    _ body: (_ sourceFile: String, _ primaryFile: String?, _ snapshot: DocumentSnapshot) async throws -> Result
  ) async throws -> Result where Result: Sendable {
    let snapshot = try await self.snapshotFromDisk(for: uri)
    let sourceFile = try await openHelperDocument(snapshot)
    defer {
      Task { await closeHelperDocument(sourceFile, snapshot) }
    }
    var primaryFile = snapshot.uri.primaryFile?.pseudoPath
    if primaryFile == snapshot.uri.pseudoPath {
      primaryFile = sourceFile
    }
    return try await body(sourceFile, primaryFile, snapshot)
  }

  /// Provides detailed information about a symbol under the cursor, if any.
  ///
  /// Wraps the information returned by sourcekitd's `cursor_info` request, such as symbol name,
  /// USR, and declaration location. This request does minimal processing of the result.
  ///
  /// Always uses the document contents on disk regardless of whether or not it is currently open
  /// in SourceKit-LSP.
  ///
  /// - Parameters:
  ///   - url: Document URI in which to perform the request.
  ///   - range: The position range within the document to lookup the symbol at.
  ///   - includeSymbolGraph: Whether or not to ask sourcekitd for the complete symbol graph.
  ///   - fallbackSettingsAfterTimeout: Whether fallback build settings should be used for the cursor info request if no
  ///     build settings can be retrieved within a timeout.
  func cursorInfoFromDisk(
    _ uri: DocumentURI,
    _ range: Range<Position>,
    includeSymbolGraph: Bool = false,
    fallbackSettingsAfterTimeout: Bool,
    additionalParameters appendAdditionalParameters: ((SKDRequestDictionary) -> Void)? = nil
  ) async throws -> (cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?) {
    try await withSnapshotFromDisk(prefix: UUID().uuidString, uri: uri) { sourceFile, primaryFile, snapshot in
      let documentManager = try self.documentManager
      let offsetRange = snapshot.utf8OffsetRange(of: range)

      let keys = self.keys

      let skreq = sourcekitd.dictionary([
        keys.request: requests.cursorInfo,
        keys.cancelOnSubsequentRequest: 0,
        keys.offset: offsetRange.lowerBound,
        keys.length: offsetRange.upperBound != offsetRange.lowerBound ? offsetRange.count : nil,
        keys.sourceFile: sourceFile,
        keys.primaryFile: primaryFile,
        keys.retrieveSymbolGraph: includeSymbolGraph ? 1 : 0,
        keys.compilerArgs: await self.buildSettings(for: uri, fallbackAfterTimeout: fallbackSettingsAfterTimeout)?
          .patching(newFile: sourceFile, originalFile: uri).compilerArguments as [SKDRequestValue]?,
      ])

      appendAdditionalParameters?(skreq)

      let dict = try await sendSourcekitdRequest(skreq, fileContents: snapshot.text)

      var cursorInfoResults: [CursorInfo] = []
      if let cursorInfo = CursorInfo(dict, documentManager: documentManager, sourcekitd: sourcekitd) {
        cursorInfoResults.append(cursorInfo)
      }
      cursorInfoResults +=
        dict[keys.secondarySymbols]?
        .compactMap { CursorInfo($0, documentManager: documentManager, sourcekitd: sourcekitd) } ?? []
      let refactorActions =
        [SemanticRefactorCommand](
          array: dict[keys.refactorActions],
          range: range,
          textDocument: TextDocumentIdentifier(uri),
          keys,
          self.sourcekitd.api
        ) ?? []
      let symbolGraph: String? = dict[keys.symbolGraph]

      return (cursorInfoResults, refactorActions, symbolGraph)
    }
  }
}
