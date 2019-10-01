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
import TSCBasic
import sourcekitd

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
  /// https://github.com/apple/swift/blob/master/bindings/xml/comment-xml-schema.rng
  var documentationXML: String?

  /// The refactor actions available at this position.
  var refactorActions: SKResponseArray? = nil

  init(_ symbolInfo: SymbolDetails, annotatedDeclaration: String?, documentationXML: String?, refactorActions: SKResponseArray? = nil) {
    self.symbolInfo = symbolInfo
    self.annotatedDeclaration = annotatedDeclaration
    self.documentationXML =  documentationXML
    self.refactorActions = refactorActions
  }
}

extension CursorInfo {

  /// Create a `CursorInfo` from a sourcekitd response dictionary, if possible.
  ///
  /// - Parameters:
  ///   - dict: Response dictionary to extract information from.
  ///   - snapshot: Document contents at the time of the request, used to map locations.
  ///   - keys: The sourcekitd key set to use for looking up into `dict`.
  init?(_ dict: SKResponseDictionary, _ snapshot: DocumentSnapshot, _ keys: sourcekitd_keys) {
    guard let _: sourcekitd_uid_t = dict[keys.kind] else {
      // Nothing to report.
      return nil
    }

    var location: Location? = nil
    if let filepath: String = dict[keys.filepath],
       let offset: Int = dict[keys.offset],
       let pos = snapshot.positionOf(utf8Offset: offset)
    {
      location = Location(url: URL(fileURLWithPath: filepath), range: Range(pos))
    }

    self.init(
      SymbolDetails(
        name: dict[keys.name],
        containerName: nil,
        usr: dict[keys.usr],
        bestLocalDeclaration: location),
      annotatedDeclaration: dict[keys.annotated_decl],
      documentationXML: dict[keys.doc_full_as_xml],
      refactorActions: dict[keys.refactor_actions])
  }
}

/// An error from a cursor info request.
enum CursorInfoError: Error {

  /// The given URL is not a known document.
  case unknownDocument(URL)

  /// The given position is not valid in the document snapshot.
  case invalidPosition(Position)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)
}

extension CursorInfoError: CustomStringConvertible {
  var description: String {
    switch self {
    case .unknownDocument(let url):
      return "failed to find snapshot for url \(url)"
    case .invalidPosition(let position):
      return "invalid position \(position)"
    case .responseError(let error):
      return "\(error)"
    }
  }
}

extension SwiftLanguageServer {

  /// Provides detailed information about a symbol under the cursor, if any.
  ///
  /// Wraps the information returned by sourcekitd's `cursor_info` request, such as symbol name,
  /// USR, and declaration location. This request does minimal processing of the result.
  ///
  /// - Parameters:
  ///   - url: Document URL in which to perform the request. Must be an open document.
  ///   - position: Location within the document to lookup the symbol at.
  ///   - completion: Completion block to asynchronously receive the CursorInfo, or error.
  func cursorInfo(
    _ url: URL,
    _ position: Position,
    customCursorOffset: Int? = nil,
    additionalParameters appendAdditionalParameters: ((SKRequestDictionary) -> Void)? = nil,
    _ completion: @escaping (Swift.Result<CursorInfo?, CursorInfoError>) -> Void)
  {
    guard let snapshot = documentManager.latestSnapshot(url) else {
      return completion(.failure(.unknownDocument(url)))
    }

    guard let offset = snapshot.utf8Offset(of: position) else {
      return completion(.failure(.invalidPosition(position)))
    }
 
    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.cursorinfo
    skreq[keys.offset] = customCursorOffset ?? offset
    skreq[keys.sourcefile] = snapshot.document.url.path

    appendAdditionalParameters?(skreq)

    // FIXME: should come from the internal document
    if let settings = buildSystem.settings(for: snapshot.document.url, snapshot.document.language) {
      skreq[keys.compilerargs] = settings.compilerArguments
    }

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        return completion(.failure(.responseError(result.failure!)))
      }

      guard let _: sourcekitd_uid_t = dict[self.keys.kind] else {
        // Nothing to report.
        return completion(.success(nil))
      }

      var location: Location? = nil
      if let filepath: String = dict[self.keys.filepath],
         let offset: Int = dict[self.keys.offset],
         let pos = snapshot.positionOf(utf8Offset: offset)
      {
        location = Location(url: URL(fileURLWithPath: filepath), range: Range(pos))
      }

      completion(.success(
        CursorInfo(
          SymbolDetails(
          name: dict[self.keys.name],
          containerName: nil,
          usr: dict[self.keys.usr],
          bestLocalDeclaration: location),
        annotatedDeclaration: dict[self.keys.annotated_decl],
        documentationXML: dict[self.keys.doc_full_as_xml],
        refactorActions: dict[self.keys.refactor_actions]
        )))
    }

    // FIXME: cancellation
    _ = handle
  }
}
