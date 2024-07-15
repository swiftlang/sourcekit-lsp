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

extension Array {
  /// Returns the element at the specified index if it is within the Array's
  /// bounds, otherwise `nil`.
  package subscript(safe index: Index) -> Element? {
    return index >= 0 && index < count ? self[index] : nil
  }
}
