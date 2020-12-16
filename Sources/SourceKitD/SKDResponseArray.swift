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
#if canImport(Glibc)
import Glibc
#endif

public final class SKDResponseArray {
  public let array: sourcekitd_variant_t
  let resp: SKDResponse

  public var sourcekitd: SourceKitD { return resp.sourcekitd }

  public init(_ array: sourcekitd_variant_t, response: SKDResponse) {
    self.array = array
    self.resp = response
  }

  public var count: Int { return sourcekitd.api.variant_array_get_count(array) }

  /// If the `applier` returns `false`, iteration terminates.
  @discardableResult
  public func forEach(_ applier: (Int, SKDResponseDictionary) -> Bool) -> Bool {
    for i in 0..<count {
      if !applier(i, SKDResponseDictionary(sourcekitd.api.variant_array_get_value(array, i), response: resp)) {
        return false
      }
    }
    return true
  }

  /// Attempt to access the item at `index` as a string.
  public subscript(index: Int) -> String? {
    if let cstr = sourcekitd.api.variant_array_get_string(array, index) {
      return String(cString: cstr)
    }
    return nil
  }
}

extension SKDResponseArray: CustomStringConvertible {
  public var description: String {
    let ptr = sourcekitd.api.variant_description_copy(array)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
