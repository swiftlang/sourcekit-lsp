//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import Foundation
import XCTest

class UTF8ByteTests: XCTestCase {
  func testCaseMapping() {
    func byte(_ character: Character) -> UTF8Byte {
      character.utf8.only!
    }
    struct BoundaryLetters {
      var lowercase: UTF8Byte
      var uppercase: UTF8Byte
    }

    let boundaryLetters: [BoundaryLetters] = [
      BoundaryLetters(lowercase: byte("a"), uppercase: byte("A")),
      BoundaryLetters(lowercase: byte("b"), uppercase: byte("B")),
      BoundaryLetters(lowercase: byte("y"), uppercase: byte("Y")),
      BoundaryLetters(lowercase: byte("z"), uppercase: byte("Z")),
    ]

    for boundaryLetter in boundaryLetters {
      XCTAssertTrue(boundaryLetter.uppercase.isUppercase)
      XCTAssertTrue(boundaryLetter.lowercase.isLowercase)
      XCTAssertTrue(!boundaryLetter.uppercase.isLowercase)
      XCTAssertTrue(!boundaryLetter.lowercase.isUppercase)

      XCTAssertEqual(boundaryLetter.uppercase.uppercasedUTF8Byte, boundaryLetter.uppercase)
      XCTAssertEqual(boundaryLetter.lowercase.uppercasedUTF8Byte, boundaryLetter.uppercase)

      XCTAssertEqual(boundaryLetter.uppercase.lowercasedUTF8Byte, boundaryLetter.lowercase)
      XCTAssertEqual(boundaryLetter.lowercase.lowercasedUTF8Byte, boundaryLetter.lowercase)
    }

    let boundarySymbols: [UTF8Byte] = [
      byte("A") - 1,
      byte("Z") + 1,
      byte("a") - 1,
      byte("z") + 1,
    ]
    for boundarySymbol in boundarySymbols {
      XCTAssertTrue(!boundarySymbol.isUppercase)
      XCTAssertTrue(!boundarySymbol.isLowercase)
      XCTAssertEqual(boundarySymbol.uppercasedUTF8Byte, boundarySymbol)
      XCTAssertEqual(boundarySymbol.lowercasedUTF8Byte, boundarySymbol)
    }
  }
}
