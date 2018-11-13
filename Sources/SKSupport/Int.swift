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

import SPMLibc

extension UInt8 {
  @inlinable
  public var isSpace: Bool {
    return isspace(Int32(self)) != 0
  }

  @inlinable
  public var isDigit: Bool {
   return isdigit(Int32(self)) != 0
  }

  @inlinable
  public var asciiDigit: Int {
    precondition(isDigit)
    return Int(self - UInt8(ascii: "0"))
  }
}

extension Int {

  /// Constructs an integer from a buffer of base-10 ascii digits, ignoring any surrounding whitespace.
  ///
  /// This is similar to `atol` but with several advantages:
  /// - no need to construct a null-terminated C string
  /// - overflow will trap instead of being undefined
  /// - does not allow non-whitespace characters at the end
  @inlinable
  public init?<C>(ascii buffer: C) where C: Collection, C.Element == UInt8 {
    guard !buffer.isEmpty else { return nil }

    // Trim leading whitespace.
    var i = buffer.startIndex
    while i != buffer.endIndex, buffer[i].isSpace {
      i = buffer.index(after: i)
    }

    guard i != buffer.endIndex else { return nil }

    // Check sign if any.
    var sign = 1
    if buffer[i] == UInt8(ascii: "+") {
      i = buffer.index(after: i)
    } else if buffer[i] == UInt8(ascii: "-") {
      i = buffer.index(after: i)
      sign = -1
    }

    guard i != buffer.endIndex, buffer[i].isDigit else { return nil }

    // Accumulate the result.
    var result = 0
    while i != buffer.endIndex, buffer[i].isDigit {
      result = result * 10 + sign * buffer[i].asciiDigit
      i = buffer.index(after: i)
    }

    // Trim trailing whitespace.
    while i != buffer.endIndex {
      if !buffer[i].isSpace { return nil }
      i = buffer.index(after: i)
    }
    self = result
  }

  // Constructs an integer from a buffer of base-10 ascii digits, ignoring any surrounding whitespace.
  ///
  /// This is similar to `atol` but with several advantages:
  /// - no need to construct a null-terminated C string
  /// - overflow will trap instead of being undefined
  /// - does not allow non-whitespace characters at the end
  @inlinable
  public init?<S>(ascii buffer: S) where S: StringProtocol {
    self.init(ascii: buffer.utf8)
  }
}
