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
import SwiftSyntax

fileprivate extension TokenSyntax {
  /// Returns `false` if it is known that this token can’t be followed by a type
  /// annotation.
  var canBeFollowedByTypeAnnotation: Bool {
    var node = Syntax(self)
    LOOP: while let parent = node.parent {
      switch parent.kind {
      case .caseItem, .closureParam:
        // case items (inside a switch) and closure parameters can’t have type
        // annotations.
        return false
      case .codeBlockItem, .memberDeclListItem:
        // Performance optimization. If we walked the parents up to code block item,
        // we can’t enter a case item or closure param anymore. No need walking
        // the tree any further.
        break LOOP
      default:
        break
      }
      node = parent
    }

    // By default, assume that the token can be followed by a type annotation as
    // most locations that produce a variable type info can.
    return true
  }
}

/// A typed variable as returned by sourcekitd's CollectVariableType.
struct VariableTypeInfo {
  /// Range of the variable identifier in the source file.
  var range: Range<Position>
  /// The printed type of the variable.
  var printedType: String
  /// Whether the variable has an explicit type annotation in the source file.
  var hasExplicitType: Bool
  /// Whether we should suggest making an edit to add the type annotation to the
  /// source file.
  var canBeFollowedByTypeAnnotation: Bool

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
    let tokenAtOffset = snapshot.tokens.syntaxTree?.token(at: AbsolutePosition(utf8Offset: offset))

    self.range = startIndex..<endIndex
    self.printedType = printedType
    self.hasExplicitType = hasExplicitType
    self.canBeFollowedByTypeAnnotation = tokenAtOffset?.canBeFollowedByTypeAnnotation ?? true
  }
}

enum VariableTypeInfoError: Error, Equatable {
  /// The given URL is not a known document.
  case unknownDocument(DocumentURI)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)
}

extension SwiftLanguageServer {
  /// Provides typed variable declarations in a document.
  ///
  /// - Parameters:
  ///   - url: Document URL in which to perform the request. Must be an open document.
  ///   - completion: Completion block to asynchronously receive the VariableTypeInfos, or error.
  func variableTypeInfos(
    _ uri: DocumentURI,
    _ range: Range<Position>? = nil,
    _ completion: @escaping (Swift.Result<[VariableTypeInfo], VariableTypeInfoError>) -> Void
  ) async {
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
    if let compileCommand = await self.buildSettings(for: uri) {
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
}
