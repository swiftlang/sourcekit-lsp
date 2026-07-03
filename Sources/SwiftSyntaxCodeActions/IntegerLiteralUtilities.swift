//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

extension IntegerLiteralExprSyntax {
  /// Returns an (arbitrarily) "ideal" number of digits that should constitute
  /// a separator-delimited "group" in an integer literal.
  package var idealGroupSize: Int {
    switch self.radix {
    case .binary: return 4
    case .octal: return 3
    case .decimal: return 3
    case .hex: return 4
    #if RESILIENT_LIBRARIES
    @unknown default: return 3
    #endif
    }
  }

  /// Split the leading radix prefix from the value part of this integer literal.
  ///
  /// ```
  /// 10 -> ("", "10")
  /// 0xFFFF -> ("0x", "FFFF")
  /// 0o77 -> ("0o", "77")
  /// 0b1010101 -> ("0b", "1010101")
  /// ```
  package func split() -> (prefix: String, value: Substring) {
    let text = self.literal.text
    let radix = self.radix
    let literalPrefix = radix.literalPrefix
    return (literalPrefix, text.dropFirst(literalPrefix.count))
  }
}
