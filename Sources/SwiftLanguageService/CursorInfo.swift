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

import Csourcekitd
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP

/// Detailed information about a symbol under the cursor.
///
/// Wraps the information returned by sourcekitd's `cursor_info` request, such as symbol name, USR,
/// and declaration location. This is intended to only do lightweight processing of the data to make
/// it easier to use from Swift. Any expensive processing, such as parsing the XML strings, is
/// handled elsewhere.
struct CursorInfo {

  /// Information common between CursorInfo and SymbolDetails from the `symbolInfo` request, such as
  /// name and USR.
  var symbolInfo: SymbolDetails

  /// The annotated declaration XML string.
  var annotatedDeclaration: String?

  /// The documentation as it is spelled in
  var documentation: String?

  /// The refactor actions available at this position.
  var refactorActions: [SemanticRefactorCommand]? = nil

  init(
    _ symbolInfo: SymbolDetails,
    annotatedDeclaration: String?,
    documentation: String?
  ) {
    self.symbolInfo = symbolInfo
    self.annotatedDeclaration = annotatedDeclaration
    self.documentation = documentation
  }

  /// `snapshot` is the snapshot from which the cursor info was invoked. It is necessary to pass that snapshot in here
  /// because snapshot might not be open in `documentManager` if cursor info was invoked using file contents from disk
  /// using `cursorInfoFromDisk` and thus we couldn't convert positions if the snapshot wasn't passed in explicitly.
  /// For all document other than `snapshot`, `documentManager` is used to find the latest snapshot of a document to
  /// convert positions.
  init?(
    _ dict: SKDResponseDictionary,
    snapshot: DocumentSnapshot,
    documentManager: DocumentManager,
    sourcekitd: some SourceKitD
  ) {
    let keys = sourcekitd.keys
    guard let kind: sourcekitd_api_uid_t = dict[keys.kind] else {
      // Nothing to report.
      return nil
    }

    let location: Location?
    if let filepath: String = dict[keys.filePath],
      let line: Int = dict[keys.line],
      let column: Int = dict[keys.column]
    {
      let uri = DocumentURI(filePath: filepath, isDirectory: false)
      let snapshot: DocumentSnapshot? =
        if snapshot.uri.sourcekitdSourceFile == filepath {
          snapshot
        } else {
          documentManager.latestSnapshotOrDisk(uri, language: .swift)
        }
      if let snapshot {
        let position = snapshot.positionOf(zeroBasedLine: line - 1, utf8Column: column - 1)
        location = Location(uri: uri, range: Range(position))
      } else {
        logger.error("Failed to get snapshot for \(uri.forLogging) to convert position")
        location = nil
      }
    } else {
      location = nil
    }

    let module: SymbolDetails.ModuleInfo?
    if let moduleName: String = dict[keys.moduleName] {
      let groupName: String? = dict[keys.groupName]
      module = SymbolDetails.ModuleInfo(moduleName: moduleName, groupName: groupName)
    } else {
      module = nil
    }

    self.init(
      SymbolDetails(
        name: dict[keys.name],
        containerName: nil,
        usr: dict[keys.usr],
        bestLocalDeclaration: location,
        kind: kind.asSymbolKind(sourcekitd.values),
        isDynamic: dict[keys.isDynamic] ?? false,
        isSystem: dict[keys.isSystem] ?? false,
        receiverUsrs: dict[keys.receivers]?.compactMap { $0[keys.usr] as String? } ?? [],
        systemModule: module
      ),
      annotatedDeclaration: dict[keys.annotatedDecl],
      documentation: dict[keys.docComment]
    )
  }
}

/// An error from a cursor info request.
enum CursorInfoError: Error, Equatable {
  /// The given range is not valid in the document snapshot.
  case invalidRange(Range<Position>)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)
}

extension CursorInfoError: CustomStringConvertible {
  var description: String {
    switch self {
    case .invalidRange(let range):
      return "invalid range \(range)"
    case .responseError(let error):
      return "\(error)"
    }
  }
}

extension SwiftLanguageService {
  /// Provides detailed information about a symbol under the cursor, if any.
  ///
  /// Wraps the information returned by sourcekitd's `cursor_info` request, such as symbol name,
  /// USR, and declaration location. This request does minimal processing of the result.
  ///
  /// - Parameters:
  ///   - url: Document URI in which to perform the request. Must be an open document.
  ///   - range: The position range within the document to lookup the symbol at.
  ///   - includeSymbolGraph: Whether or not to ask sourcekitd for the complete symbol graph.
  ///   - fallbackSettingsAfterTimeout: Whether fallback build settings should be used for the cursor info request if no
  ///     build settings can be retrieved within a timeout.
  func cursorInfo(
    _ snapshot: DocumentSnapshot,
    compileCommand: SwiftCompileCommand?,
    _ range: Range<Position>,
    includeSymbolGraph: Bool = false,
    additionalParameters appendAdditionalParameters: ((SKDRequestDictionary) -> Void)? = nil
  ) async throws -> (cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?) {
    let documentManager = try self.documentManager

    let offsetRange = snapshot.utf8OffsetRange(of: range)

    let keys = self.keys

    let skreq = sourcekitd.dictionary([
      keys.cancelOnSubsequentRequest: 0,
      keys.offset: offsetRange.lowerBound,
      keys.length: offsetRange.upperBound != offsetRange.lowerBound ? offsetRange.count : nil,
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.retrieveSymbolGraph: includeSymbolGraph ? 1 : 0,
      keys.compilerArgs: compileCommand?.compilerArgs as [any SKDRequestValue]?,
    ])

    appendAdditionalParameters?(skreq)

    let dict = try await send(sourcekitdRequest: \.cursorInfo, skreq, snapshot: snapshot)

    var cursorInfoResults: [CursorInfo] = []
    if let cursorInfo = CursorInfo(dict, snapshot: snapshot, documentManager: documentManager, sourcekitd: sourcekitd) {
      cursorInfoResults.append(cursorInfo)
    }
    cursorInfoResults +=
      dict[keys.secondarySymbols]?
      .compactMap { CursorInfo($0, snapshot: snapshot, documentManager: documentManager, sourcekitd: sourcekitd) } ?? []
    let refactorActions =
      [SemanticRefactorCommand](
        array: dict[keys.refactorActions],
        range: range,
        textDocument: TextDocumentIdentifier(snapshot.uri),
        keys,
        self.sourcekitd.api
      ) ?? []
    let symbolGraph: String? = dict[keys.symbolGraph]

    return (cursorInfoResults, refactorActions, symbolGraph)
  }

  func cursorInfo(
    _ uri: DocumentURI,
    _ range: Range<Position>,
    includeSymbolGraph: Bool = false,
    fallbackSettingsAfterTimeout: Bool,
    additionalParameters appendAdditionalParameters: ((SKDRequestDictionary) -> Void)? = nil
  ) async throws -> (cursorInfo: [CursorInfo], refactorActions: [SemanticRefactorCommand], symbolGraph: String?) {
    return try await self.cursorInfo(
      self.latestSnapshot(for: uri),
      compileCommand: await self.compileCommand(for: uri, fallbackAfterTimeout: fallbackSettingsAfterTimeout),
      range,
      includeSymbolGraph: includeSymbolGraph,
      additionalParameters: appendAdditionalParameters
    )
  }
}
