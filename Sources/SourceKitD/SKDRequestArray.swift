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

extension Array<SKDValue> {
  /// Create an `SKDRequestArray` from this array.
  public func skd(_ sourcekitd: SourceKitD) -> SKDRequestArray {
    let result = SKDRequestArray(sourcekitd: sourcekitd)
    for element in self {
      result.append(element)
    }
    return result
  }
}

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

  public func append(_ newValue: SKDValue) {
    switch newValue {
    case let newValue as String:
      sourcekitd.api.request_array_set_string(array, -1, newValue)
    case let newValue as Int:
      sourcekitd.api.request_array_set_int64(array, -1, Int64(newValue))
    case let newValue as sourcekitd_uid_t:
      sourcekitd.api.request_array_set_uid(array, -1, newValue)
    case let newValue as SKDRequestDictionary:
      sourcekitd.api.request_array_set_value(array, -1, newValue.dict)
    case let newValue as SKDRequestArray:
      sourcekitd.api.request_array_set_value(array, -1, newValue.array)
    case let newValue as Array<SKDValue>:
      self.append(newValue.skd(sourcekitd))
    case let newValue as Dictionary<sourcekitd_uid_t, SKDValue>:
      self.append(newValue.skd(sourcekitd))
    case let newValue as Optional<SKDValue>:
      if let newValue {
        self.append(newValue)
      }
    default:
      preconditionFailure("Unknown type conforming to SKDValueProtocol")
    }
  }

  public static func += (array: SKDRequestArray, other: some Sequence<SKDValue>) {
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
