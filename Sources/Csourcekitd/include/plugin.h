//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_SOURCEKITD_PLUGIN_H
#define SWIFT_SOURCEKITD_PLUGIN_H

#include "sourcekitd_functions.h"


typedef void *sourcekitd_api_variant_functions_t;

typedef sourcekitd_api_variant_type_t (*sourcekitd_api_variant_functions_get_type_t)(
  sourcekitd_api_variant_t obj
);
typedef bool (*sourcekitd_api_variant_functions_array_apply_t)(
  sourcekitd_api_variant_t array,
  _Null_unspecified sourcekitd_api_variant_array_applier_f_t applier,
  void *_Null_unspecified context
);
typedef bool (*sourcekitd_api_variant_functions_array_get_bool_t)(
  sourcekitd_api_variant_t array,
  size_t index
);
typedef double (*sourcekitd_api_variant_functions_array_get_double_t)(
  sourcekitd_api_variant_t array,
  size_t index
);
typedef size_t (*sourcekitd_api_variant_functions_array_get_count_t)(
  sourcekitd_api_variant_t array
);
typedef int64_t (*sourcekitd_api_variant_functions_array_get_int64_t)(
  sourcekitd_api_variant_t array,
  size_t index
);
typedef const char *_Null_unspecified (*sourcekitd_api_variant_functions_array_get_string_t)(
  sourcekitd_api_variant_t array,
  size_t index
);
typedef _Null_unspecified sourcekitd_api_uid_t (*sourcekitd_api_variant_functions_array_get_uid_t)(
  sourcekitd_api_variant_t array,
  size_t index
);
typedef sourcekitd_api_variant_t (*sourcekitd_api_variant_functions_array_get_value_t)(
  sourcekitd_api_variant_t array,
  size_t index
);
typedef bool (*sourcekitd_api_variant_functions_bool_get_value_t)(
  sourcekitd_api_variant_t obj
);
typedef double (*sourcekitd_api_variant_functions_double_get_value_t)(
  sourcekitd_api_variant_t obj
);
typedef bool (*sourcekitd_api_variant_functions_dictionary_apply_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_variant_dictionary_applier_f_t applier,
  void *_Null_unspecified context
);
typedef bool (*sourcekitd_api_variant_functions_dictionary_get_bool_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_uid_t key
);
typedef double (*sourcekitd_api_variant_functions_dictionary_get_double_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_uid_t key
);
typedef int64_t (*sourcekitd_api_variant_functions_dictionary_get_int64_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_uid_t key
);
typedef const char *_Null_unspecified (*sourcekitd_api_variant_functions_dictionary_get_string_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_uid_t key
);
typedef sourcekitd_api_variant_t (*sourcekitd_api_variant_functions_dictionary_get_value_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_uid_t key
);
typedef _Null_unspecified sourcekitd_api_uid_t (*sourcekitd_api_variant_functions_dictionary_get_uid_t)(
  sourcekitd_api_variant_t dict,
  _Null_unspecified sourcekitd_api_uid_t key
);
typedef size_t (*sourcekitd_api_variant_functions_string_get_length_t)(
  sourcekitd_api_variant_t obj
);
typedef const char *_Null_unspecified (*sourcekitd_api_variant_functions_string_get_ptr_t)(
  sourcekitd_api_variant_t obj
);
typedef int64_t (*sourcekitd_api_variant_functions_int64_get_value_t)(
  sourcekitd_api_variant_t obj
);
typedef _Null_unspecified sourcekitd_api_uid_t (*sourcekitd_api_variant_functions_uid_get_value_t)(
  sourcekitd_api_variant_t obj
);
typedef size_t (*sourcekitd_api_variant_functions_data_get_size_t)(
  sourcekitd_api_variant_t obj
);
typedef const void *_Null_unspecified (*sourcekitd_api_variant_functions_data_get_ptr_t)(
  sourcekitd_api_variant_t obj
);

/// Handle the request specified by the \c sourcekitd_api_object_t and keep track
/// of it using the \c sourcekitd_api_request_handle_t. If the cancellation handler
/// specified by \c sourcekitd_api_plugin_initialize_register_cancellation_handler
/// is called with the this request handle, the request should be cancelled.
typedef bool (^sourcekitd_api_cancellable_request_handler_t)(
  _Null_unspecified sourcekitd_api_object_t,
  _Null_unspecified sourcekitd_api_request_handle_t,
  void (^_Null_unspecified SWIFT_SENDABLE)(_Null_unspecified sourcekitd_api_response_t)
);
typedef void (^sourcekitd_api_cancellation_handler_t)(_Null_unspecified sourcekitd_api_request_handle_t);
typedef _Null_unspecified sourcekitd_api_uid_t (*sourcekitd_api_uid_get_from_cstr_t)(const char *_Null_unspecified string);
typedef const char *_Null_unspecified (*sourcekitd_api_uid_get_string_ptr_t)(_Null_unspecified sourcekitd_api_uid_t);

typedef void *sourcekitd_api_plugin_initialize_params_t;
typedef void (*sourcekitd_api_plugin_initialize_t)(
  _Null_unspecified sourcekitd_api_plugin_initialize_params_t
);

typedef struct {
  _Null_unspecified sourcekitd_api_variant_functions_t (*_Nonnull variant_functions_create)(void);

  void (*_Nonnull variant_functions_set_get_type)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_get_type_t f
  );
  void (*_Nonnull variant_functions_set_array_apply)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_apply_t f
  );
  void (*_Nonnull variant_functions_set_array_get_bool)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_bool_t f
  );
  void (*_Nonnull variant_functions_set_array_get_double)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_double_t f
  );
  void (*_Nonnull variant_functions_set_array_get_count)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_count_t f
  );
  void (*_Nonnull variant_functions_set_array_get_int64)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_int64_t f
  );
  void (*_Nonnull variant_functions_set_array_get_string)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_string_t f
  );
  void (*_Nonnull variant_functions_set_array_get_uid)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_uid_t f
  );
  void (*_Nonnull variant_functions_set_array_get_value)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_array_get_value_t f
  );
  void (*_Nonnull variant_functions_set_bool_get_value)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_bool_get_value_t f
  );
  void (*_Nonnull variant_functions_set_double_get_value)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_double_get_value_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_apply)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_apply_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_get_bool)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_get_bool_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_get_double)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_get_double_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_get_int64)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_get_int64_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_get_string)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_get_string_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_get_value)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_get_value_t f
  );
  void (*_Nonnull variant_functions_set_dictionary_get_uid)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_dictionary_get_uid_t f
  );
  void (*_Nonnull variant_functions_set_string_get_length)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_string_get_length_t f
  );
  void (*_Nonnull variant_functions_set_string_get_ptr)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_string_get_ptr_t f
  );
  void (*_Nonnull variant_functions_set_int64_get_value)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_int64_get_value_t f
  );
  void (*_Nonnull variant_functions_set_uid_get_value)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_uid_get_value_t f
  );
  void (*_Nonnull variant_functions_set_data_get_size)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_data_get_size_t f
  );
  void (*_Nonnull variant_functions_set_data_get_ptr)(
    _Nonnull sourcekitd_api_variant_functions_t funcs,
    _Nonnull sourcekitd_api_variant_functions_data_get_ptr_t f
  );

  bool (*_Nonnull plugin_initialize_is_client_only)(
    _Null_unspecified sourcekitd_api_plugin_initialize_params_t
  );

  uint64_t (*_Nonnull plugin_initialize_custom_buffer_start)(
    _Null_unspecified sourcekitd_api_plugin_initialize_params_t
  );

  _Null_unspecified SWIFT_SENDABLE sourcekitd_api_uid_get_from_cstr_t (*_Nonnull plugin_initialize_uid_get_from_cstr)(
    _Null_unspecified sourcekitd_api_plugin_initialize_params_t
  );

  _Null_unspecified SWIFT_SENDABLE sourcekitd_api_uid_get_string_ptr_t (*_Nonnull plugin_initialize_uid_get_string_ptr)(
    _Null_unspecified sourcekitd_api_plugin_initialize_params_t
  );

  void (*_Nonnull plugin_initialize_register_custom_buffer)(
    _Nonnull sourcekitd_api_plugin_initialize_params_t,
    uint64_t kind,
    _Nonnull sourcekitd_api_variant_functions_t funcs
  );
} sourcekitd_plugin_api_functions_t;

typedef struct {
  void (*_Nonnull plugin_initialize_register_cancellable_request_handler)(
    _Nonnull sourcekitd_api_plugin_initialize_params_t,
    _Nonnull SWIFT_SENDABLE sourcekitd_api_cancellable_request_handler_t
  );

  /// Adds a function that will be called when a request is cancelled.
  /// The cancellation handler is called even for cancelled requests that are handled by
  /// sourcekitd itself and not the plugin. If the plugin doesn't know the request
  /// handle to be cancelled, it should ignore the cancellation request.
  void (*_Nonnull plugin_initialize_register_cancellation_handler)(
    _Nonnull sourcekitd_api_plugin_initialize_params_t,
    _Nonnull SWIFT_SENDABLE sourcekitd_api_cancellation_handler_t
  );

  void *_Null_unspecified(*_Nonnull plugin_initialize_get_swift_ide_inspection_instance)(
    _Null_unspecified sourcekitd_api_plugin_initialize_params_t
  );

  //============================================================================//
  // Request
  //============================================================================//

  sourcekitd_api_variant_type_t (*_Nonnull request_get_type)(
    _Null_unspecified sourcekitd_api_object_t obj
  );

  _Null_unspecified sourcekitd_api_object_t (*_Nonnull request_dictionary_get_value)(
    _Null_unspecified sourcekitd_api_object_t dict,
    _Nonnull sourcekitd_api_uid_t key
  );

  /// The underlying C string for the specified key. NULL if the value for the
  /// specified key is not a C string value or if there is no value for the
  /// specified key.
  const char *_Null_unspecified (*_Nonnull request_dictionary_get_string)(
    _Nonnull sourcekitd_api_object_t dict,
    _Nonnull sourcekitd_api_uid_t key
  );

  /// The underlying \c int64 value for the specified key. 0 if the
  /// value for the specified key is not an integer value or if there is no
  /// value for the specified key.
  int64_t (*_Nonnull request_dictionary_get_int64)(
    _Nonnull sourcekitd_api_object_t dict,
    _Nonnull sourcekitd_api_uid_t key
  );

  /// The underlying \c bool value for the specified key. false if the
  /// value for the specified key is not a Boolean value or if there is no
  /// value for the specified key.
  bool (*_Nonnull request_dictionary_get_bool)(
    _Nonnull sourcekitd_api_object_t dict,
    _Nonnull sourcekitd_api_uid_t key
  );

  _Null_unspecified sourcekitd_api_uid_t (*_Nonnull request_dictionary_get_uid)(
    _Nonnull sourcekitd_api_object_t dict,
    _Nonnull sourcekitd_api_uid_t key
  );

  size_t (*_Nonnull request_array_get_count)(
    _Null_unspecified sourcekitd_api_object_t array
  );

  _Null_unspecified sourcekitd_api_object_t (*_Nonnull request_array_get_value)(
    _Null_unspecified sourcekitd_api_object_t array,
    size_t index
  );

  const char *_Null_unspecified (*_Nonnull request_array_get_string)(
    _Null_unspecified sourcekitd_api_object_t array,
    size_t index
  );

  int64_t (*_Nonnull request_array_get_int64)(
    _Null_unspecified sourcekitd_api_object_t array,
    size_t index
  );

  bool (*_Nonnull request_array_get_bool)(
    _Null_unspecified sourcekitd_api_object_t array,
    size_t index
  );

  _Null_unspecified sourcekitd_api_uid_t (*_Nonnull request_array_get_uid)(
    _Null_unspecified sourcekitd_api_object_t array,
    size_t index
  );

  int64_t (*_Nonnull request_int64_get_value)(
    _Null_unspecified sourcekitd_api_object_t obj
  );

  bool (*_Nonnull request_bool_get_value)(
    _Null_unspecified sourcekitd_api_object_t obj
  );

  size_t (*_Nonnull request_string_get_length)(
    _Null_unspecified sourcekitd_api_object_t obj
  );

  const char *_Null_unspecified (*_Nonnull request_string_get_ptr)(
    _Null_unspecified sourcekitd_api_object_t obj
  );

  _Null_unspecified sourcekitd_api_uid_t (*_Nonnull request_uid_get_value)(
    _Null_unspecified sourcekitd_api_object_t obj
  );

  //============================================================================//
  // Response
  //============================================================================//

  _Nonnull sourcekitd_api_response_t (*_Nonnull response_retain)(
    _Nonnull sourcekitd_api_response_t object
  );

  _Null_unspecified sourcekitd_api_response_t (*_Nonnull response_error_create)(
    sourcekitd_api_error_t kind,
    const char *_Null_unspecified description
  );

  _Nonnull sourcekitd_api_response_t (*_Nonnull response_dictionary_create)(
    const _Null_unspecified sourcekitd_api_uid_t *_Null_unspecified keys,
    const _Null_unspecified sourcekitd_api_response_t *_Null_unspecified values,
    size_t count
  );

  void (*_Nonnull response_dictionary_set_value)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    _Nonnull sourcekitd_api_response_t value
  );

  void (*_Nonnull response_dictionary_set_string)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    const char *_Nonnull string
  );

  void (*_Nonnull response_dictionary_set_stringbuf)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    const char *_Nonnull buf,
    size_t length
  );

  void (*_Nonnull response_dictionary_set_int64)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    int64_t val
  );

  void (*_Nonnull response_dictionary_set_bool)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    bool val
  );

  void (*_Nonnull response_dictionary_set_double)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    double val
  );

  void (*_Nonnull response_dictionary_set_uid)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    _Nonnull sourcekitd_api_uid_t uid
  );

  _Nonnull sourcekitd_api_response_t (*_Nonnull response_array_create)(
    const _Null_unspecified sourcekitd_api_response_t *_Null_unspecified objects,
    size_t count
  );

  void (*_Nonnull response_array_set_value)(
    _Nonnull sourcekitd_api_response_t array,
    size_t index,
    _Nonnull sourcekitd_api_response_t value
  );

  void (*_Nonnull response_array_set_string)(
    _Nonnull sourcekitd_api_response_t array,
    size_t index,
    const char *_Nonnull string
  );

  void (*_Nonnull response_array_set_stringbuf)(
    _Nonnull sourcekitd_api_response_t array,
    size_t index,
    const char *_Nonnull buf,
    size_t length
  );

  void (*_Nonnull response_array_set_int64)(
    _Nonnull sourcekitd_api_response_t array,
    size_t index,
    int64_t val
  );

  void (*_Nonnull response_array_set_double)(
    _Nonnull sourcekitd_api_response_t array,
    size_t index,
    double val
  );

  void (*_Nonnull response_array_set_uid)(
    _Nonnull sourcekitd_api_response_t array,
    size_t index,
    _Nonnull sourcekitd_api_uid_t uid
  );

  void (*_Nonnull response_dictionary_set_custom_buffer)(
    _Nonnull sourcekitd_api_response_t dict,
    _Nonnull sourcekitd_api_uid_t key,
    const void *_Nonnull ptr,
    size_t size
  );
} sourcekitd_service_plugin_api_functions_t;

#endif
