//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Crypto
import Foundation

/// An object that can printed for logging and also offers a redacted description
/// when logging in contexts in which private information shouldn't be captured.
package protocol CustomLogStringConvertible: CustomStringConvertible, Sendable {
  /// A full description of the object.
  var description: String { get }

  /// A description of the object that doesn't contain any private information.
  var redactedDescription: String { get }
}

/// When an NSObject is logged with OSLog in private mode and the object
/// implements `redactedDescription`, OSLog will log that information instead of
/// just logging `<private>`.
///
/// There currently is no way to get equivalent functionality in pure Swift. We
/// thus pass this object to OSLog, which just forwards to `description` or
/// `redactedDescription` of an object that implements `CustomLogStringConvertible`.
package final class CustomLogStringConvertibleWrapper: NSObject, Sendable {
  private let underlyingObject: any CustomLogStringConvertible

  fileprivate init(_ underlyingObject: any CustomLogStringConvertible) {
    self.underlyingObject = underlyingObject
  }

  package override var description: String {
    return underlyingObject.description
  }

  #if canImport(os)
  // When using OSLog mark redactedDescription as @objc so that OSLog can find it via the Objective-C runtime.
  // We can't unconditionally mark it as @objc because eg. Linux doesn't have the Objective-C runtime.
  @objc
  #endif
  package var redactedDescription: String {
    underlyingObject.redactedDescription
  }
}

extension CustomLogStringConvertible {
  /// Returns an object that can be passed to OSLog, which will print the
  /// `redactedDescription` if logging of private information is disabled and
  /// will log `description` otherwise.
  package var forLogging: CustomLogStringConvertibleWrapper {
    return CustomLogStringConvertibleWrapper(self)
  }
}

extension String {
  /// A hash value that can be logged in a redacted description without
  /// disclosing any private information about the string.
  package var hashForLogging: String {
    return Insecure.MD5.hash(data: Data(self.utf8)).description
  }
}

private struct OptionalWrapper<Wrapped>: CustomLogStringConvertible where Wrapped: CustomLogStringConvertible {
  let optional: Optional<Wrapped>

  package var description: String {
    return optional?.description ?? "<nil>"
  }

  package var redactedDescription: String {
    return optional?.redactedDescription ?? "<nil>"
  }
}

extension Optional where Wrapped: CustomLogStringConvertible {
  package var forLogging: CustomLogStringConvertibleWrapper {
    return CustomLogStringConvertibleWrapper(OptionalWrapper(optional: self))
  }
}

/// A JSON-like description of the object.
public func recursiveDescription(of subject: Any) -> String {
  return "{"
    + Mirror(reflecting: subject).children.map { (key, value) in
      "\(key ?? "<nil>"): \(String(describing: value))"
    }.joined(separator: ", ")
    + "}"
}

fileprivate protocol OptionalProtocol {
  associatedtype Wrapped
  var asOptional: Wrapped? { get }
}
extension Optional: OptionalProtocol {
  var asOptional: Wrapped? { self }
}

/// A JSON-like description of the object that shows trivial values but redacts values that might contain sensitive
/// information.
public func recursiveRedactedDescription(of value: Any) -> String {
  switch value {
  case let value as Bool:
    return value.description
  case let value as Int:
    return value.description
  case let value as Double:
    return value.description
  case let value as String:
    return value.hashForLogging
  case let value as any OptionalProtocol:
    if let value = value.asOptional {
      return recursiveRedactedDescription(of: value)
    } else {
      return "nil"
    }
  default:
    break
  }

  let children = Mirror(reflecting: value).children.sorted { $0.label ?? "" < $1.label ?? "" }
  if !children.isEmpty {
    let childrenKeyValuePairs = children.map { (label, value) -> String in
      let label = label ?? "<nil>"
      let value =
        if let value = value as? any CustomLogStringConvertible {
          value.redactedDescription
        } else {
          recursiveRedactedDescription(of: value)
        }
      return "\(label): \(value)"
    }
    return "{" + childrenKeyValuePairs.joined(separator: ", ") + "}"
  }
  return "<private>"
}
