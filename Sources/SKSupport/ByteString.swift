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

import TSCBasic
import Foundation

extension ByteString {

  /// Access the contents of `self` as `Data`. The contents are not copied, so it is not safe to
  /// store a reference to the data object.
  @inlinable
  public func withUnsafeData<R>(_ body: (Data) throws -> R) rethrows -> R {
    let contents = self.contents
    return try contents.withUnsafeBytes { buffer in
      guard let pointer = UnsafeMutableRawBufferPointer(mutating: buffer).baseAddress else {
        return try body(Data())
      }
      return try body(Data(bytesNoCopy: pointer, count: contents.count, deallocator: .none))
    }
  }
}
