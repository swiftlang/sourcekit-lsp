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

package import Csourcekitd

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

extension SourceKitD {
  /// Create a `SKDRequestArray` from the given array.
  nonisolated package func array(_ array: [any SKDRequestValue]) -> SKDRequestArray {
    let result = SKDRequestArray(sourcekitd: self)
    for element in array {
      result.append(element)
    }
    return result
  }
}

package final class SKDRequestArray: Sendable {
  nonisolated(unsafe) let array: sourcekitd_api_object_t
  private let sourcekitd: SourceKitD

  package init(_ array: sourcekitd_api_object_t? = nil, sourcekitd: SourceKitD) {
    self.array = array ?? sourcekitd.api.request_array_create(nil, 0)!
    self.sourcekitd = sourcekitd
  }

  deinit {
    sourcekitd.api.request_release(array)
  }

  package func append(_ newValue: any SKDRequestValue) {
    switch newValue {
    case let newValue as String:
      sourcekitd.api.request_array_set_string(array, -1, newValue)
    case let newValue as Int:
      sourcekitd.api.request_array_set_int64(array, -1, Int64(newValue))
    case let newValue as sourcekitd_api_uid_t:
      sourcekitd.api.request_array_set_uid(array, -1, newValue)
    case let newValue as SKDRequestDictionary:
      sourcekitd.api.request_array_set_value(array, -1, newValue.dict)
    case let newValue as SKDRequestArray:
      sourcekitd.api.request_array_set_value(array, -1, newValue.array)
    case let newValue as [any SKDRequestValue]:
      self.append(sourcekitd.array(newValue))
    case let newValue as [sourcekitd_api_uid_t: any SKDRequestValue]:
      self.append(sourcekitd.dictionary(newValue))
    case let newValue as (any SKDRequestValue)?:
      if let newValue {
        self.append(newValue)
      }
    default:
      preconditionFailure("Unknown type conforming to SKDRequestValue")
    }
  }

  package static func += (array: SKDRequestArray, other: some Sequence<any SKDRequestValue>) {
    for item in other {
      array.append(item)
    }
  }
}

extension SKDRequestArray: CustomStringConvertible {
  package var description: String {
    let ptr = sourcekitd.api.request_description_copy(array)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
