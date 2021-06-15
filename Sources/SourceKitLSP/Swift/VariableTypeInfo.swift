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

  init?(_ dict: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = dict.sourcekitd.keys

    guard let offset: Int = dict[keys.variable_offset],
          let length: Int = dict[keys.variable_length],
          let startIndex = snapshot.positionOf(utf8Offset: offset),
          let endIndex = snapshot.positionOf(utf8Offset: offset + length),
          let printedType: String = dict[keys.variable_type] else {
      return nil
    }

    self.range = startIndex..<endIndex
    self.printedType = printedType
  }
}
