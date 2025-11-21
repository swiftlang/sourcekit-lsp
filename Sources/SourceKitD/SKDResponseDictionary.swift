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

package final class SKDResponseDictionary: Sendable {
  private let dict: sourcekitd_api_variant_t
  private let resp: SKDResponse

  package var sourcekitd: SourceKitD { return resp.sourcekitd }

  package init(_ dict: sourcekitd_api_variant_t, response: SKDResponse) {
    self.dict = dict
    self.resp = response
  }

  package subscript(key: sourcekitd_api_uid_t) -> String? {
    guard let cString = sourcekitd.api.variant_dictionary_get_string(dict, key) else {
      return nil
    }
    return String(cString: cString)
  }

  package subscript(key: sourcekitd_api_uid_t) -> Int? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_API_VARIANT_TYPE_INT64 {
      return Int(sourcekitd.api.variant_int64_get_value(value))
    } else {
      return nil
    }
  }

  package subscript(key: sourcekitd_api_uid_t) -> Bool? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_API_VARIANT_TYPE_BOOL {
      return sourcekitd.api.variant_bool_get_value(value)
    } else {
      return nil
    }
  }

  public subscript(key: sourcekitd_api_uid_t) -> Double? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_API_VARIANT_TYPE_DOUBLE {
      return sourcekitd.api.variant_double_get_value!(value)
    } else {
      return nil
    }
  }

  package subscript(key: sourcekitd_api_uid_t) -> sourcekitd_api_uid_t? {
    return sourcekitd.api.variant_dictionary_get_uid(dict, key)
  }

  package subscript(key: sourcekitd_api_uid_t) -> SKDResponseArray? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_API_VARIANT_TYPE_ARRAY {
      return SKDResponseArray(value, response: resp)
    } else {
      return nil
    }
  }
}

extension SKDResponseDictionary: CustomStringConvertible {
  package var description: String {
    let ptr = sourcekitd.api.variant_description_copy(dict)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
