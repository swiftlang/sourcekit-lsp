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
  public var arguments: [AnyCommandArgument]?

  public init(title: String, command: String, arguments: [AnyCommandArgument]?) {
    self.title = title
    self.command = command
    self.arguments = arguments
  }
}

public protocol CommandArgumentType: Codable, Hashable {}

extension Int: CommandArgumentType {}
extension Bool: CommandArgumentType {}
extension Double: CommandArgumentType {}
extension String: CommandArgumentType {}
extension Array: CommandArgumentType where Element: CommandArgumentType {}
extension Dictionary: CommandArgumentType where Key: CommandArgumentType, Value: CommandArgumentType {}

/// A type-erased `CommandArgumentType` value.
public struct AnyCommandArgument {
  public let value: Any?

  public init<T>(_ value: T?) {
    self.value = value
  }
}

extension AnyCommandArgument: Hashable {
  public static func == (lhs: AnyCommandArgument, rhs: AnyCommandArgument) -> Bool {
    switch (lhs.value, rhs.value) {
    case let (lhs as Int, rhs as Int):
      return lhs == rhs
    case let (lhs as Bool, rhs as Bool):
      return lhs == rhs
    case let (lhs as Double, rhs as Double):
      return lhs == rhs
    case let (lhs as String, rhs as String):
      return lhs == rhs
    case let (lhs as [AnyCommandArgument], rhs as [AnyCommandArgument]):
      return lhs == rhs
    case let (lhs as [AnyCommandArgument: AnyCommandArgument],
              rhs as [AnyCommandArgument: AnyCommandArgument]):
      return lhs == rhs
    default:
      return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch value {
    case let value as Int:
      value.hash(into: &hasher)
    case let value as Bool:
      value.hash(into: &hasher)
    case let value as Double:
      value.hash(into: &hasher)
    case let value as String:
      value.hash(into: &hasher)
    case let value as [AnyCommandArgument]:
      value.hash(into: &hasher)
    case let value as [AnyCommandArgument: AnyCommandArgument]:
      value.hash(into: &hasher)
    default:
      return
    }
  }
}

extension AnyCommandArgument: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Int.self) {
      self.init(value)
    } else if let value = try? container.decode(Bool.self) {
      self.init(value)
    } else if let value = try? container.decode(Double.self) {
      self.init(value)
    } else if let value = try? container.decode(String.self) {
      self.init(value)
    } else if let value = try? container.decode([AnyCommandArgument].self) {
      self.init(value)
    } else if let value = try? container.decode([AnyCommandArgument: AnyCommandArgument].self) {
      self.init(value)
    } else {
      let error = "AnyCommandArgument cannot be decoded: Unrecognized type."
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error)
    }
  }
}

extension AnyCommandArgument: Encodable {
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case let value as Int:
      try container.encode(value)
    case let value as Bool:
      try container.encode(value)
    case let value as Double:
      try container.encode(value)
    case let value as String:
      try container.encode(value)
    case let value as [AnyCommandArgument]:
      try container.encode(value)
    case let value as [AnyCommandArgument: AnyCommandArgument]:
      try container.encode(value)
    default:
      let error = "AnyCommandArgument cannot be encoded: Unrecognized type."
      let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: error)
      throw EncodingError.invalidValue(value as Any, context)
    }
  }
}

extension AnyCommandArgument: ExpressibleByIntegerLiteral {}
extension AnyCommandArgument: ExpressibleByBooleanLiteral {}
extension AnyCommandArgument: ExpressibleByFloatLiteral {}
extension AnyCommandArgument: ExpressibleByStringLiteral {}
extension AnyCommandArgument: ExpressibleByArrayLiteral {}
extension AnyCommandArgument: ExpressibleByDictionaryLiteral {}

extension AnyCommandArgument {
  public init(integerLiteral value: Int) {
    self.init(value)
  }

  public init(booleanLiteral value: Bool) {
    self.init(value)
  }

  public init(floatLiteral value: Double) {
    self.init(value)
  }

  public init(extendedGraphemeClusterLiteral value: String) {
    self.init(value)
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public init(arrayLiteral elements: Any...) {
    self.init(elements)
  }

  public init(dictionaryLiteral elements: (AnyHashable, Any)...) {
    self.init(elements)
  }
}
