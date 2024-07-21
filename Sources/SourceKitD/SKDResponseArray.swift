//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#elseif canImport(Bionic)
import Bionic
#endif

package final class SKDResponseArray: Sendable {
  private let array: sourcekitd_api_variant_t
  private let resp: SKDResponse

  package var sourcekitd: SourceKitD { return resp.sourcekitd }

  package init(_ array: sourcekitd_api_variant_t, response: SKDResponse) {
    self.array = array
    self.resp = response
  }

  package var count: Int { return sourcekitd.api.variant_array_get_count(array) }

  /// If the `applier` returns `false`, iteration terminates.
  @discardableResult
  package func forEach(_ applier: (Int, SKDResponseDictionary) throws -> Bool) rethrows -> Bool {
    for i in 0..<count {
      if try !applier(i, SKDResponseDictionary(sourcekitd.api.variant_array_get_value(array, i), response: resp)) {
        return false
      }
    }
    return true
  }

  /// If the `applier` returns `false`, iteration terminates.
  @discardableResult
  package func forEachUID(_ applier: (Int, sourcekitd_api_uid_t) throws -> Bool) rethrows -> Bool {
    for i in 0..<count {
      if let uid = sourcekitd.api.variant_array_get_uid(array, i), try !applier(i, uid) {
        return false
      }
    }
    return true
  }

  package func map<T>(_ transform: (SKDResponseDictionary) throws -> T) rethrows -> [T] {
    var result: [T] = []
    result.reserveCapacity(self.count)
    try self.forEach { _, element in
      result.append(try transform(element))
      return true
    }
    return result
  }

  package func compactMap<T>(_ transform: (SKDResponseDictionary) throws -> T?) rethrows -> [T] {
    var result: [T] = []
    try self.forEach { _, element in
      if let transformed = try transform(element) {
        result.append(transformed)
      }
      return true
    }
    return result
  }

  /// Attempt to access the item at `index` as a string.
  package subscript(index: Int) -> String? {
    if let cstr = sourcekitd.api.variant_array_get_string(array, index) {
      return String(cString: cstr)
    }
    return nil
  }
}

extension SKDResponseArray: CustomStringConvertible {
  package var description: String {
    let ptr = sourcekitd.api.variant_description_copy(array)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
