//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

final class LocationSortKeyTests: SourceKitLSPTestCase {
  /// `LocationSortKey` must order locations exactly like `Location.<`.
  func testOrderingMatchesLocation() throws {
    let uris = [
      try DocumentURI(string: "file:///project/b.swift"),
      try DocumentURI(string: "file:///project/a.swift"),
      // Same file as `a.swift` but spelled with a percent-encoded character.
      try DocumentURI(string: "file:///project/%61.swift"),
      try DocumentURI(string: "file:///project/a%20b.swift"),
      try DocumentURI(string: "untitled:Untitled-1"),
      try DocumentURI(string: "untitled:Untitled-2"),
    ]
    let ranges = [
      Position(line: 2, utf16index: 0)..<Position(line: 2, utf16index: 4),
      Position(line: 1, utf16index: 3)..<Position(line: 1, utf16index: 5),
      Position(line: 1, utf16index: 3)..<Position(line: 1, utf16index: 4),
      Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
    ]
    let locations = uris.flatMap { uri in ranges.map { Location(uri: uri, range: $0) } }

    for lhs in locations {
      for rhs in locations {
        XCTAssertEqual(
          LocationSortKey(lhs) < LocationSortKey(rhs),
          lhs < rhs,
          "Different ordering for \(lhs) and \(rhs)"
        )
      }
    }
    XCTAssertEqual(locations.sorted(byLocation: \.self), locations.sorted())
  }
}
