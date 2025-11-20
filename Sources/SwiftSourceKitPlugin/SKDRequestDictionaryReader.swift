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

import Csourcekitd
import SourceKitD

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

/// Provide getters to get values of a sourcekitd request dictionary.
///
/// This is not part of the `SourceKitD` module because it uses `SourceKitD.servicePluginAPI` which must not be accessed
/// outside of the service plugin.
final class SKDRequestDictionaryReader: Sendable, CustomStringConvertible {
  private nonisolated(unsafe) let dict: sourcekitd_api_object_t
  let sourcekitd: SourceKitD

  var description: String {
    guard let description = sourcekitd.api.request_description_copy(dict) else {
      return "getting request description failed"
    }
    defer { free(description) }
    return String(cString: description)
  }

  /// Creates an `SKDRequestDictionary` that essentially provides a view into the given opaque
  /// `sourcekitd_api_object_t`.
  init?(_ request: sourcekitd_api_object_t, sourcekitd: SourceKitD) {
    guard sourcekitd.servicePluginApi.request_get_type(request) == SOURCEKITD_API_VARIANT_TYPE_DICTIONARY else {
      return nil
    }
    self.dict = request
    self.sourcekitd = sourcekitd
    _ = sourcekitd.api.request_retain(dict)
  }

  deinit {
    _ = sourcekitd.api.request_release(dict)
  }

  private func getVariant<T>(
    _ key: sourcekitd_api_uid_t,
    _ variantType: sourcekitd_api_variant_type_t,
    _ retrievalFunction: (sourcekitd_api_object_t) -> T?
  ) -> T? {
    guard let value = sourcekitd.servicePluginApi.request_dictionary_get_value(sourcekitd_api_object_t(dict), key)
    else {
      return nil
    }
    if sourcekitd.servicePluginApi.request_get_type(value) == variantType {
      return retrievalFunction(value)
    } else {
      return nil
    }
  }

  subscript(key: sourcekitd_api_uid_t) -> String? {
    guard let cString = sourcekitd.servicePluginApi.request_dictionary_get_string(sourcekitd_api_object_t(dict), key)
    else {
      return nil
    }
    return String(cString: cString)
  }

  subscript(key: sourcekitd_api_uid_t) -> Int64? {
    return getVariant(key, SOURCEKITD_API_VARIANT_TYPE_INT64, sourcekitd.servicePluginApi.request_int64_get_value)
  }

  subscript(key: sourcekitd_api_uid_t) -> Int? {
    guard let value: Int64 = self[key] else {
      return nil
    }
    return Int(value)
  }

  subscript(key: sourcekitd_api_uid_t) -> Bool? {
    return getVariant(key, SOURCEKITD_API_VARIANT_TYPE_BOOL, sourcekitd.servicePluginApi.request_bool_get_value)
  }

  subscript(key: sourcekitd_api_uid_t) -> sourcekitd_api_uid_t? {
    return sourcekitd.servicePluginApi.request_dictionary_get_uid(sourcekitd_api_object_t(dict), key)
  }

  subscript(key: sourcekitd_api_uid_t) -> SKDRequestArrayReader? {
    return getVariant(key, SOURCEKITD_API_VARIANT_TYPE_ARRAY) {
      SKDRequestArrayReader($0, sourcekitd: sourcekitd)
    }
  }

  subscript(key: sourcekitd_api_uid_t) -> SKDRequestDictionaryReader? {
    return getVariant(key, SOURCEKITD_API_VARIANT_TYPE_DICTIONARY) {
      SKDRequestDictionaryReader($0, sourcekitd: sourcekitd)
    }
  }
}
