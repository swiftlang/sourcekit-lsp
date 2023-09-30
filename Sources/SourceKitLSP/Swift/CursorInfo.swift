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

import LanguageServerProtocol
import SourceKitD

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

  /// The documentation comment XML string. The schema is at
  /// https://github.com/apple/swift/blob/main/bindings/xml/comment-xml-schema.rng
  var documentationXML: String?

  /// The refactor actions available at this position.
  var refactorActions: [SemanticRefactorCommand]? = nil

  init(_ symbolInfo: SymbolDetails, annotatedDeclaration: String?, documentationXML: String?, refactorActions: [SemanticRefactorCommand]? = nil) {
    self.symbolInfo = symbolInfo
    self.annotatedDeclaration = annotatedDeclaration
    self.documentationXML =  documentationXML
    self.refactorActions = refactorActions
  }
}

/// An error from a cursor info request.
enum CursorInfoError: Error, Equatable {

  /// The given URL is not a known document.
  case unknownDocument(DocumentURI)

  /// The given range is not valid in the document snapshot.
  case invalidRange(Range<Position>)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)
}

extension CursorInfoError: CustomStringConvertible {
  var description: String {
    switch self {
    case .unknownDocument(let url):
      return "failed to find snapshot for url \(url)"
    case .invalidRange(let range):
      return "invalid range \(range)"
    case .responseError(let error):
      return "\(error)"
    }
  }
}

extension SwiftLanguageServer {

  /// Must be called on self.queue.
  func _cursorInfo(
    _ uri: DocumentURI,
    _ range: Range<Position>,
    additionalParameters appendAdditionalParameters: ((SKDRequestDictionary) -> Void)? = nil,
    _ completion: @escaping (Swift.Result<CursorInfo?, CursorInfoError>) -> Void)
  {
    guard let snapshot = documentManager.latestSnapshot(uri) else {
       return completion(.failure(.unknownDocument(uri)))
     }

    guard let offsetRange = snapshot.utf8OffsetRange(of: range) else {
      return completion(.failure(.invalidRange(range)))
    }

    let keys = self.keys

    let skreq = SKDRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.cursorinfo
    skreq[keys.offset] = offsetRange.lowerBound
    if offsetRange.upperBound != offsetRange.lowerBound {
      skreq[keys.length] = offsetRange.count
    }
    skreq[keys.sourcefile] = snapshot.document.uri.pseudoPath

    // FIXME: SourceKit should probably cache this for us.
    if let compileCommand = self.commandsByFile[uri] {
      skreq[keys.compilerargs] = compileCommand.compilerArgs
    }

    appendAdditionalParameters?(skreq)

    let handle = self.sourcekitd.send(skreq, self.queue) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        return completion(.failure(.responseError(ResponseError(result.failure!))))
      }

      guard let kind: sourcekitd_uid_t = dict[keys.kind] else {
        // Nothing to report.
        return completion(.success(nil))
      }

      var location: Location? = nil
      if let filepath: String = dict[keys.filepath],
         let offset: Int = dict[keys.offset],
         let pos = snapshot.positionOf(utf8Offset: offset)
      {
        location = Location(uri: DocumentURI(URL(fileURLWithPath: filepath)), range: Range(pos))
      }

      let refactorActionsArray: SKDResponseArray? = dict[keys.refactor_actions]

      completion(.success(
        CursorInfo(
          SymbolDetails(
          name: dict[keys.name],
          containerName: nil,
          usr: dict[keys.usr],
          bestLocalDeclaration: location,
          kind: kind.asSymbolKind(self.sourcekitd.values)),
        annotatedDeclaration: dict[keys.annotated_decl],
        documentationXML: dict[keys.doc_full_as_xml],
        refactorActions:
          [SemanticRefactorCommand](
          array: refactorActionsArray,
          range: range,
          textDocument: TextDocumentIdentifier(uri),
          keys,
          self.sourcekitd.api)
      )))
    }

    // FIXME: cancellation
    _ = handle
  }

  /// Provides detailed information about a symbol under the cursor, if any.
  ///
  /// Wraps the information returned by sourcekitd's `cursor_info` request, such as symbol name,
  /// USR, and declaration location. This request does minimal processing of the result.
  ///
  /// - Parameters:
  ///   - url: Document URL in which to perform the request. Must be an open document.
  ///   - range: The position range within the document to lookup the symbol at.
  ///   - completion: Completion block to asynchronously receive the CursorInfo, or error.
  func cursorInfo(
    _ uri: DocumentURI,
    _ range: Range<Position>,
    additionalParameters appendAdditionalParameters: ((SKDRequestDictionary) -> Void)? = nil,
    _ completion: @escaping (Swift.Result<CursorInfo?, CursorInfoError>) -> Void)
  {
    self.queue.async {
      self._cursorInfo(uri, range,
                       additionalParameters: appendAdditionalParameters, completion)
    }
  }
}
