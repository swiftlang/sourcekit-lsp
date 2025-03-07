//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import LanguageServerProtocol

extension LocationsOrLocationLinksResponse {
  /// If this is the `locations` case, return the locations, otherwise return `nil`.
  package var locations: [Location]? {
    switch self {
    case .locations(let locations): return locations
    case .locationLinks: return nil
    }
  }
}
