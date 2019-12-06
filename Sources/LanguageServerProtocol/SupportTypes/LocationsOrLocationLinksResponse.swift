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

public enum LocationsOrLocationLinksResponse: ResponseType, Hashable {
  case locations([Location])
  case locationLinks([LocationLink])

  public init(from decoder: Decoder) throws {
    if let locations = try? [Location](from: decoder) {
      self = .locations(locations)
    } else if let locationLinks = try? [LocationLink](from: decoder) {
      self = .locationLinks(locationLinks)
    } else if let location = try? Location(from: decoder) {
      // Fallback: Decode single location as array with one element
      self = .locations([location])
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected [Location], [LocationLink], or Location")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .locations(let locations):
      try locations.encode(to: encoder)
    case .locationLinks(let locationLinks):
      try locationLinks.encode(to: encoder)
    }
  }
}

