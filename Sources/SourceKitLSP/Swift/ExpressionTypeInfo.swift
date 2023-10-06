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
