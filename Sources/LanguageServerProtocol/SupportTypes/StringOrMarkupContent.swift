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

public enum StringOrMarkupContent: Codable, Hashable {
  case string(String)
  case markupContent(MarkupContent)

  public init(from decoder: Decoder) throws {
    if let string = try? String(from: decoder) {
      self = .string(string)
    } else if let markupContent = try? MarkupContent(from: decoder) {
      self = .markupContent(markupContent)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or MarkupContent")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let string):
      try string.encode(to: encoder)
    case .markupContent(let markupContent):
      try markupContent.encode(to: encoder)
    }
  }
}
