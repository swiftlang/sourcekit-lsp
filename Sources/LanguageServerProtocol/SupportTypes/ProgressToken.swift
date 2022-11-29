//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum ProgressToken: Codable, Hashable {
  case integer(Int)
  case string(String)

  public init(from decoder: Decoder) throws {
    if let integer = try? Int(from: decoder) {
      self = .integer(integer)
    } else if let string = try? String(from: decoder) {
      self = .string(string)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .integer(let integer):
      try integer.encode(to: encoder)
    case .string(let string):
      try string.encode(to: encoder)
    }
  }
}
