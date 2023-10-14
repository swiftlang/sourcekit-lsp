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

import Foundation

/// A wrapper around `Error` that conforms to `CustomLogStringConvertible`.
private struct MaskedError: CustomLogStringConvertible {
  let underlyingError: any Error

  init(_ underlyingError: any Error) {
    self.underlyingError = underlyingError
  }

  var description: String {
    return "\(underlyingError)"
  }

  var redactedDescription: String {
    let error = underlyingError as NSError
    return "\(error.code): \(error.description.hashForLogging)"
  }
}

extension Error {
  /// A version of the error that can be used for logging and will only log the
  /// error code and a hash of the description in privacy-sensitive contexts.
  public var forLogging: CustomLogStringConvertibleWrapper {
    if let error = self as? CustomLogStringConvertible {
      return error.forLogging
    } else {
      return MaskedError(self).forLogging
    }
  }
}
