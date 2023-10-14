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
public protocol CustomLogStringConvertible: CustomStringConvertible {
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
public class CustomLogStringConvertibleWrapper: NSObject {
  private let underlyingObject: any CustomLogStringConvertible

  fileprivate init(_ underlyingObject: any CustomLogStringConvertible) {
    self.underlyingObject = underlyingObject
  }

  public override var description: String {
    return underlyingObject.description
  }

  public var redactedDescription: String {
    underlyingObject.redactedDescription
  }
}

extension CustomLogStringConvertible {
  /// Returns an object that can be passed to OSLog, which will print the
  /// `redactedDescription` if logging of private information is disabled and
  /// will log `description` otherwise.
  public var forLogging: CustomLogStringConvertibleWrapper {
    return CustomLogStringConvertibleWrapper(self)
  }
}

extension String {
  /// A hash value that can be logged in a redacted description without
  /// disclosing any private information about the string.
  public var hashForLogging: String {
    return Insecure.MD5.hash(data: Data(self.utf8)).description
  }
}
