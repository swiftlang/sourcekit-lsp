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

import Basic

extension Result {

  /// Project out the .success value, or nil.
  public var success: Value? {
    switch self {
    case .success(let value):
      return value
    default:
      return nil
    }
  }

  /// Project out the .failure value, or nil.
  public var failure: ErrorType? {
    switch self {
    case .failure(let error):
      return error
    default:
      return nil
    }
  }
}

extension Result: Equatable where Value: Equatable, ErrorType: Equatable {

  @inlinable
  public static func ==(lhs: Result, rhs: Result) -> Bool {
    switch (lhs, rhs) {
    case (.success(let lhs), .success(let rhs)):
      return lhs == rhs
    case (.failure(let lhs), .failure(let rhs)):
      return lhs == rhs
    default:
      return false
    }
  }
}
