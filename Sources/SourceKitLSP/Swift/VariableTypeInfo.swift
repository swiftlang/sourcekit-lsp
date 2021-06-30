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

/// A typed variable as returned by sourcekitd's CollectVariableType.
struct VariableTypeInfo {
  /// Range of the variable identifier in the source file.
  var range: Range<Position>
  /// The printed type of the variable.
  var printedType: String
  /// Whether the variable has an explicit type annotation in the source file.
  var hasExplicitType: Bool

  init?(_ dict: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = dict.sourcekitd.keys

    guard let offset: Int = dict[keys.variable_offset],
          let length: Int = dict[keys.variable_length],
          let startIndex = snapshot.positionOf(utf8Offset: offset),
          let endIndex = snapshot.positionOf(utf8Offset: offset + length),
          let printedType: String = dict[keys.variable_type],
          let hasExplicitType: Bool = dict[keys.variable_type_explicit] else {
      return nil
    }

    self.range = startIndex..<endIndex
    self.printedType = printedType
    self.hasExplicitType = hasExplicitType
  }
}

enum VariableTypeInfoError: Error, Equatable {
  /// The given URL is not a known document.
  case unknownDocument(DocumentURI)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)
}

extension SwiftLanguageServer {
  /// Must be called on self.queue.
  private func _variableTypeInfos(
    _ uri: DocumentURI,
    _ range: Range<Position>? = nil,
    _ completion: @escaping (Swift.Result<[VariableTypeInfo], VariableTypeInfoError>) -> Void
  ) {
    dispatchPrecondition(condition: .onQueue(queue))

    guard let snapshot = documentManager.latestSnapshot(uri) else {
      return completion(.failure(.unknownDocument(uri)))
    }

    let keys = self.keys

    let skreq = SKDRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.variable_type
    skreq[keys.sourcefile] = snapshot.document.uri.pseudoPath

    if let range = range,
       let start = snapshot.utf8Offset(of: range.lowerBound),
       let end = snapshot.utf8Offset(of: range.upperBound) {
      skreq[keys.offset] = start
      skreq[keys.length] = end - start
    }

    // FIXME: SourceKit should probably cache this for us
    if let compileCommand = self.commandsByFile[uri] {
      skreq[keys.compilerargs] = compileCommand.compilerArgs
    }

    let handle = self.sourcekitd.send(skreq, self.queue) { result in
      guard let dict = result.success else {
        return completion(.failure(.responseError(ResponseError(result.failure!))))
      }

      guard let skVariableTypeInfos: SKDResponseArray = dict[keys.variable_type_list] else {
        return completion(.success([]))
      }

      var variableTypeInfos: [VariableTypeInfo] = []
      variableTypeInfos.reserveCapacity(skVariableTypeInfos.count)

      skVariableTypeInfos.forEach { (_, skVariableTypeInfo) -> Bool in
        guard let info = VariableTypeInfo(skVariableTypeInfo, in: snapshot) else {
          assertionFailure("VariableTypeInfo failed to deserialize")
          return true
        }
        variableTypeInfos.append(info)
        return true
      }

      completion(.success(variableTypeInfos))
    }

    // FIXME: cancellation
    _ = handle
  }

  /// Provides typed variable declarations in a document.
  ///
  /// - Parameters:
  ///   - url: Document URL in which to perform the request. Must be an open document.
  ///   - completion: Completion block to asynchronously receive the VariableTypeInfos, or error.
  func variableTypeInfos(
    _ uri: DocumentURI,
    _ range: Range<Position>? = nil,
    _ completion: @escaping (Swift.Result<[VariableTypeInfo], VariableTypeInfoError>) -> Void
  ) {
    queue.async {
      self._variableTypeInfos(uri, range, completion)
    }
  }
}
