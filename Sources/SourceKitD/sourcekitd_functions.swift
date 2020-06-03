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
import SKSupport

extension sourcekitd_functions_t {
  public init(_ sourcekitd: DLHandle) throws {
    // Zero-initialize
    self.init()

    // MARK: Optional Methods

    self.variant_data_get_size = dlsym(sourcekitd, symbol: "sourcekitd_variant_data_get_size")
    self.variant_data_get_ptr = dlsym(sourcekitd, symbol:"sourcekitd_variant_data_get_ptr")

    // MARK: Required Methods

    func loadRequired<T>(_ symbol: String) throws -> T {
      guard let sym: T = dlsym(sourcekitd, symbol: symbol) else {
        throw SKDError.missingRequiredSymbol(symbol)
      }
      return sym
    }

    self.initialize = try loadRequired("sourcekitd_initialize")
    self.shutdown = try loadRequired("sourcekitd_shutdown")
    self.uid_get_from_cstr = try loadRequired("sourcekitd_uid_get_from_cstr")
    self.uid_get_from_buf = try loadRequired("sourcekitd_uid_get_from_buf")
    self.uid_get_length = try loadRequired("sourcekitd_uid_get_length")
    self.uid_get_string_ptr = try loadRequired("sourcekitd_uid_get_string_ptr")
    self.request_retain = try loadRequired("sourcekitd_request_retain")
    self.request_release = try loadRequired("sourcekitd_request_release")
    self.request_dictionary_create = try loadRequired("sourcekitd_request_dictionary_create")
    self.request_dictionary_set_value = try loadRequired("sourcekitd_request_dictionary_set_value")
    self.request_dictionary_set_string = try loadRequired("sourcekitd_request_dictionary_set_string")
    self.request_dictionary_set_stringbuf = try loadRequired("sourcekitd_request_dictionary_set_stringbuf")
    self.request_dictionary_set_int64 = try loadRequired("sourcekitd_request_dictionary_set_int64")
    self.request_dictionary_set_uid = try loadRequired("sourcekitd_request_dictionary_set_uid")
    self.request_array_create = try loadRequired("sourcekitd_request_array_create")
    self.request_array_set_value = try loadRequired("sourcekitd_request_array_set_value")
    self.request_array_set_string = try loadRequired("sourcekitd_request_array_set_string")
    self.request_array_set_stringbuf = try loadRequired("sourcekitd_request_array_set_stringbuf")
    self.request_array_set_int64 = try loadRequired("sourcekitd_request_array_set_int64")
    self.request_array_set_uid = try loadRequired("sourcekitd_request_array_set_uid")
    self.request_int64_create = try loadRequired("sourcekitd_request_int64_create")
    self.request_string_create = try loadRequired("sourcekitd_request_string_create")
    self.request_uid_create = try loadRequired("sourcekitd_request_uid_create")
    self.request_create_from_yaml = try loadRequired("sourcekitd_request_create_from_yaml")
    self.request_description_dump = try loadRequired("sourcekitd_request_description_dump")
    self.request_description_copy = try loadRequired("sourcekitd_request_description_copy")
    self.response_dispose = try loadRequired("sourcekitd_response_dispose")
    self.response_is_error = try loadRequired("sourcekitd_response_is_error")
    self.response_error_get_kind = try loadRequired("sourcekitd_response_error_get_kind")
    self.response_error_get_description = try loadRequired("sourcekitd_response_error_get_description")
    self.response_get_value = try loadRequired("sourcekitd_response_get_value")
    self.variant_get_type = try loadRequired("sourcekitd_variant_get_type")

    self.variant_dictionary_apply = try loadRequired("sourcekitd_variant_dictionary_apply")
    self.variant_dictionary_get_value = try loadRequired("sourcekitd_variant_dictionary_get_value")
    self.variant_dictionary_get_string = try loadRequired("sourcekitd_variant_dictionary_get_string")
    self.variant_dictionary_get_int64 = try loadRequired("sourcekitd_variant_dictionary_get_int64")
    self.variant_dictionary_get_bool = try loadRequired("sourcekitd_variant_dictionary_get_bool")
    self.variant_dictionary_get_uid = try loadRequired("sourcekitd_variant_dictionary_get_uid")

    self.variant_array_apply = try loadRequired("sourcekitd_variant_array_apply")
    self.variant_array_get_count = try loadRequired("sourcekitd_variant_array_get_count")
    self.variant_array_get_value = try loadRequired("sourcekitd_variant_array_get_value")
    self.variant_array_get_string = try loadRequired("sourcekitd_variant_array_get_string")
    self.variant_array_get_int64 = try loadRequired("sourcekitd_variant_array_get_int64")
    self.variant_array_get_bool = try loadRequired("sourcekitd_variant_array_get_bool")
    self.variant_array_get_uid = try loadRequired("sourcekitd_variant_array_get_uid")

    self.variant_int64_get_value = try loadRequired("sourcekitd_variant_int64_get_value")
    self.variant_bool_get_value = try loadRequired("sourcekitd_variant_bool_get_value")
    self.variant_string_get_length = try loadRequired("sourcekitd_variant_string_get_length")
    self.variant_string_get_ptr = try loadRequired("sourcekitd_variant_string_get_ptr")

    self.variant_uid_get_value = try loadRequired("sourcekitd_variant_uid_get_value")
    self.response_description_dump = try loadRequired("sourcekitd_response_description_dump")
    self.response_description_dump_filedesc = try loadRequired("sourcekitd_response_description_dump_filedesc")
    self.response_description_copy = try loadRequired("sourcekitd_response_description_copy")
    self.variant_description_dump = try loadRequired("sourcekitd_variant_description_dump")
    self.variant_description_dump_filedesc = try loadRequired("sourcekitd_variant_description_dump_filedesc")
    self.variant_description_copy = try loadRequired("sourcekitd_variant_description_copy")
    self.send_request_sync = try loadRequired("sourcekitd_send_request_sync")
    self.send_request = try loadRequired("sourcekitd_send_request")
    self.cancel_request = try loadRequired("sourcekitd_cancel_request")
    self.set_notification_handler = try loadRequired("sourcekitd_set_notification_handler")
    self.set_uid_handlers = try loadRequired("sourcekitd_set_uid_handlers")
  }
}
