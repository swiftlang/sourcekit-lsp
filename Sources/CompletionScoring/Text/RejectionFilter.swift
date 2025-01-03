//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A `RejectionFilter` can quickly rule out two byte strings matching with a simple bitwise and.
/// It's the first, most aggressive, and cheapest filter used in matching.
///
/// -- The Mask --
/// It's 32 bits. Conceptually it uses 26 bits to represent `a...z`. If the letter corresponding
/// to a byte was present in the candidate, it's bit is set in the filter.
///
/// The filter is case insensitive, so making a filter from "abc" produces the same filter as one
/// produced from "AbC".
///
/// Computing ranges in the alphabet is a bottle neck, and a filter will work as long as it's case
/// insensitive for ascii. So instead of mapping `a...z` to `0...25` we map the lower 5 bits of the
/// byte to (0...31), and then shift 1 by that amount to map all bytes to a bit in a way that is
/// both case preserving, and very cheap to compute.
///
/// -- The Filter --
/// For a pattern to match a candidate, all bytes in the pattern must be in the candidate in the
/// same order - ascii case insensitive. If you have a mask for the pattern and candidate, then
/// if any bits from the pattern mask aren't in the candidate mask, they can't possibly satisfy
/// the stricter matching criteria.
///
/// If every bit in the pattern mask is also in the candidate mask it might match the candidate.
/// Examples of cases where it still wouldn't match:
///     * Character occurs 2 times in pattern, but 1 time in candidate
///     * Character in pattern are in different order from candidate
///     * Multiple distinct pattern characters mapped to the same bit, and only one of them was
///       in the candidate. For example, both '8' and 'x' map to the same bit.
package struct RejectionFilter {
  package enum Match {
    case no
    case maybe
  }

  private var mask: UInt32 = 0
  static var empty: Self {
    .init(mask: 0)
  }

  private func maskBit(byte: UTF8Byte) -> UInt32 {
    // This mapping relies on the fact that the ascii values for a...z and A...Z
    // are equivalent modulo 32, and since that's a power of 2, we can extract
    // a bunch of information about that with shifts and masks.
    // The comments below refer to each of these groups of 32 values as "bands"

    // The last 5 bits of the byte fulfill the following properties:
    //  - Every character in a...z has a unique value
    //  - The value of an uppercase character is the same as the corresponding lowercase character
    let lowerFiveBits = UInt32(1) << UInt32(byte & 0b0001_1111)

    // We want to minimize aliasing between a-z values with other values with the same lower 5 bits.
    // Start with their 6th bit, which will be zero for many of the non-alpha bands.
    let hasAlphaBandBit = UInt32(byte & 0b0100_0000) >> 6

    // Multiply their lower five bits by that value to map them to either themselves, or 0.
    // This eliminates aliasing between 'z' and ':', 'h' and '(', and ')' and 'i', which commonly
    // occur in filter text.
    let mask = lowerFiveBits * hasAlphaBandBit

    // Ensure that every byte sets at least one bit, by always setting 0b01.
    // That bit is never set for a-z because a is the second character in its band.
    //
    // Technically we don't need this, but without it you get surprising but not wrong results like
    // all characters outside of the alpha bands return `.maybe` for matching either the empty string,
    // or characters inside the alpha bands.
    return mask | 0b01
  }

  package init<Bytes: Collection>(bytes: Bytes) where Bytes.Element == UTF8Byte {
    for byte in bytes {
      mask = mask | maskBit(byte: byte)
    }
  }

  package init<Bytes: Collection>(lowercaseBytes: Bytes) where Bytes.Element == UTF8Byte {
    for byte in lowercaseBytes {
      mask = mask | maskBit(byte: byte)
    }
  }

  private init(mask: UInt32) {
    self.mask = mask
  }

  package init(lowercaseByte: UTF8Byte) {
    mask = maskBit(byte: lowercaseByte)
  }

  package init(string: String) {
    self.init(bytes: string.utf8)
  }

  package static func match(pattern: RejectionFilter, candidate: RejectionFilter) -> Match {
    return (pattern.mask & candidate.mask) == pattern.mask ? .maybe : .no
  }

  func contains(candidateByte: UTF8Byte) -> Match {
    let candidateMask = maskBit(byte: candidateByte)
    return (mask & candidateMask) == candidateMask ? .maybe : .no
  }

  mutating func formUnion(_ rhs: Self) {
    mask = mask | rhs.mask
  }

  mutating func formUnion(lowercaseByte: UTF8Byte) {
    mask = mask | maskBit(byte: lowercaseByte)
  }
}

extension RejectionFilter: CustomStringConvertible {
  package var description: String {
    let base = String(mask, radix: 2)
    return "0b" + String(repeating: "0", count: mask.bitWidth - base.count) + base
  }
}

extension RejectionFilter: Equatable {
  package static func == (lhs: RejectionFilter, rhs: RejectionFilter) -> Bool {
    lhs.mask == rhs.mask
  }
}
