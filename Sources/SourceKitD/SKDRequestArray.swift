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
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#endif

public final class SKDRequestArray {
  public let array: sourcekitd_object_t?
  public let sourcekitd: SourceKitD

  public init(_ array: sourcekitd_object_t? = nil, sourcekitd: SourceKitD) {
    self.array = array ?? sourcekitd.api.request_array_create(nil, 0)
    self.sourcekitd = sourcekitd
  }

  deinit {
    sourcekitd.api.request_release(array)
  }

  public func append(_ value: String) {
    sourcekitd.api.request_array_set_string(array, -1, value)
  }

  public func append(_ value: SKDRequestDictionary) {
    sourcekitd.api.request_array_set_value(array, -1, value.dict)
  }

  public static func += (array: SKDRequestArray, other: some Sequence<SKDRequestDictionary>) {
    for item in other {
      array.append(item)
    }
  }
}

extension SKDRequestArray: CustomStringConvertible {
  public var description: String {
    let ptr = sourcekitd.api.request_description_copy(array)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
