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

/// Representation of 'any' in the Language Server Protocol, which is equivalent
/// to an arbitrary JSON value.
public enum LSPAny: Hashable {
  case null
  case int(Int)
  case bool(Bool)
  case double(Double)
  case string(String)
  case array([LSPAny])
  case dictionary([String: LSPAny])
}

extension LSPAny: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([LSPAny].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: LSPAny].self) {
      self = .dictionary(value)
    } else {
      let error = "LSPAny cannot be decoded: Unrecognized type."
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
    }
  }
}

extension LSPAny: Encodable {
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .int(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .dictionary(let value):
      try container.encode(value)
    }
  }
}

extension LSPAny: ResponseType {}

extension LSPAny: ExpressibleByNilLiteral {
  public init(nilLiteral _: ()) {
    self = .null
  }
}

extension LSPAny: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .int(value)
  }
}

extension LSPAny: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension LSPAny: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .double(value)
  }
}

extension LSPAny: ExpressibleByStringLiteral {
  public init(extendedGraphemeClusterLiteral value: String) {
    self = .string(value)
  }

  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension LSPAny: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: LSPAny...) {
    self = .array(elements)
  }
}

extension LSPAny: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, LSPAny)...) {
    let dict  = [String: LSPAny](elements, uniquingKeysWith: { first, _ in first })
    self = .dictionary(dict)
  }
}

public protocol LSPAnyCodable {
  init?(fromLSPDictionary dictionary: [String: LSPAny])
  func encodeToLSPAny() -> LSPAny
}

extension Optional: LSPAnyCodable where Wrapped: LSPAnyCodable {
  public init?(fromLSPAny value: LSPAny) {
    if case .null = value {
      self = .none
      return
    }
    guard case .dictionary(let dict) = value else {
      return nil
    }
    guard let wrapped = Wrapped.init(fromLSPDictionary: dict) else {
      return nil
    }
    self = .some(wrapped)
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    return nil
  }

  public func encodeToLSPAny() -> LSPAny {
    guard let wrapped = self else { return .null }
    return wrapped.encodeToLSPAny()
  }
}

extension Array: LSPAnyCodable where Element: LSPAnyCodable {
  public init?(fromLSPArray array: LSPAny) {
    guard case .array(let array) = array else {
      return nil
    }
    var result = [Element]()
    for case .dictionary(let editDict) in array {
      guard let element = Element.init(fromLSPDictionary: editDict) else {
        return nil
      }
      result.append(element)
    }
    self = result
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    return nil
  }

  public func encodeToLSPAny() -> LSPAny {
    return .array(map { $0.encodeToLSPAny() })
  }
}

public typealias LSPObject = [String: LSPAny]
public typealias LSPArray = [LSPAny]
