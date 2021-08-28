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

public final class SKDResponseDictionary {
  public let dict: sourcekitd_variant_t
  let resp: SKDResponse

  public var sourcekitd: SourceKitD { return resp.sourcekitd }

  public init(_ dict: sourcekitd_variant_t, response: SKDResponse) {
    self.dict = dict
    self.resp = response
  }

  public subscript(key: sourcekitd_uid_t?) -> String? {
    return sourcekitd.api.variant_dictionary_get_string(dict, key).map(String.init(cString:))
  }
  public subscript(key: sourcekitd_uid_t?) -> Int? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_VARIANT_TYPE_INT64 {
      return Int(sourcekitd.api.variant_int64_get_value(value))
    } else {
      return nil
    }
  }
  public subscript(key: sourcekitd_uid_t?) -> Bool? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_VARIANT_TYPE_BOOL {
      return sourcekitd.api.variant_bool_get_value(value)
    } else {
      return nil
    }
  }
  public subscript(key: sourcekitd_uid_t?) -> sourcekitd_uid_t? {
    return sourcekitd.api.variant_dictionary_get_uid(dict, key)
  }
  public subscript(key: sourcekitd_uid_t?) -> SKDResponseArray? {
    let value = sourcekitd.api.variant_dictionary_get_value(dict, key)
    if sourcekitd.api.variant_get_type(value) == SOURCEKITD_VARIANT_TYPE_ARRAY {
      return SKDResponseArray(value, response: resp)
    } else {
      return nil
    }
  }
}

extension SKDResponseDictionary: CustomStringConvertible {
  public var description: String {
    let ptr = sourcekitd.api.variant_description_copy(dict)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
