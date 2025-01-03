//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

package typealias UTF8Byte = UInt8
package extension UTF8Byte {
  init(_ character: Character) throws {
    self = try character.utf8.only.unwrap(orThrow: "More than one byte: \(character)")
  }
}

package func UTF8ByteValue(_ character: Character) -> UTF8Byte? {
  character.utf8.only
}

package extension UTF8Byte {
  static let uppercaseAZ: ClosedRange<UInt8> = (65...90)
  static let lowercaseAZ: ClosedRange<UInt8> = (97...122)

  static let cSpace: Self = 32  // ' '
  static let cPlus: Self = 43  // '+'
  static let cMinus: Self = 45  // '-'
  static let cColon: Self = 58  // ':'
  static let cPeriod: Self = 46  // '.'
  static let cLeftParentheses: Self = 40  // '('
  static let cRightParentheses: Self = 41  // ')'
  static let cUnderscore: Self = 95  // '_'

  var isLowercase: Bool {
    return Self.lowercaseAZ.contains(self)
  }

  var isUppercase: Bool {
    return Self.uppercaseAZ.contains(self)
  }

  var lowercasedUTF8Byte: UInt8 {
    return isUppercase ? (self - Self.uppercaseAZ.lowerBound) + Self.lowercaseAZ.lowerBound : self
  }

  var uppercasedUTF8Byte: UInt8 {
    return isLowercase ? (self - Self.lowercaseAZ.lowerBound) + Self.uppercaseAZ.lowerBound : self
  }

  var isDelimiter: Bool {
    return (self == .cSpace)
      || (self == .cPlus)
      || (self == .cMinus)
      || (self == .cColon)
      || (self == .cPeriod)
      || (self == .cUnderscore)
      || (self == .cLeftParentheses)
      || (self == .cRightParentheses)
  }
}
