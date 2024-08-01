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

extension sourcekitd_api_functions_t {
  package init(_ sourcekitd: DLHandle) throws {
    func loadRequired<T>(_ symbol: String) throws -> T {
      guard let sym: T = dlsym(sourcekitd, symbol: symbol) else {
        throw SKDError.missingRequiredSymbol(symbol)
      }
      return sym
    }

    func loadOptional<T>(_ symbol: String) -> T? {
      return dlsym(sourcekitd, symbol: symbol)
    }

    self.init(
      initialize: try loadRequired("sourcekitd_initialize"),
      shutdown: try loadRequired("sourcekitd_shutdown"),
      uid_get_from_cstr: try loadRequired("sourcekitd_uid_get_from_cstr"),
      uid_get_from_buf: try loadRequired("sourcekitd_uid_get_from_buf"),
      uid_get_length: try loadRequired("sourcekitd_uid_get_length"),
      uid_get_string_ptr: try loadRequired("sourcekitd_uid_get_string_ptr"),
      request_retain: try loadRequired("sourcekitd_request_retain"),
      request_release: try loadRequired("sourcekitd_request_release"),
      request_dictionary_create: try loadRequired("sourcekitd_request_dictionary_create"),
      request_dictionary_set_value: try loadRequired("sourcekitd_request_dictionary_set_value"),
      request_dictionary_set_string: try loadRequired("sourcekitd_request_dictionary_set_string"),
      request_dictionary_set_stringbuf: try loadRequired("sourcekitd_request_dictionary_set_stringbuf"),
      request_dictionary_set_int64: try loadRequired("sourcekitd_request_dictionary_set_int64"),
      request_dictionary_set_uid: try loadRequired("sourcekitd_request_dictionary_set_uid"),
      request_array_create: try loadRequired("sourcekitd_request_array_create"),
      request_array_set_value: try loadRequired("sourcekitd_request_array_set_value"),
      request_array_set_string: try loadRequired("sourcekitd_request_array_set_string"),
      request_array_set_stringbuf: try loadRequired("sourcekitd_request_array_set_stringbuf"),
      request_array_set_int64: try loadRequired("sourcekitd_request_array_set_int64"),
      request_array_set_uid: try loadRequired("sourcekitd_request_array_set_uid"),
      request_int64_create: try loadRequired("sourcekitd_request_int64_create"),
      request_string_create: try loadRequired("sourcekitd_request_string_create"),
      request_uid_create: try loadRequired("sourcekitd_request_uid_create"),
      request_create_from_yaml: try loadRequired("sourcekitd_request_create_from_yaml"),
      request_description_dump: try loadRequired("sourcekitd_request_description_dump"),
      request_description_copy: try loadRequired("sourcekitd_request_description_copy"),
      response_dispose: try loadRequired("sourcekitd_response_dispose"),
      response_is_error: try loadRequired("sourcekitd_response_is_error"),
      response_error_get_kind: try loadRequired("sourcekitd_response_error_get_kind"),
      response_error_get_description: try loadRequired("sourcekitd_response_error_get_description"),
      response_get_value: try loadRequired("sourcekitd_response_get_value"),
      variant_get_type: try loadRequired("sourcekitd_variant_get_type"),
      variant_dictionary_get_value: try loadRequired("sourcekitd_variant_dictionary_get_value"),
      variant_dictionary_get_string: try loadRequired("sourcekitd_variant_dictionary_get_string"),
      variant_dictionary_get_int64: try loadRequired("sourcekitd_variant_dictionary_get_int64"),
      variant_dictionary_get_bool: try loadRequired("sourcekitd_variant_dictionary_get_bool"),
      variant_dictionary_get_uid: try loadRequired("sourcekitd_variant_dictionary_get_uid"),
      variant_array_get_count: try loadRequired("sourcekitd_variant_array_get_count"),
      variant_array_get_value: try loadRequired("sourcekitd_variant_array_get_value"),
      variant_array_get_string: try loadRequired("sourcekitd_variant_array_get_string"),
      variant_array_get_int64: try loadRequired("sourcekitd_variant_array_get_int64"),
      variant_array_get_bool: try loadRequired("sourcekitd_variant_array_get_bool"),
      variant_array_get_uid: try loadRequired("sourcekitd_variant_array_get_uid"),
      variant_int64_get_value: try loadRequired("sourcekitd_variant_int64_get_value"),
      variant_bool_get_value: try loadRequired("sourcekitd_variant_bool_get_value"),
      variant_string_get_length: try loadRequired("sourcekitd_variant_string_get_length"),
      variant_string_get_ptr: try loadRequired("sourcekitd_variant_string_get_ptr"),
      variant_data_get_size: loadOptional("sourcekitd_variant_data_get_size"),
      variant_data_get_ptr: loadOptional("sourcekitd_variant_data_get_ptr"),
      variant_uid_get_value: try loadRequired("sourcekitd_variant_uid_get_value"),
      response_description_dump: try loadRequired("sourcekitd_response_description_dump"),
      response_description_dump_filedesc: try loadRequired("sourcekitd_response_description_dump_filedesc"),
      response_description_copy: try loadRequired("sourcekitd_response_description_copy"),
      variant_description_dump: try loadRequired("sourcekitd_variant_description_dump"),
      variant_description_dump_filedesc: try loadRequired("sourcekitd_variant_description_dump_filedesc"),
      variant_description_copy: try loadRequired("sourcekitd_variant_description_copy"),
      send_request_sync: try loadRequired("sourcekitd_send_request_sync"),
      send_request: try loadRequired("sourcekitd_send_request"),
      cancel_request: try loadRequired("sourcekitd_cancel_request"),
      set_notification_handler: try loadRequired("sourcekitd_set_notification_handler"),
      set_uid_handlers: try loadRequired("sourcekitd_set_uid_handlers")
    )

  }
}
