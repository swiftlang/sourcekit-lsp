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

@_spi(SourceKitLSP) package import LanguageServerProtocol

/// The values that `Location.<` compares, computed once per location.
///
/// Comparing `DocumentURI`s computes their file system paths, which is expensive, so sorting by `Location` directly
/// computes them twice for every comparison.
package struct LocationSortKey {
  private let scheme: String?
  private let pseudoPath: String
  private let uriString: String
  private let range: Range<Position>

  package init(_ location: Location) {
    self.scheme = location.uri.scheme
    self.pseudoPath = location.uri.pseudoPath
    self.uriString = location.uri.stringValue
    self.range = location.range
  }

  /// Same ordering as `Location.<`.
  package static func < (lhs: LocationSortKey, rhs: LocationSortKey) -> Bool {
    if lhs.scheme != rhs.scheme || lhs.pseudoPath != rhs.pseudoPath {
      return lhs.uriString < rhs.uriString
    }
    if lhs.range.lowerBound != rhs.range.lowerBound {
      return lhs.range.lowerBound < rhs.range.lowerBound
    }
    return lhs.range.upperBound < rhs.range.upperBound
  }
}

extension Sequence {
  /// Equivalent to `sorted { location($0) < location($1) }`. Prefer this method because it computes the file system
  /// path of each element's URI once instead of twice per comparison.
  package func sorted(byLocation location: (Element) -> Location) -> [Element] {
    return self.map { (element: $0, locationKey: LocationSortKey(location($0))) }
      .sorted { $0.locationKey < $1.locationKey }
      .map(\.element)
  }
}
