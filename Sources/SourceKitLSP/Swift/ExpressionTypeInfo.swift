//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import LanguageServerProtocol
import SourceKitD

/// A typed expression as returned by sourcekitd's CollectExpressionType.
///
/// A detailed description of the structure returned by sourcekitd can be found
/// here: https://github.com/apple/swift/blob/main/tools/SourceKit/docs/Protocol.md#expression-type
struct ExpressionTypeInfo {
  /// Range of the expression in the source file.
  var range: Range<Position>
  /// The printed type of the expression.
  var printedType: String

  init?(_ dict: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = dict.sourcekitd.keys

    guard let offset: Int = dict[keys.expression_offset],
          let length: Int = dict[keys.expression_length],
          let startIndex = snapshot.positionOf(utf8Offset: offset),
          let endIndex = snapshot.positionOf(utf8Offset: offset + length),
          let printedType: String = dict[keys.expression_type] else {
      return nil
    }
    
    self.range = startIndex..<endIndex
    self.printedType = printedType
  }
}

enum ExpressionTypeInfoError: Error, Equatable {
  /// The given URL is not a known document.
  case unknownDocument(DocumentURI)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)
}

extension SwiftLanguageServer {
  /// Provides typed expressions in a document.
  ///
  /// - Parameters:
  ///   - url: Document URL in which to perform the request. Must be an open document.
  ///   - completion: Completion block to asynchronously receive the ExpressionTypeInfos, or error.
  func expressionTypeInfos(
    _ uri: DocumentURI,
    _ completion: @escaping (Swift.Result<[ExpressionTypeInfo], ExpressionTypeInfoError>) -> Void
  ) {
    guard let snapshot = documentManager.latestSnapshot(uri) else {
      return completion(.failure(.unknownDocument(uri)))
    }

    let keys = self.keys

    let skreq = SKDRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.expression_type
    skreq[keys.sourcefile] = snapshot.document.uri.pseudoPath

    // FIXME: SourceKit should probably cache this for us.
    if let compileCommand = self.commandsByFile[uri] {
      skreq[keys.compilerargs] = compileCommand.compilerArgs
    }

    let handle = self.sourcekitd.send(skreq, self.queue) { result in
      guard let dict = result.success else {
        return completion(.failure(.responseError(ResponseError(result.failure!))))
      }

      guard let skExpressionTypeInfos: SKDResponseArray = dict[keys.expression_type_list] else {
        return completion(.success([]))
      }

      var expressionTypeInfos: [ExpressionTypeInfo] = []
      expressionTypeInfos.reserveCapacity(skExpressionTypeInfos.count)

      skExpressionTypeInfos.forEach { (_, skExpressionTypeInfo) -> Bool in
        guard let info = ExpressionTypeInfo(skExpressionTypeInfo, in: snapshot) else {
          assertionFailure("ExpressionTypeInfo failed to deserialize")
          return true
        }
        expressionTypeInfos.append(info)
        return true
      }

      completion(.success(expressionTypeInfos))
    }

    // FIXME: cancellation
    _ = handle
  }
}
