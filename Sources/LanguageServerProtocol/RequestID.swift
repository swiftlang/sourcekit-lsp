//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum RequestID: Hashable{
  case string(String)
  case number(Int)
}

extension RequestID: Codable {
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let intValue = try? value.decode(Int.self) {
      self = .number(intValue)
    } else if let strValue = try? value.decode(String.self) {
      self = .string(strValue)
    } else {
      throw MessageDecodingError.invalidRequest("could not decode request id")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    }
  }
}

extension RequestID: CustomStringConvertible {
  public var description: String {
    switch self {
    case .number(let n): return String(n)
    case .string(let s): return "\"\(s)\""
    }
  }
}
