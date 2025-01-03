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
      register_plugin_path: loadOptional("sourcekitd_register_plugin_path"),
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
      variant_double_get_value: loadOptional("sourcekitd_variant_double_get_value"),
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

extension sourcekitd_ide_api_functions_t {
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
      connection_create_with_inspection_instance: try loadRequired(
        "swiftide_connection_create_with_inspection_instance"
      ),
      connection_dispose: try loadRequired("swiftide_connection_dispose"),
      connection_mark_cached_compiler_instance_should_be_invalidated: try loadRequired(
        "swiftide_connection_mark_cached_compiler_instance_should_be_invalidated"
      ),
      set_file_contents: try loadRequired("swiftide_set_file_contents"),
      cancel_request: try loadRequired("swiftide_cancel_request"),
      completion_request_create: try loadRequired("swiftide_completion_request_create"),
      completion_request_dispose: try loadRequired("swiftide_completion_request_dispose"),
      completion_request_set_annotate_result: try loadRequired("swiftide_completion_request_set_annotate_result"),
      completion_request_set_include_objectliterals: try loadRequired(
        "swiftide_completion_request_set_include_objectliterals"
      ),
      completion_request_set_add_inits_to_top_level: try loadRequired(
        "swiftide_completion_request_set_add_inits_to_top_level"
      ),
      completion_request_set_add_call_with_no_default_args: try loadRequired(
        "swiftide_completion_request_set_add_call_with_no_default_args"
      ),
      complete_cancellable: try loadRequired("swiftide_complete_cancellable"),
      completion_result_dispose: try loadRequired("swiftide_completion_result_dispose"),
      completion_result_is_error: try loadRequired("swiftide_completion_result_is_error"),
      completion_result_get_error_description: try loadRequired("swiftide_completion_result_get_error_description"),
      completion_result_is_cancelled: try loadRequired("swiftide_completion_result_is_cancelled"),
      completion_result_description_copy: try loadRequired("swiftide_completion_result_description_copy"),
      completion_result_get_completions: try loadRequired("swiftide_completion_result_get_completions"),
      completion_result_get_completion_at_index: try loadRequired("swiftide_completion_result_get_completion_at_index"),
      completion_result_get_kind: try loadRequired("swiftide_completion_result_get_kind"),
      completion_result_foreach_baseexpr_typename: try loadRequired(
        "swiftide_completion_result_foreach_baseexpr_typename"
      ),
      completion_result_is_reusing_astcontext: try loadRequired("swiftide_completion_result_is_reusing_astcontext"),
      completion_item_description_copy: try loadRequired("swiftide_completion_item_description_copy"),
      completion_item_get_label: try loadRequired("swiftide_completion_item_get_label"),
      completion_item_get_source_text: try loadRequired("swiftide_completion_item_get_source_text"),
      completion_item_get_type_name: try loadRequired("swiftide_completion_item_get_type_name"),
      completion_item_get_doc_brief: try loadRequired("swiftide_completion_item_get_doc_brief"),
      completion_item_get_associated_usrs: try loadRequired("swiftide_completion_item_get_associated_usrs"),
      completion_item_get_kind: try loadRequired("swiftide_completion_item_get_kind"),
      completion_item_get_associated_kind: try loadRequired("swiftide_completion_item_get_associated_kind"),
      completion_item_get_semantic_context: try loadRequired("swiftide_completion_item_get_semantic_context"),
      completion_item_get_flair: try loadRequired("swiftide_completion_item_get_flair"),
      completion_item_is_not_recommended: try loadRequired("swiftide_completion_item_is_not_recommended"),
      completion_item_not_recommended_reason: try loadRequired("swiftide_completion_item_not_recommended_reason"),
      completion_item_has_diagnostic: try loadRequired("swiftide_completion_item_has_diagnostic"),
      completion_item_get_diagnostic: try loadRequired("swiftide_completion_item_get_diagnostic"),
      completion_item_is_system: try loadRequired("swiftide_completion_item_is_system"),
      completion_item_get_module_name: try loadRequired("swiftide_completion_item_get_module_name"),
      completion_item_get_num_bytes_to_erase: try loadRequired("swiftide_completion_item_get_num_bytes_to_erase"),
      completion_item_get_type_relation: try loadRequired("swiftide_completion_item_get_type_relation"),
      completion_item_import_depth: try loadRequired("swiftide_completion_item_import_depth"),
      fuzzy_match_pattern_create: try loadRequired("swiftide_fuzzy_match_pattern_create"),
      fuzzy_match_pattern_matches_candidate: try loadRequired("swiftide_fuzzy_match_pattern_matches_candidate"),
      fuzzy_match_pattern_dispose: try loadRequired("swiftide_fuzzy_match_pattern_dispose")
    )
  }
}

extension sourcekitd_plugin_api_functions_t {
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
      variant_functions_create: try loadRequired("sourcekitd_variant_functions_create"),
      variant_functions_set_get_type: try loadRequired("sourcekitd_variant_functions_set_get_type"),
      variant_functions_set_array_apply: try loadRequired("sourcekitd_variant_functions_set_array_apply"),
      variant_functions_set_array_get_bool: try loadRequired("sourcekitd_variant_functions_set_array_get_bool"),
      variant_functions_set_array_get_double: try loadRequired("sourcekitd_variant_functions_set_array_get_double"),
      variant_functions_set_array_get_count: try loadRequired("sourcekitd_variant_functions_set_array_get_count"),
      variant_functions_set_array_get_int64: try loadRequired("sourcekitd_variant_functions_set_array_get_int64"),
      variant_functions_set_array_get_string: try loadRequired("sourcekitd_variant_functions_set_array_get_string"),
      variant_functions_set_array_get_uid: try loadRequired("sourcekitd_variant_functions_set_array_get_uid"),
      variant_functions_set_array_get_value: try loadRequired("sourcekitd_variant_functions_set_array_get_value"),
      variant_functions_set_bool_get_value: try loadRequired("sourcekitd_variant_functions_set_bool_get_value"),
      variant_functions_set_double_get_value: try loadRequired("sourcekitd_variant_functions_set_double_get_value"),
      variant_functions_set_dictionary_apply: try loadRequired("sourcekitd_variant_functions_set_dictionary_apply"),
      variant_functions_set_dictionary_get_bool: try loadRequired(
        "sourcekitd_variant_functions_set_dictionary_get_bool"
      ),
      variant_functions_set_dictionary_get_double: try loadRequired(
        "sourcekitd_variant_functions_set_dictionary_get_double"
      ),
      variant_functions_set_dictionary_get_int64: try loadRequired(
        "sourcekitd_variant_functions_set_dictionary_get_int64"
      ),
      variant_functions_set_dictionary_get_string: try loadRequired(
        "sourcekitd_variant_functions_set_dictionary_get_string"
      ),
      variant_functions_set_dictionary_get_value: try loadRequired(
        "sourcekitd_variant_functions_set_dictionary_get_value"
      ),
      variant_functions_set_dictionary_get_uid: try loadRequired("sourcekitd_variant_functions_set_dictionary_get_uid"),
      variant_functions_set_string_get_length: try loadRequired("sourcekitd_variant_functions_set_string_get_length"),
      variant_functions_set_string_get_ptr: try loadRequired("sourcekitd_variant_functions_set_string_get_ptr"),
      variant_functions_set_int64_get_value: try loadRequired("sourcekitd_variant_functions_set_int64_get_value"),
      variant_functions_set_uid_get_value: try loadRequired("sourcekitd_variant_functions_set_uid_get_value"),
      variant_functions_set_data_get_size: try loadRequired("sourcekitd_variant_functions_set_data_get_size"),
      variant_functions_set_data_get_ptr: try loadRequired("sourcekitd_variant_functions_set_data_get_ptr"),
      plugin_initialize_is_client_only: try loadRequired("sourcekitd_plugin_initialize_is_client_only"),
      plugin_initialize_custom_buffer_start: try loadRequired("sourcekitd_plugin_initialize_custom_buffer_start"),
      plugin_initialize_uid_get_from_cstr: try loadRequired("sourcekitd_plugin_initialize_uid_get_from_cstr"),
      plugin_initialize_uid_get_string_ptr: try loadRequired("sourcekitd_plugin_initialize_uid_get_string_ptr"),
      plugin_initialize_register_custom_buffer: try loadRequired("sourcekitd_plugin_initialize_register_custom_buffer")
    )
  }
}

extension sourcekitd_service_plugin_api_functions_t {
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
      plugin_initialize_register_cancellable_request_handler: try loadRequired(
        "sourcekitd_plugin_initialize_register_cancellable_request_handler"
      ),
      plugin_initialize_register_cancellation_handler: try loadRequired(
        "sourcekitd_plugin_initialize_register_cancellation_handler"
      ),
      plugin_initialize_get_swift_ide_inspection_instance: try loadRequired(
        "sourcekitd_plugin_initialize_get_swift_ide_inspection_instance"
      ),
      request_get_type: try loadRequired("sourcekitd_request_get_type"),
      request_dictionary_get_value: try loadRequired("sourcekitd_request_dictionary_get_value"),
      request_dictionary_get_string: try loadRequired("sourcekitd_request_dictionary_get_string"),
      request_dictionary_get_int64: try loadRequired("sourcekitd_request_dictionary_get_int64"),
      request_dictionary_get_bool: try loadRequired("sourcekitd_request_dictionary_get_bool"),
      request_dictionary_get_uid: try loadRequired("sourcekitd_request_dictionary_get_uid"),
      request_array_get_count: try loadRequired("sourcekitd_request_array_get_count"),
      request_array_get_value: try loadRequired("sourcekitd_request_array_get_value"),
      request_array_get_string: try loadRequired("sourcekitd_request_array_get_string"),
      request_array_get_int64: try loadRequired("sourcekitd_request_array_get_int64"),
      request_array_get_bool: try loadRequired("sourcekitd_request_array_get_bool"),
      request_array_get_uid: try loadRequired("sourcekitd_request_array_get_uid"),
      request_int64_get_value: try loadRequired("sourcekitd_request_int64_get_value"),
      request_bool_get_value: try loadRequired("sourcekitd_request_bool_get_value"),
      request_string_get_length: try loadRequired("sourcekitd_request_string_get_length"),
      request_string_get_ptr: try loadRequired("sourcekitd_request_string_get_ptr"),
      request_uid_get_value: try loadRequired("sourcekitd_request_uid_get_value"),
      response_retain: try loadRequired("sourcekitd_response_retain"),
      response_error_create: try loadRequired("sourcekitd_response_error_create"),
      response_dictionary_create: try loadRequired("sourcekitd_response_dictionary_create"),
      response_dictionary_set_value: try loadRequired("sourcekitd_response_dictionary_set_value"),
      response_dictionary_set_string: try loadRequired("sourcekitd_response_dictionary_set_string"),
      response_dictionary_set_stringbuf: try loadRequired("sourcekitd_response_dictionary_set_stringbuf"),
      response_dictionary_set_int64: try loadRequired("sourcekitd_response_dictionary_set_int64"),
      response_dictionary_set_bool: try loadRequired("sourcekitd_response_dictionary_set_bool"),
      response_dictionary_set_double: try loadRequired("sourcekitd_response_dictionary_set_double"),
      response_dictionary_set_uid: try loadRequired("sourcekitd_response_dictionary_set_uid"),
      response_array_create: try loadRequired("sourcekitd_response_array_create"),
      response_array_set_value: try loadRequired("sourcekitd_response_array_set_value"),
      response_array_set_string: try loadRequired("sourcekitd_response_array_set_string"),
      response_array_set_stringbuf: try loadRequired("sourcekitd_response_array_set_stringbuf"),
      response_array_set_int64: try loadRequired("sourcekitd_response_array_set_int64"),
      response_array_set_double: try loadRequired("sourcekitd_response_array_set_double"),
      response_array_set_uid: try loadRequired("sourcekitd_response_array_set_uid"),
      response_dictionary_set_custom_buffer: try loadRequired("sourcekitd_response_dictionary_set_custom_buffer")
    )
  }
}
