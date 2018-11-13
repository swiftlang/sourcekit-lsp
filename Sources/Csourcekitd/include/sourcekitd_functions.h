//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef SOURCEKITDFUNCTIONS_H
#define SOURCEKITDFUNCTIONS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

// Avoid including <sourcekitd/sourcekitd.h> to make sure we don't call the functions directly.
// But we need the types to form the function pointers.
// These are supposed to stay stable across toolchains.

typedef void *sourcekitd_object_t;
typedef struct sourcekitd_uid_s *sourcekitd_uid_t;
typedef void *sourcekitd_response_t;
typedef void *sourcekitd_request_handle_t;

typedef struct {
  uint64_t data[3];
} sourcekitd_variant_t;

typedef enum {
  SOURCEKITD_VARIANT_TYPE_NULL = 0,
  SOURCEKITD_VARIANT_TYPE_DICTIONARY = 1,
  SOURCEKITD_VARIANT_TYPE_ARRAY = 2,
  SOURCEKITD_VARIANT_TYPE_INT64 = 3,
  SOURCEKITD_VARIANT_TYPE_STRING = 4,
  SOURCEKITD_VARIANT_TYPE_UID = 5,
  SOURCEKITD_VARIANT_TYPE_BOOL = 6,
  // Reserved for future addition
  // SOURCEKITD_VARIANT_TYPE_DOUBLE = 7,
  SOURCEKITD_VARIANT_TYPE_DATA = 8,
} sourcekitd_variant_type_t;

typedef enum {
  SOURCEKITD_ERROR_CONNECTION_INTERRUPTED = 1,
  SOURCEKITD_ERROR_REQUEST_INVALID = 2,
  SOURCEKITD_ERROR_REQUEST_FAILED = 3,
  SOURCEKITD_ERROR_REQUEST_CANCELLED = 4
} sourcekitd_error_t;

typedef bool (^sourcekitd_variant_dictionary_applier_t)(sourcekitd_uid_t key,
                                                        sourcekitd_variant_t value);
typedef void(^sourcekitd_interrupted_connection_handler_t)(void);
typedef bool (*sourcekitd_variant_dictionary_applier_f_t)(sourcekitd_uid_t key,
                                                    sourcekitd_variant_t value,
                                                    void *context);
typedef bool (^sourcekitd_variant_array_applier_t)(size_t index,
                                                   sourcekitd_variant_t value);
typedef bool (*sourcekitd_variant_array_applier_f_t)(size_t index,
                                                     sourcekitd_variant_t value,
                                                     void *context);
typedef void (^sourcekitd_response_receiver_t)(sourcekitd_response_t resp);

typedef sourcekitd_uid_t(^sourcekitd_uid_from_str_handler_t)(const char* uidStr);
typedef const char *(^sourcekitd_str_from_uid_handler_t)(sourcekitd_uid_t uid);

typedef struct {
  void (*initialize)(void);
  void (*shutdown)(void);

  sourcekitd_uid_t (*uid_get_from_cstr)(const char *string);
  sourcekitd_uid_t (*uid_get_from_buf)(const char *buf, size_t length);
  size_t (*uid_get_length)(sourcekitd_uid_t obj);
  const char * (*uid_get_string_ptr)(sourcekitd_uid_t obj);
  sourcekitd_object_t (*request_retain)(sourcekitd_object_t object);
  void (*request_release)(sourcekitd_object_t object);
  sourcekitd_object_t (*request_dictionary_create)(const sourcekitd_uid_t *keys, const sourcekitd_object_t *values, size_t count);
  void (*request_dictionary_set_value)(sourcekitd_object_t dict, sourcekitd_uid_t key, sourcekitd_object_t value);
  void (*request_dictionary_set_string)(sourcekitd_object_t dict, sourcekitd_uid_t key, const char *string);
  void (*request_dictionary_set_stringbuf)(sourcekitd_object_t dict, sourcekitd_uid_t key, const char *buf, size_t length);
  void (*request_dictionary_set_int64)(sourcekitd_object_t dict, sourcekitd_uid_t key, int64_t val);
  void (*request_dictionary_set_uid)(sourcekitd_object_t dict, sourcekitd_uid_t key, sourcekitd_uid_t uid);
  sourcekitd_object_t (*request_array_create)(const sourcekitd_object_t *objects, size_t count);
  void (*request_array_set_value)(sourcekitd_object_t array, size_t index, sourcekitd_object_t value);
  void (*request_array_set_string)(sourcekitd_object_t array, size_t index, const char *string);
  void (*request_array_set_stringbuf)(sourcekitd_object_t array, size_t index, const char *buf, size_t length);
  void (*request_array_set_int64)(sourcekitd_object_t array, size_t index, int64_t val);
  void (*request_array_set_uid)(sourcekitd_object_t array, size_t index, sourcekitd_uid_t uid);
  sourcekitd_object_t (*request_int64_create)(int64_t val);
  sourcekitd_object_t (*request_string_create)(const char *string);
  sourcekitd_object_t (*request_uid_create)(sourcekitd_uid_t uid);
  sourcekitd_object_t (*request_create_from_yaml)(const char *yaml, char **error);
  void (*request_description_dump)(sourcekitd_object_t obj);
  char *(*request_description_copy)(sourcekitd_object_t obj);
  void (*response_dispose)(sourcekitd_response_t obj);
  bool (*response_is_error)(sourcekitd_response_t obj);
  sourcekitd_error_t (*response_error_get_kind)(sourcekitd_response_t err);
  const char * (*response_error_get_description)(sourcekitd_response_t err);
  sourcekitd_variant_t (*response_get_value)(sourcekitd_response_t resp);
  sourcekitd_variant_type_t (*variant_get_type)(sourcekitd_variant_t obj);
  sourcekitd_variant_t (*variant_dictionary_get_value)(sourcekitd_variant_t dict, sourcekitd_uid_t key);
  const char * (*variant_dictionary_get_string)(sourcekitd_variant_t dict, sourcekitd_uid_t key);
  int64_t (*variant_dictionary_get_int64)(sourcekitd_variant_t dict, sourcekitd_uid_t key);
  bool (*variant_dictionary_get_bool)(sourcekitd_variant_t dict, sourcekitd_uid_t key);
  sourcekitd_uid_t (*variant_dictionary_get_uid)(sourcekitd_variant_t dict, sourcekitd_uid_t key);
  bool (*variant_dictionary_apply)(sourcekitd_variant_t dict, sourcekitd_variant_dictionary_applier_t applier);
  size_t (*variant_array_get_count)(sourcekitd_variant_t array);
  sourcekitd_variant_t (*variant_array_get_value)(sourcekitd_variant_t array, size_t index);
  const char * (*variant_array_get_string)(sourcekitd_variant_t array, size_t index);
  int64_t (*variant_array_get_int64)(sourcekitd_variant_t array, size_t index);
  bool (*variant_array_get_bool)(sourcekitd_variant_t array, size_t index);
  sourcekitd_uid_t (*variant_array_get_uid)(sourcekitd_variant_t array, size_t index);
  bool (*variant_array_apply)(sourcekitd_variant_t array, sourcekitd_variant_array_applier_t applier);
  int64_t (*variant_int64_get_value)(sourcekitd_variant_t obj);
  bool (*variant_bool_get_value)(sourcekitd_variant_t obj);
  size_t (*variant_string_get_length)(sourcekitd_variant_t obj);
  const char * (*variant_string_get_ptr)(sourcekitd_variant_t obj);
  size_t (*variant_data_get_size)(sourcekitd_variant_t obj);
  const void * (*variant_data_get_ptr)(sourcekitd_variant_t obj);
  sourcekitd_uid_t (*variant_uid_get_value)(sourcekitd_variant_t obj);
  void (*response_description_dump)(sourcekitd_response_t resp);
  void (*response_description_dump_filedesc)(sourcekitd_response_t resp, int fd);
  char *(*response_description_copy)(sourcekitd_response_t resp);
  void (*variant_description_dump)(sourcekitd_variant_t obj);
  void (*variant_description_dump_filedesc)(sourcekitd_variant_t obj, int fd);
  char * (*variant_description_copy)(sourcekitd_variant_t obj);
  sourcekitd_response_t (*send_request_sync)(sourcekitd_object_t req);
  void (*send_request)(sourcekitd_object_t req, sourcekitd_request_handle_t *out_handle, sourcekitd_response_receiver_t receiver);
  void (*cancel_request)(sourcekitd_request_handle_t handle);
  void (*set_notification_handler)(sourcekitd_response_receiver_t receiver);
  void (*set_uid_handlers)(sourcekitd_uid_from_str_handler_t uid_from_str, sourcekitd_str_from_uid_handler_t str_from_uid);
} sourcekitd_functions_t;

#endif
