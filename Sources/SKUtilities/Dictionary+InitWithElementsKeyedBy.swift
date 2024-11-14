//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKLogging

extension Dictionary {
  /// Create a new dictionary from the given elements, assuming that they all have a unique value identified by `keyedBy`.
  /// If two elements have the same key, log an error and choose the first value with that key.
  public init(elements: some Sequence<Value>, keyedBy: KeyPath<Value, Key>) {
    self = [:]
    self.reserveCapacity(elements.underestimatedCount)
    for element in elements {
      let key = element[keyPath: keyedBy]
      if let existingElement = self[key] {
        logger.error(
          "Found duplicate key \(String(describing: key)): \(String(describing: existingElement)) vs. \(String(describing: element))"
        )
        continue
      }
      self[key] = element
    }
  }
}
