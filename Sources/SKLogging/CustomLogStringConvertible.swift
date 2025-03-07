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

package import Foundation

#if !NO_CRYPTO_DEPENDENCY
import Crypto
#endif

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
    #if NO_CRYPTO_DEPENDENCY
    return "<private>"
    #else
    let hash = SHA256.hash(data: Data(self.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    return "<private \(hash)>"
    #endif
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

extension Encodable {
  package var prettyPrintedJSON: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self) else {
      return "\(self)"
    }
    guard let string = String(data: data, encoding: .utf8) else {
      return "\(self)"
    }
    // Don't escape '/'. Most JSON readers don't need it escaped and it makes
    // paths a lot easier to read and copy-paste.
    return string.replacingOccurrences(of: "\\/", with: "/")
  }

  package var prettyPrintedRedactedJSON: String {
    func redact(subject: Any) -> Any {
      if let subject = subject as? [String: Any] {
        return subject.mapValues { redact(subject: $0) }
      } else if let subject = subject as? [Any] {
        return subject.map { redact(subject: $0) }
      } else if let subject = subject as? String {
        return subject.hashForLogging
      } else if let subject = subject as? Int {
        return subject
      } else if let subject = subject as? Double {
        return subject
      } else if let subject = subject as? Bool {
        return subject
      } else {
        return "<private>"
      }
    }

    guard let encoded = try? JSONEncoder().encode(self),
      let jsonObject = try? JSONSerialization.jsonObject(with: encoded),
      let data = try? JSONSerialization.data(
        withJSONObject: redact(subject: jsonObject),
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      ),
      let string = String(data: data, encoding: .utf8)
    else {
      return "<private>"
    }
    return string
  }
}
