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

extension SourceKitD {
  nonisolated func responseArray(_ array: [any SKDResponseValue]) -> SKDResponseArrayBuilder {
    let result = SKDResponseArrayBuilder(sourcekitd: self)
    for element in array {
      result.append(element)
    }
    return result
  }
}

struct SKDResponseArrayBuilder {
  /// The `SKDResponse` object that manages the lifetime of the `sourcekitd_response_t`.
  private let response: SKDResponse

  var value: sourcekitd_api_response_t { response.value }
  private var sourcekitd: SourceKitD { response.sourcekitd }

  init(sourcekitd: SourceKitD) {
    response = .init(
      takingUnderlyingResponse: sourcekitd.servicePluginApi.response_array_create(nil, 0),
      sourcekitd: sourcekitd
    )
  }

  func append(_ newValue: any SKDResponseValue) {
    switch newValue {
    case let newValue as String:
      sourcekitd.servicePluginApi.response_array_set_string(value, -1, newValue)
    case is Bool:
      preconditionFailure("Arrays of bools are not supported")
    case let newValue as Int:
      sourcekitd.servicePluginApi.response_array_set_int64(value, -1, Int64(newValue))
    case let newValue as Int64:
      sourcekitd.servicePluginApi.response_array_set_int64(value, -1, newValue)
    case let newValue as Double:
      sourcekitd.servicePluginApi.response_array_set_double(value, -1, newValue)
    case let newValue as sourcekitd_api_uid_t:
      sourcekitd.servicePluginApi.response_array_set_uid(value, -1, newValue)
    case let newValue as SKDResponseDictionaryBuilder:
      sourcekitd.servicePluginApi.response_array_set_value(value, -1, newValue.value)
    case let newValue as SKDResponseArrayBuilder:
      sourcekitd.servicePluginApi.response_array_set_value(value, -1, newValue.value)
    case let newValue as [any SKDResponseValue]:
      self.append(sourcekitd.responseArray(newValue))
    case let newValue as [sourcekitd_api_uid_t: any SKDResponseValue]:
      self.append(sourcekitd.responseDictionary(newValue))
    case let newValue as (any SKDResponseValue)?:
      if let newValue {
        self.append(newValue)
      }
    default:
      preconditionFailure("Unknown type conforming to SKDRequestValue")
    }
  }
}
