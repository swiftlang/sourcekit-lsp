//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class CodingTests: XCTestCase {
  func testMillisecondsSince1970Date() throws {
    struct WithDate: Codable, Equatable {
      @CustomCodable<MillisecondsSince1970Date>
      var date: Date
    }

    checkCoding(
      WithDate(date: Date(timeIntervalSince1970: 12.3)),
      json: """
        {
          "date" : 12300
        }
        """
    )

    // Check that the encoded date is an integer, not a double
    checkEncoding(
      WithDate(date: Date(timeIntervalSince1970: 12.34567)),
      json: """
        {
          "date" : 12346
        }
        """
    )
  }

  func testOptionalMillisecondsSince1970Date() throws {
    struct WithDate: Codable, Equatable {
      @CustomCodable<MillisecondsSince1970Date?>
      var date: Date?
    }

    checkCoding(
      WithDate(date: Date(timeIntervalSince1970: 12.3)),
      json: """
        {
          "date" : 12300
        }
        """
    )

    checkCoding(
      WithDate(date: nil),
      json: """
        {

        }
        """
    )
  }
}
