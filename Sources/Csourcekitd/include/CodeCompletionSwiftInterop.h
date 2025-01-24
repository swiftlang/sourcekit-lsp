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

#ifndef SWIFT_C_CODE_COMPLETION_H
#define SWIFT_C_CODE_COMPLETION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// Global state across completions including compiler instance caching.
typedef void *swiftide_api_connection_t;

/// Opaque completion item handle, used to retrieve additional information that
/// may be more expensive to compute.
typedef void *swiftide_api_completion_item_t;

typedef enum swiftide_api_completion_kind_t: uint32_t {
  SWIFTIDE_COMPLETION_KIND_NONE = 0,
  SWIFTIDE_COMPLETION_KIND_IMPORT = 1,
  SWIFTIDE_COMPLETION_KIND_UNRESOLVEDMEMBER = 2,
  SWIFTIDE_COMPLETION_KIND_DOTEXPR = 3,
  SWIFTIDE_COMPLETION_KIND_STMTOREXPR = 4,
  SWIFTIDE_COMPLETION_KIND_POSTFIXEXPRBEGINNING = 5,
  SWIFTIDE_COMPLETION_KIND_POSTFIXEXPR = 6,
  /* obsoleted */SWIFTIDE_COMPLETION_KIND_POSTFIXEXPRPAREN = 7,
  SWIFTIDE_COMPLETION_KIND_KEYPATHEXPROBJC = 8,
  SWIFTIDE_COMPLETION_KIND_KEYPATHEXPRSWIFT = 9,
  SWIFTIDE_COMPLETION_KIND_TYPEDECLRESULTBEGINNING = 10,
  SWIFTIDE_COMPLETION_KIND_TYPESIMPLEBEGINNING = 11,
  SWIFTIDE_COMPLETION_KIND_TYPEIDENTIFIERWITHDOT = 12,
  SWIFTIDE_COMPLETION_KIND_TYPEIDENTIFIERWITHOUTDOT = 13,
  SWIFTIDE_COMPLETION_KIND_CASESTMTKEYWORD = 14,
  SWIFTIDE_COMPLETION_KIND_CASESTMTBEGINNING = 15,
  SWIFTIDE_COMPLETION_KIND_NOMINALMEMBERBEGINNING = 16,
  SWIFTIDE_COMPLETION_KIND_ACCESSORBEGINNING = 17,
  SWIFTIDE_COMPLETION_KIND_ATTRIBUTEBEGIN = 18,
  SWIFTIDE_COMPLETION_KIND_ATTRIBUTEDECLPAREN = 19,
  SWIFTIDE_COMPLETION_KIND_POUNDAVAILABLEPLATFORM = 20,
  SWIFTIDE_COMPLETION_KIND_CALLARG = 21,
  SWIFTIDE_COMPLETION_KIND_LABELEDTRAILINGCLOSURE = 22,
  SWIFTIDE_COMPLETION_KIND_RETURNSTMTEXPR = 23,
  SWIFTIDE_COMPLETION_KIND_YIELDSTMTEXPR = 24,
  SWIFTIDE_COMPLETION_KIND_FOREACHSEQUENCE = 25,
  SWIFTIDE_COMPLETION_KIND_AFTERPOUNDEXPR = 26,
  SWIFTIDE_COMPLETION_KIND_AFTERPOUNDDIRECTIVE = 27,
  SWIFTIDE_COMPLETION_KIND_PLATFORMCONDITON = 28,
  SWIFTIDE_COMPLETION_KIND_AFTERIFSTMTELSE = 29,
  SWIFTIDE_COMPLETION_KIND_GENERICREQUIREMENT = 30,
  SWIFTIDE_COMPLETION_KIND_PRECEDENCEGROUP = 31,
  SWIFTIDE_COMPLETION_KIND_STMTLABEL = 32,
  SWIFTIDE_COMPLETION_KIND_EFFECTSSPECIFIER = 33,
  SWIFTIDE_COMPLETION_KIND_FOREACHPATTERNBEGINNING = 34,
  SWIFTIDE_COMPLETION_KIND_TYPEATTRBEGINNING = 35,
  SWIFTIDE_COMPLETION_KIND_OPTIONALBINDING = 36,
  SWIFTIDE_COMPLETION_KIND_FOREACHKWIN = 37,
  SWIFTIDE_COMPLETION_KIND_WITHOUTCONSTRAINTTYPE = 38,
  SWIFTIDE_COMPLETION_KIND_THENSTMTEXPR = 39,
  SWIFTIDE_COMPLETION_KIND_TYPEBEGINNING = 40,
  SWIFTIDE_COMPLETION_KIND_TYPESIMPLEORCOMPOSITION = 41,
  SWIFTIDE_COMPLETION_KIND_TYPEPOSSIBLEFUNCTIONPARAMBEGINNING = 42,
  SWIFTIDE_COMPLETION_KIND_TYPEATTRINHERITANCEBEGINNING = 43,
} swiftide_api_completion_kind_t;

typedef enum swiftide_api_completion_item_kind_t: uint32_t {
  SWIFTIDE_COMPLETION_ITEM_KIND_DECLARATION = 0,
  SWIFTIDE_COMPLETION_ITEM_KIND_KEYWORD = 1,
  SWIFTIDE_COMPLETION_ITEM_KIND_PATTERN = 2,
  SWIFTIDE_COMPLETION_ITEM_KIND_LITERAL = 3,
  SWIFTIDE_COMPLETION_ITEM_KIND_BUILTINOPERATOR = 4,
} swiftide_api_completion_item_kind_t;

typedef enum swiftide_api_completion_item_decl_kind_t: uint32_t {
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_MODULE = 0,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_CLASS = 1,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_STRUCT = 2,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ENUM = 3,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ENUMELEMENT = 4,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_PROTOCOL = 5,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ASSOCIATEDTYPE = 6,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_TYPEALIAS = 7,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_GENERICTYPEPARAM = 8,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_CONSTRUCTOR = 9,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_DESTRUCTOR = 10,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_SUBSCRIPT = 11,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_STATICMETHOD = 12,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_INSTANCEMETHOD = 13,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_PREFIXOPERATORFUNCTION = 14,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_POSTFIXOPERATORFUNCTION = 15,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_INFIXOPERATORFUNCTION = 16,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_FREEFUNCTION = 17,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_STATICVAR = 18,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_INSTANCEVAR = 19,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_LOCALVAR = 20,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_GLOBALVAR = 21,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_PRECEDENCEGROUP = 22,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ACTOR = 23,
  SWIFTIDE_COMPLETION_ITEM_DECL_KIND_MACRO = 24,
} swiftide_api_completion_item_decl_kind_t;

typedef enum swiftide_api_completion_type_relation_t: uint32_t {
  SWIFTIDE_COMPLETION_TYPE_RELATION_NOTAPPLICABLE = 0,
  SWIFTIDE_COMPLETION_TYPE_RELATION_UNKNOWN = 1,
  SWIFTIDE_COMPLETION_TYPE_RELATION_UNRELATED = 2,
  SWIFTIDE_COMPLETION_TYPE_RELATION_INVALID = 3,
  SWIFTIDE_COMPLETION_TYPE_RELATION_CONVERTIBLE = 4,
  SWIFTIDE_COMPLETION_TYPE_RELATION_IDENTICAL = 5,
} swiftide_api_completion_type_relation_t;

typedef enum swiftide_api_completion_semantic_context_t: uint32_t {
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_NONE = 0,
  /* obsoleted */SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_EXPRESSIONSPECIFIC = 1,
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_LOCAL = 2,
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_CURRENTNOMINAL = 3,
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_SUPER = 4,
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_OUTSIDENOMINAL = 5,
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_CURRENTMODULE = 6,
  SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_OTHERMODULE = 7,
} swiftide_api_completion_semantic_context_t;

typedef enum swiftide_api_completion_flair_t: uint32_t {
  SWIFTIDE_COMPLETION_FLAIR_EXPRESSIONSPECIFIC = 1 << 0,
  SWIFTIDE_COMPLETION_FLAIR_SUPERCHAIN = 1 << 1,
  SWIFTIDE_COMPLETION_FLAIR_ARGUMENTLABELS = 1 << 2,
  SWIFTIDE_COMPLETION_FLAIR_COMMONKEYWORDATCURRENTPOSITION = 1 << 3,
  SWIFTIDE_COMPLETION_FLAIR_RAREKEYWORDATCURRENTPOSITION = 1 << 4,
  SWIFTIDE_COMPLETION_FLAIR_RARETYPEATCURRENTPOSITION = 1 << 5,
  SWIFTIDE_COMPLETION_FLAIR_EXPRESSIONATNONSCRIPTORMAINFILESCOPE = 1 << 6,
} swiftide_api_completion_flair_t;

typedef enum swiftide_api_completion_not_recommended_reason_t: uint32_t {
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_NONE = 0,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_REDUNDANT_IMPORT = 1,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_DEPRECATED = 2,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_INVALID_ASYNC_CONTEXT = 3,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_CROSS_ACTOR_REFERENCE = 4,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_VARIABLE_USED_IN_OWN_DEFINITION = 5,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_REDUNDANT_IMPORT_INDIRECT = 6,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_SOFTDEPRECATED = 7,
  SWIFTIDE_COMPLETION_NOT_RECOMMENDED_NON_ASYNC_ALTERNATIVE_USED_IN_ASYNC_CONTEXT = 8,
} swiftide_api_completion_not_recommended_reason_t;

typedef enum swiftide_api_completion_diagnostic_severity_t: uint32_t {
  SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_NONE = 0,
  SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_ERROR = 1,
  SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_WARNING = 2,
  SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_REMARK  = 3,
  SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_NOTE  = 4,
} swiftide_api_completion_diagnostic_severity_t;

typedef void *swiftide_api_completion_request_t;

typedef void *swiftide_api_completion_response_t;

typedef void *swiftide_api_fuzzy_match_pattern_t;

typedef void *swiftide_api_cache_invalidation_options_t;

/// swiftide equivalent of sourcekitd_request_handle_t
typedef const void *swiftide_api_request_handle_t;


typedef struct {
  _Nonnull swiftide_api_connection_t (*_Nonnull connection_create_with_inspection_instance)(
    void *_Null_unspecified opqueSwiftIDEInspectionInstance
  );

  void (*_Nonnull connection_dispose)(
    _Null_unspecified swiftide_api_connection_t
  );

  void (*_Nonnull connection_mark_cached_compiler_instance_should_be_invalidated)(
    _Null_unspecified swiftide_api_connection_t,
    _Null_unspecified swiftide_api_cache_invalidation_options_t
  );

  /// Override the contents of the file \p path with \p contents. If \p contents
  /// is NULL, go back to using the real the file system.
  void (*_Nonnull set_file_contents)(
    _Null_unspecified swiftide_api_connection_t connection,
    const char *_Null_unspecified path,
    const char *_Null_unspecified contents
  );

  /// Cancel the request with \p handle.
  void (*_Nonnull cancel_request)(
    _Null_unspecified swiftide_api_connection_t _conn,
    _Null_unspecified swiftide_api_request_handle_t handle
  );

  _Null_unspecified swiftide_api_completion_request_t (*_Nonnull completion_request_create)(
    const char *_Null_unspecified path,
    uint32_t offset,
    char *_Null_unspecified const *_Null_unspecified const compiler_args,
    uint32_t num_compiler_args
  );

  void (*_Nonnull completion_request_dispose)(
    _Null_unspecified swiftide_api_completion_request_t
  );

  void (*_Nonnull completion_request_set_annotate_result)(
    _Null_unspecified swiftide_api_completion_request_t,
    bool
  );

  void (*_Nonnull completion_request_set_include_objectliterals)(
    _Null_unspecified swiftide_api_completion_request_t,
    bool
  );

  void (*_Nonnull completion_request_set_add_inits_to_top_level)(
    _Null_unspecified swiftide_api_completion_request_t,
    bool
  );


  void (*_Nonnull completion_request_set_add_call_with_no_default_args)(
    _Null_unspecified swiftide_api_completion_request_t,
    bool
  );

  /// Same as swiftide_complete but supports cancellation.
  /// This request is identified by \p handle. Calling swiftide_cancel_request
  /// with that handle cancels the request.
  /// Note that the caller is responsible for creating a unique request handle.
  /// This differs from the sourcekitd functions in which SourceKit creates a
  /// unique handle and passes it to the client via an out parameter.
  _Null_unspecified swiftide_api_completion_response_t (*_Nonnull complete_cancellable)(
    _Null_unspecified swiftide_api_connection_t _conn,
    _Null_unspecified swiftide_api_completion_request_t _req,
    _Null_unspecified swiftide_api_request_handle_t handle
  );

  void (*_Nonnull completion_result_dispose)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  bool (*_Nonnull completion_result_is_error)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  /// Result has the same lifetime as the result.
  const char *_Null_unspecified (*_Nonnull completion_result_get_error_description)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  bool (*_Nonnull completion_result_is_cancelled)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  /// Copies a string representation of the completion result. This string should
  /// be disposed of with \c free when done.
  const char *_Null_unspecified  (*_Nonnull completion_result_description_copy)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  void (*_Nonnull completion_result_get_completions)(
    _Null_unspecified swiftide_api_completion_response_t,
    void (^_Null_unspecified completions_handler)(
      const _Null_unspecified swiftide_api_completion_item_t *_Null_unspecified completions,
      const char *_Null_unspecified *_Null_unspecified filter_names,
      uint64_t num_completions
    )
  );

  _Null_unspecified swiftide_api_completion_item_t (*_Nonnull completion_result_get_completion_at_index)(
    _Null_unspecified swiftide_api_completion_response_t,
    uint64_t index
  );

  swiftide_api_completion_kind_t (*_Nonnull completion_result_get_kind)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  void (*_Nonnull completion_result_foreach_baseexpr_typename)(
    _Null_unspecified swiftide_api_completion_response_t,
    bool (^_Null_unspecified handler)(const char *_Null_unspecified )
  );

  bool (*_Nonnull completion_result_is_reusing_astcontext)(
    _Null_unspecified swiftide_api_completion_response_t
  );

  /// Copies a string representation of the completion item. This string should
  /// be disposed of with \c free when done.
  const char *_Null_unspecified  (*_Nonnull completion_item_description_copy)(
    _Null_unspecified swiftide_api_completion_item_t
  );


  void (*_Nonnull completion_item_get_label)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t,
    bool annotate,
    void (^_Null_unspecified handler)(const char *_Null_unspecified)
  );

  void (*_Nonnull completion_item_get_source_text)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t,
    void (^_Null_unspecified handler)(const char *_Null_unspecified)
  );

  void (*_Nonnull completion_item_get_type_name)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t,
    bool annotate,
    void (^_Null_unspecified handler)(const char *_Null_unspecified)
  );

  void (*_Nonnull completion_item_get_doc_brief)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t,
    void (^_Null_unspecified handler)(const char *_Null_unspecified)
  );

  void (*_Nonnull completion_item_get_associated_usrs)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t,
    void (^_Null_unspecified handler)(const char *_Null_unspecified *_Null_unspecified, uint64_t)
  );

  uint32_t (*_Nonnull completion_item_get_kind)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  uint32_t (*_Nonnull  completion_item_get_associated_kind)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  uint32_t (*_Nonnull completion_item_get_semantic_context)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  uint32_t (*_Nonnull completion_item_get_flair)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  bool (*_Nonnull completion_item_is_not_recommended)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  uint32_t (*_Nonnull completion_item_not_recommended_reason)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  bool (*_Nonnull completion_item_has_diagnostic)(
    _Null_unspecified swiftide_api_completion_item_t _item
  );

  void (*_Nonnull completion_item_get_diagnostic)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t,
    void (^_Null_unspecified handler)(swiftide_api_completion_diagnostic_severity_t, const char *_Null_unspecified)
  );

  bool (*_Nonnull completion_item_is_system)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  void (*_Nonnull completion_item_get_module_name)(
    _Null_unspecified swiftide_api_completion_response_t _response,
    _Null_unspecified swiftide_api_completion_item_t _item,
    void (^_Null_unspecified handler)(const char *_Null_unspecified)
  );

  uint32_t (*_Nonnull completion_item_get_num_bytes_to_erase)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  uint32_t (*_Nonnull completion_item_get_type_relation)(
    _Null_unspecified swiftide_api_completion_item_t
  );

  /// Returns 0 for items not in an external module, and ~0u if the other module
  /// is not imported or the depth is otherwise unknown.
  uint32_t (*_Nonnull completion_item_import_depth)(
    _Null_unspecified swiftide_api_completion_response_t,
    _Null_unspecified swiftide_api_completion_item_t
  );

  _Null_unspecified swiftide_api_fuzzy_match_pattern_t (*_Nonnull fuzzy_match_pattern_create)(
    const char *_Null_unspecified pattern
  );

  bool (*_Nonnull fuzzy_match_pattern_matches_candidate)(
    _Null_unspecified swiftide_api_fuzzy_match_pattern_t pattern,
    const char *_Null_unspecified candidate,
    double *_Null_unspecified outScore
  );

  void (*_Nonnull fuzzy_match_pattern_dispose)(
    _Null_unspecified swiftide_api_fuzzy_match_pattern_t
  );
} sourcekitd_ide_api_functions_t;

#endif

