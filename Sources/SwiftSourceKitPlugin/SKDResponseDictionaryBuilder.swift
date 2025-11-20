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
import SwiftSourceKitPluginCommon

extension SourceKitD {
  nonisolated func responseDictionary(
    _ dict: [sourcekitd_api_uid_t: any SKDResponseValue]
  ) -> SKDResponseDictionaryBuilder {
    let result = SKDResponseDictionaryBuilder(sourcekitd: self)
    for (key, value) in dict {
      result.set(key, to: value)
    }
    return result
  }
}

struct SKDResponseDictionaryBuilder {
  /// The `SKDResponse` object that manages the lifetime of the `sourcekitd_response_t`.
  let response: SKDResponse

  var value: sourcekitd_api_response_t { response.value }
  private var sourcekitd: SourceKitD { response.sourcekitd }

  init(sourcekitd: SourceKitD) {
    response = .init(
      takingUnderlyingResponse: sourcekitd.servicePluginApi.response_dictionary_create(nil, nil, 0),
      sourcekitd: sourcekitd
    )
  }

  func set(_ key: sourcekitd_api_uid_t, to newValue: any SKDResponseValue) {
    switch newValue {
    case let newValue as String:
      sourcekitd.servicePluginApi.response_dictionary_set_string(value, key, newValue)
    case let newValue as Bool:
      sourcekitd.servicePluginApi.response_dictionary_set_bool(value, key, newValue)
    case let newValue as Int:
      sourcekitd.servicePluginApi.response_dictionary_set_int64(value, key, Int64(newValue))
    case let newValue as Int64:
      sourcekitd.servicePluginApi.response_dictionary_set_int64(value, key, newValue)
    case let newValue as Double:
      sourcekitd.servicePluginApi.response_dictionary_set_double(value, key, newValue)
    case let newValue as sourcekitd_api_uid_t:
      sourcekitd.servicePluginApi.response_dictionary_set_uid(value, key, newValue)
    case let newValue as SKDResponseDictionaryBuilder:
      sourcekitd.servicePluginApi.response_dictionary_set_value(value, key, newValue.value)
    case let newValue as SKDResponseArrayBuilder:
      sourcekitd.servicePluginApi.response_dictionary_set_value(value, key, newValue.value)
    case let newValue as [any SKDResponseValue]:
      self.set(key, to: sourcekitd.responseArray(newValue))
    case let newValue as [sourcekitd_api_uid_t: any SKDResponseValue]:
      self.set(key, to: sourcekitd.responseDictionary(newValue))
    case let newValue as (any SKDResponseValue)?:
      if let newValue {
        self.set(key, to: newValue)
      }
    default:
      preconditionFailure("Unknown type conforming to SKDRequestValue")
    }
  }

  func set(_ key: sourcekitd_api_uid_t, toCustomBuffer buffer: UnsafeRawBufferPointer) {
    assert(buffer.count > MemoryLayout<UInt64>.size, "custom buffer must begin with uint64_t identifier field")
    sourcekitd.servicePluginApi.response_dictionary_set_custom_buffer(
      value,
      key,
      buffer.baseAddress!,
      buffer.count
    )
  }
}
