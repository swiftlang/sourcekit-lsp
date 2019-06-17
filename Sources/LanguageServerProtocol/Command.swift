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
import class Foundation.NSNull

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

public enum CommandArgumentType {
  case null
  case int(Int)
  case bool(Bool)
  case double(Double)
  case string(String)
  case array([CommandArgumentType])
  case dictionary([String: CommandArgumentType])
}

extension CommandArgumentType: Hashable {
  public static func == (lhs: CommandArgumentType, rhs: CommandArgumentType) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null):
      return true
    case let (.int(lhs), .int(rhs)):
      return lhs == rhs
    case let (.bool(lhs), .bool(rhs)):
      return lhs == rhs
    case let (.double(lhs), .double(rhs)):
      return lhs == rhs
    case let (.string(lhs), .string(rhs)):
      return lhs == rhs
    case let (.array(lhs), .array(rhs)):
      return lhs == rhs
    case let (.dictionary(lhs), .dictionary(rhs)):
      return lhs == rhs
    default:
      return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch self {
    case .null:
      NSNull().hash(into: &hasher)
    case let .int(value):
      value.hash(into: &hasher)
    case let .bool(value):
      value.hash(into: &hasher)
    case let .double(value):
      value.hash(into: &hasher)
    case let .string(value):
      value.hash(into: &hasher)
    case let .array(value):
      value.hash(into: &hasher)
    case let .dictionary(value):
      value.hash(into: &hasher)
    }
  }
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
    case let .int(value):
      try container.encode(value)
    case let .bool(value):
      try container.encode(value)
    case let .double(value):
      try container.encode(value)
    case let .string(value):
      try container.encode(value)
    case let .array(value):
      try container.encode(value)
    case let .dictionary(value):
      try container.encode(value)
    }
  }
}

extension CommandArgumentType: ExpressibleByNilLiteral {}
extension CommandArgumentType: ExpressibleByIntegerLiteral {}
extension CommandArgumentType: ExpressibleByBooleanLiteral {}
extension CommandArgumentType: ExpressibleByFloatLiteral {}
extension CommandArgumentType: ExpressibleByStringLiteral {}
extension CommandArgumentType: ExpressibleByArrayLiteral {}
extension CommandArgumentType: ExpressibleByDictionaryLiteral {}

extension CommandArgumentType {
  public init(nilLiteral _: ()) {
    self = .null
  }

  public init(integerLiteral value: Int) {
    self = .int(value)
  }

  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }

  public init(floatLiteral value: Double) {
    self = .double(value)
  }

  public init(extendedGraphemeClusterLiteral value: String) {
    self = .string(value)
  }

  public init(stringLiteral value: String) {
    self = .string(value)
  }

  public init(arrayLiteral elements: CommandArgumentType...) {
    self = .array(elements)
  }

  public init(dictionaryLiteral elements: (String, CommandArgumentType)...) {
    let dict  = [String: CommandArgumentType](elements, uniquingKeysWith: { first, _ in first })
    self = .dictionary(dict)
  }
}
