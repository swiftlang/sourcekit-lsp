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

import SKSupport

/// Represents a reference to a command identified by a string. Used as the result of
/// requests that returns actions to the user, later used as the parameter of
/// workspace/executeCommand if the user wishes to execute said command.
public struct Command: Codable, Hashable {

  /// The title of this command.
  public var title: String

  /// The internal identifier of this command.
  public var command: String

  /// The arguments related to this command.
  public var arguments: [CommandArgumentType]?

  public init(title: String, command: String, arguments: [CommandArgumentType]?) {
    self.title = title
    self.command = command
    self.arguments = arguments
  }
}

public enum CommandArgumentType: Hashable, ResponseType {
  case null
  case int(Int)
  case bool(Bool)
  case double(Double)
  case string(String)
  case array([CommandArgumentType])
  case dictionary([String: CommandArgumentType])
}

extension CommandArgumentType: Decodable {
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
    } else if let value = try? container.decode([CommandArgumentType].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: CommandArgumentType].self) {
      self = .dictionary(value)
    } else {
      let error = "AnyCommandArgument cannot be decoded: Unrecognized type."
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
    }
  }
}

extension CommandArgumentType: Encodable {
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

extension CommandArgumentType: ExpressibleByNilLiteral {
  public init(nilLiteral _: ()) {
    self = .null
  }
}

extension CommandArgumentType: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .int(value)
  }
}

extension CommandArgumentType: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension CommandArgumentType: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .double(value)
  }
}

extension CommandArgumentType: ExpressibleByStringLiteral {
  public init(extendedGraphemeClusterLiteral value: String) {
    self = .string(value)
  }

  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension CommandArgumentType: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: CommandArgumentType...) {
    self = .array(elements)
  }
}

extension CommandArgumentType: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, CommandArgumentType)...) {
    let dict  = [String: CommandArgumentType](elements, uniquingKeysWith: { first, _ in first })
    self = .dictionary(dict)
  }
}
