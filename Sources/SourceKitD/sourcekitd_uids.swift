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
// Automatically Generated From UIDs.swift.gyb.
// Do Not Edit Directly! To regenerate run Utilities/generate-uids.py

package import Csourcekitd

// swift-format-ignore: TypeNamesShouldBeCapitalized
// Matching C style types
package struct sourcekitd_api_keys {
  /// `key.version_major`
  package let versionMajor: sourcekitd_api_uid_t
  /// `key.version_minor`
  package let versionMinor: sourcekitd_api_uid_t
  /// `key.version_patch`
  package let versionPatch: sourcekitd_api_uid_t
  /// `key.results`
  package let results: sourcekitd_api_uid_t
  /// `key.request`
  package let request: sourcekitd_api_uid_t
  /// `key.notification`
  package let notification: sourcekitd_api_uid_t
  /// `key.kind`
  package let kind: sourcekitd_api_uid_t
  /// `key.accessibility`
  package let accessLevel: sourcekitd_api_uid_t
  /// `key.setter_accessibility`
  package let setterAccessLevel: sourcekitd_api_uid_t
  /// `key.keyword`
  package let keyword: sourcekitd_api_uid_t
  /// `key.name`
  package let name: sourcekitd_api_uid_t
  /// `key.usr`
  package let usr: sourcekitd_api_uid_t
  /// `key.original_usr`
  package let originalUSR: sourcekitd_api_uid_t
  /// `key.default_implementation_of`
  package let defaultImplementationOf: sourcekitd_api_uid_t
  /// `key.interested_usr`
  package let interestedUSR: sourcekitd_api_uid_t
  /// `key.generic_params`
  package let genericParams: sourcekitd_api_uid_t
  /// `key.generic_requirements`
  package let genericRequirements: sourcekitd_api_uid_t
  /// `key.doc.full_as_xml`
  package let docFullAsXML: sourcekitd_api_uid_t
  /// `key.doc_comment`
  package let docComment: sourcekitd_api_uid_t
  /// `key.line`
  package let line: sourcekitd_api_uid_t
  /// `key.column`
  package let column: sourcekitd_api_uid_t
  /// `key.receiver_usr`
  package let receiverUSR: sourcekitd_api_uid_t
  /// `key.receivers`
  package let receivers: sourcekitd_api_uid_t
  /// `key.is_dynamic`
  package let isDynamic: sourcekitd_api_uid_t
  /// `key.is_implicit`
  package let isImplicit: sourcekitd_api_uid_t
  /// `key.filepath`
  package let filePath: sourcekitd_api_uid_t
  /// `key.module_interface_name`
  package let moduleInterfaceName: sourcekitd_api_uid_t
  /// `key.hash`
  package let hash: sourcekitd_api_uid_t
  /// `key.severity`
  package let severity: sourcekitd_api_uid_t
  /// `key.offset`
  package let offset: sourcekitd_api_uid_t
  /// `key.length`
  package let length: sourcekitd_api_uid_t
  /// `key.sourcefile`
  package let sourceFile: sourcekitd_api_uid_t
  /// `key.primary_file`
  package let primaryFile: sourcekitd_api_uid_t
  /// `key.enablesyntaxmap`
  package let enableSyntaxMap: sourcekitd_api_uid_t
  /// `key.enablesubstructure`
  package let enableStructure: sourcekitd_api_uid_t
  /// `key.id`
  package let id: sourcekitd_api_uid_t
  /// `key.description`
  package let description: sourcekitd_api_uid_t
  /// `key.typename`
  package let typeName: sourcekitd_api_uid_t
  /// `key.runtime_name`
  package let runtimeName: sourcekitd_api_uid_t
  /// `key.selector_name`
  package let selectorName: sourcekitd_api_uid_t
  /// `key.annotated_decl`
  package let annotatedDecl: sourcekitd_api_uid_t
  /// `key.fully_annotated_decl`
  package let fullyAnnotatedDecl: sourcekitd_api_uid_t
  /// `key.fully_annotated_generic_signature`
  package let fullyAnnotatedGenericSignature: sourcekitd_api_uid_t
  /// `key.signatures`
  package let signatures: sourcekitd_api_uid_t
  /// `key.active_signature`
  package let activeSignature: sourcekitd_api_uid_t
  /// `key.parameters`
  package let parameters: sourcekitd_api_uid_t
  /// `key.active_parameter`
  package let activeParameter: sourcekitd_api_uid_t
  /// `key.doc.brief`
  package let docBrief: sourcekitd_api_uid_t
  /// `key.context`
  package let context: sourcekitd_api_uid_t
  /// `key.typerelation`
  package let typeRelation: sourcekitd_api_uid_t
  /// `key.moduleimportdepth`
  package let moduleImportDepth: sourcekitd_api_uid_t
  /// `key.num_bytes_to_erase`
  package let numBytesToErase: sourcekitd_api_uid_t
  /// `key.not_recommended`
  package let notRecommended: sourcekitd_api_uid_t
  /// `key.declarations`
  package let declarations: sourcekitd_api_uid_t
  /// `key.enabledeclarations`
  package let enableDeclarations: sourcekitd_api_uid_t
  /// `key.annotations`
  package let annotations: sourcekitd_api_uid_t
  /// `key.semantic_tokens`
  package let semanticTokens: sourcekitd_api_uid_t
  /// `key.diagnostic_stage`
  package let diagnosticStage: sourcekitd_api_uid_t
  /// `key.syntaxmap`
  package let syntaxMap: sourcekitd_api_uid_t
  /// `key.is_system`
  package let isSystem: sourcekitd_api_uid_t
  /// `key.related`
  package let related: sourcekitd_api_uid_t
  /// `key.inherits`
  package let inherits: sourcekitd_api_uid_t
  /// `key.conforms`
  package let conforms: sourcekitd_api_uid_t
  /// `key.extends`
  package let extends: sourcekitd_api_uid_t
  /// `key.dependencies`
  package let dependencies: sourcekitd_api_uid_t
  /// `key.entities`
  package let entities: sourcekitd_api_uid_t
  /// `key.nameoffset`
  package let nameOffset: sourcekitd_api_uid_t
  /// `key.namelength`
  package let nameLength: sourcekitd_api_uid_t
  /// `key.bodyoffset`
  package let bodyOffset: sourcekitd_api_uid_t
  /// `key.bodylength`
  package let bodyLength: sourcekitd_api_uid_t
  /// `key.docoffset`
  package let docOffset: sourcekitd_api_uid_t
  /// `key.doclength`
  package let docLength: sourcekitd_api_uid_t
  /// `key.is_active`
  package let isActive: sourcekitd_api_uid_t
  /// `key.is_local`
  package let isLocal: sourcekitd_api_uid_t
  /// `key.inheritedtypes`
  package let inheritedTypes: sourcekitd_api_uid_t
  /// `key.attributes`
  package let attributes: sourcekitd_api_uid_t
  /// `key.attribute`
  package let attribute: sourcekitd_api_uid_t
  /// `key.elements`
  package let elements: sourcekitd_api_uid_t
  /// `key.substructure`
  package let subStructure: sourcekitd_api_uid_t
  /// `key.ranges`
  package let ranges: sourcekitd_api_uid_t
  /// `key.fixits`
  package let fixits: sourcekitd_api_uid_t
  /// `key.generated_buffers`
  package let generatedBuffers: sourcekitd_api_uid_t
  /// `key.buffer_text`
  package let bufferText: sourcekitd_api_uid_t
  /// `key.original_location`
  package let originalLocation: sourcekitd_api_uid_t
  /// `key.diagnostics`
  package let diagnostics: sourcekitd_api_uid_t
  /// `key.educational_note_paths`
  package let educationalNotePaths: sourcekitd_api_uid_t
  /// `key.editor.format.options`
  package let formatOptions: sourcekitd_api_uid_t
  /// `key.codecomplete.options`
  package let codeCompleteOptions: sourcekitd_api_uid_t
  /// `key.typecontextinfo.options`
  package let typeContextInfoOptions: sourcekitd_api_uid_t
  /// `key.conformingmethods.options`
  package let conformingMethodListOptions: sourcekitd_api_uid_t
  /// `key.codecomplete.filterrules`
  package let filterRules: sourcekitd_api_uid_t
  /// `key.nextrequeststart`
  package let nextRequestStart: sourcekitd_api_uid_t
  /// `key.popular`
  package let popular: sourcekitd_api_uid_t
  /// `key.unpopular`
  package let unpopular: sourcekitd_api_uid_t
  /// `key.hide`
  package let hide: sourcekitd_api_uid_t
  /// `key.platform`
  package let platform: sourcekitd_api_uid_t
  /// `key.is_deprecated`
  package let isDeprecated: sourcekitd_api_uid_t
  /// `key.is_unavailable`
  package let isUnavailable: sourcekitd_api_uid_t
  /// `key.is_optional`
  package let isOptional: sourcekitd_api_uid_t
  /// `key.is_async`
  package let isAsync: sourcekitd_api_uid_t
  /// `key.message`
  package let message: sourcekitd_api_uid_t
  /// `key.introduced`
  package let introduced: sourcekitd_api_uid_t
  /// `key.deprecated`
  package let deprecated: sourcekitd_api_uid_t
  /// `key.obsoleted`
  package let obsoleted: sourcekitd_api_uid_t
  /// `key.cancel_builds`
  package let cancelBuilds: sourcekitd_api_uid_t
  /// `key.removecache`
  package let removeCache: sourcekitd_api_uid_t
  /// `key.typeusr`
  package let typeUsr: sourcekitd_api_uid_t
  /// `key.containertypeusr`
  package let containerTypeUsr: sourcekitd_api_uid_t
  /// `key.modulegroups`
  package let moduleGroups: sourcekitd_api_uid_t
  /// `key.basename`
  package let baseName: sourcekitd_api_uid_t
  /// `key.argnames`
  package let argNames: sourcekitd_api_uid_t
  /// `key.selectorpieces`
  package let selectorPieces: sourcekitd_api_uid_t
  /// `key.namekind`
  package let nameKind: sourcekitd_api_uid_t
  /// `key.localization_key`
  package let localizationKey: sourcekitd_api_uid_t
  /// `key.is_zero_arg_selector`
  package let isZeroArgSelector: sourcekitd_api_uid_t
  /// `key.swift_version`
  package let swiftVersion: sourcekitd_api_uid_t
  /// `key.value`
  package let value: sourcekitd_api_uid_t
  /// `key.enablediagnostics`
  package let enableDiagnostics: sourcekitd_api_uid_t
  /// `key.groupname`
  package let groupName: sourcekitd_api_uid_t
  /// `key.actionname`
  package let actionName: sourcekitd_api_uid_t
  /// `key.synthesizedextensions`
  package let synthesizedExtension: sourcekitd_api_uid_t
  /// `key.usingswiftargs`
  package let usingSwiftArgs: sourcekitd_api_uid_t
  /// `key.names`
  package let names: sourcekitd_api_uid_t
  /// `key.uids`
  package let uiDs: sourcekitd_api_uid_t
  /// `key.syntactic_only`
  package let syntacticOnly: sourcekitd_api_uid_t
  /// `key.parent_loc`
  package let parentLoc: sourcekitd_api_uid_t
  /// `key.is_test_candidate`
  package let isTestCandidate: sourcekitd_api_uid_t
  /// `key.overrides`
  package let overrides: sourcekitd_api_uid_t
  /// `key.associated_usrs`
  package let associatedUSRs: sourcekitd_api_uid_t
  /// `key.modulename`
  package let moduleName: sourcekitd_api_uid_t
  /// `key.related_decls`
  package let relatedDecls: sourcekitd_api_uid_t
  /// `key.simplified`
  package let simplified: sourcekitd_api_uid_t
  /// `key.rangecontent`
  package let rangeContent: sourcekitd_api_uid_t
  /// `key.cancel_on_subsequent_request`
  package let cancelOnSubsequentRequest: sourcekitd_api_uid_t
  /// `key.include_non_editable_base_names`
  package let includeNonEditableBaseNames: sourcekitd_api_uid_t
  /// `key.renamelocations`
  package let renameLocations: sourcekitd_api_uid_t
  /// `key.locations`
  package let locations: sourcekitd_api_uid_t
  /// `key.nametype`
  package let nameType: sourcekitd_api_uid_t
  /// `key.newname`
  package let newName: sourcekitd_api_uid_t
  /// `key.categorizededits`
  package let categorizedEdits: sourcekitd_api_uid_t
  /// `key.categorizedranges`
  package let categorizedRanges: sourcekitd_api_uid_t
  /// `key.rangesworthnote`
  package let rangesWorthNote: sourcekitd_api_uid_t
  /// `key.edits`
  package let edits: sourcekitd_api_uid_t
  /// `key.endline`
  package let endLine: sourcekitd_api_uid_t
  /// `key.endcolumn`
  package let endColumn: sourcekitd_api_uid_t
  /// `key.argindex`
  package let argIndex: sourcekitd_api_uid_t
  /// `key.text`
  package let text: sourcekitd_api_uid_t
  /// `key.category`
  package let category: sourcekitd_api_uid_t
  /// `key.categories`
  package let categories: sourcekitd_api_uid_t
  /// `key.is_function_like`
  package let isFunctionLike: sourcekitd_api_uid_t
  /// `key.is_non_protocol_type`
  package let isNonProtocolType: sourcekitd_api_uid_t
  /// `key.refactor_actions`
  package let refactorActions: sourcekitd_api_uid_t
  /// `key.retrieve_refactor_actions`
  package let retrieveRefactorActions: sourcekitd_api_uid_t
  /// `key.symbol_graph`
  package let symbolGraph: sourcekitd_api_uid_t
  /// `key.retrieve_symbol_graph`
  package let retrieveSymbolGraph: sourcekitd_api_uid_t
  /// `key.parent_contexts`
  package let parentContexts: sourcekitd_api_uid_t
  /// `key.referenced_symbols`
  package let referencedSymbols: sourcekitd_api_uid_t
  /// `key.is_spi`
  package let isSPI: sourcekitd_api_uid_t
  /// `key.actionuid`
  package let actionUID: sourcekitd_api_uid_t
  /// `key.actionunavailablereason`
  package let actionUnavailableReason: sourcekitd_api_uid_t
  /// `key.compileid`
  package let compileID: sourcekitd_api_uid_t
  /// `key.compilerargs-string`
  package let compilerArgsString: sourcekitd_api_uid_t
  /// `key.implicitmembers`
  package let implicitMembers: sourcekitd_api_uid_t
  /// `key.expectedtypes`
  package let expectedTypes: sourcekitd_api_uid_t
  /// `key.members`
  package let members: sourcekitd_api_uid_t
  /// `key.printedtypebuffer`
  package let typeBuffer: sourcekitd_api_uid_t
  /// `key.expression_type_list`
  package let expressionTypeList: sourcekitd_api_uid_t
  /// `key.expression_offset`
  package let expressionOffset: sourcekitd_api_uid_t
  /// `key.expression_length`
  package let expressionLength: sourcekitd_api_uid_t
  /// `key.expression_type`
  package let expressionType: sourcekitd_api_uid_t
  /// `key.variable_type_list`
  package let variableTypeList: sourcekitd_api_uid_t
  /// `key.variable_offset`
  package let variableOffset: sourcekitd_api_uid_t
  /// `key.variable_length`
  package let variableLength: sourcekitd_api_uid_t
  /// `key.variable_type`
  package let variableType: sourcekitd_api_uid_t
  /// `key.variable_type_explicit`
  package let variableTypeExplicit: sourcekitd_api_uid_t
  /// `key.fully_qualified`
  package let fullyQualified: sourcekitd_api_uid_t
  /// `key.canonicalize_type`
  package let canonicalizeType: sourcekitd_api_uid_t
  /// `key.internal_diagnostic`
  package let internalDiagnostic: sourcekitd_api_uid_t
  /// `key.vfs.name`
  package let vfsName: sourcekitd_api_uid_t
  /// `key.vfs.options`
  package let vfsOptions: sourcekitd_api_uid_t
  /// `key.files`
  package let files: sourcekitd_api_uid_t
  /// `key.optimize_for_ide`
  package let optimizeForIDE: sourcekitd_api_uid_t
  /// `key.required_bystanders`
  package let requiredBystanders: sourcekitd_api_uid_t
  /// `key.reusingastcontext`
  package let reusingASTContext: sourcekitd_api_uid_t
  /// `key.completion_max_astcontext_reuse_count`
  package let completionMaxASTContextReuseCount: sourcekitd_api_uid_t
  /// `key.completion_check_dependency_interval`
  package let completionCheckDependencyInterval: sourcekitd_api_uid_t
  /// `key.annotated.typename`
  package let annotatedTypename: sourcekitd_api_uid_t
  /// `key.compile_operation`
  package let compileOperation: sourcekitd_api_uid_t
  /// `key.effective_access`
  package let effectiveAccess: sourcekitd_api_uid_t
  /// `key.decl_lang`
  package let declarationLang: sourcekitd_api_uid_t
  /// `key.secondary_symbols`
  package let secondarySymbols: sourcekitd_api_uid_t
  /// `key.simulate_long_request`
  package let simulateLongRequest: sourcekitd_api_uid_t
  /// `key.is_synthesized`
  package let isSynthesized: sourcekitd_api_uid_t
  /// `key.buffer_name`
  package let bufferName: sourcekitd_api_uid_t
  /// `key.barriers_enabled`
  package let barriersEnabled: sourcekitd_api_uid_t
  /// `key.expansions`
  package let expansions: sourcekitd_api_uid_t
  /// `key.macro_roles`
  package let macroRoles: sourcekitd_api_uid_t
  /// `key.expanded_macro_replacements`
  package let expandedMacroReplacements: sourcekitd_api_uid_t
  /// `key.index_store_path`
  package let indexStorePath: sourcekitd_api_uid_t
  /// `key.index_unit_output_path`
  package let indexUnitOutputPath: sourcekitd_api_uid_t
  /// `key.include_locals`
  package let includeLocals: sourcekitd_api_uid_t
  /// `key.compress`
  package let compress: sourcekitd_api_uid_t
  /// `key.ignore_clang_modules`
  package let ignoreClangModules: sourcekitd_api_uid_t
  /// `key.include_system_modules`
  package let includeSystemModules: sourcekitd_api_uid_t
  /// `key.ignore_stdlib`
  package let ignoreStdlib: sourcekitd_api_uid_t
  /// `key.disable_implicit_modules`
  package let disableImplicitModules: sourcekitd_api_uid_t
  /// `key.compilerargs`
  package let compilerArgs: sourcekitd_api_uid_t
  /// `key.sourcetext`
  package let sourceText: sourcekitd_api_uid_t
  /// `key.codecomplete.sort.byname`
  package let sortByName: sourcekitd_api_uid_t
  /// `key.codecomplete.sort.useimportdepth`
  package let useImportDepth: sourcekitd_api_uid_t
  /// `key.codecomplete.group.overloads`
  package let groupOverloads: sourcekitd_api_uid_t
  /// `key.codecomplete.group.stems`
  package let groupStems: sourcekitd_api_uid_t
  /// `key.codecomplete.filtertext`
  package let filterText: sourcekitd_api_uid_t
  /// `key.codecomplete.requestlimit`
  package let requestLimit: sourcekitd_api_uid_t
  /// `key.codecomplete.requeststart`
  package let requestStart: sourcekitd_api_uid_t
  /// `key.codecomplete.hideunderscores`
  package let hideUnderscores: sourcekitd_api_uid_t
  /// `key.codecomplete.hidelowpriority`
  package let hideLowPriority: sourcekitd_api_uid_t
  /// `key.codecomplete.hidebyname`
  package let hideByName: sourcekitd_api_uid_t
  /// `key.codecomplete.includeexactmatch`
  package let includeExactMatch: sourcekitd_api_uid_t
  /// `key.codecomplete.addinnerresults`
  package let addInnerResults: sourcekitd_api_uid_t
  /// `key.codecomplete.addinneroperators`
  package let addInnerOperators: sourcekitd_api_uid_t
  /// `key.codecomplete.addinitstotoplevel`
  package let addInitsToTopLevel: sourcekitd_api_uid_t
  /// `key.codecomplete.fuzzymatching`
  package let fuzzyMatching: sourcekitd_api_uid_t
  /// `key.codecomplete.showtopnonliteralresults`
  package let topNonLiteral: sourcekitd_api_uid_t
  /// `key.codecomplete.sort.contextweight`
  package let contextWeight: sourcekitd_api_uid_t
  /// `key.codecomplete.sort.fuzzyweight`
  package let fuzzyWeight: sourcekitd_api_uid_t
  /// `key.codecomplete.sort.popularitybonus`
  package let popularityBonus: sourcekitd_api_uid_t
  /// `key.codecomplete.annotateddescription`
  package let annotatedDescription: sourcekitd_api_uid_t
  /// `key.codecomplete.includeobjectliterals`
  package let includeObjectLiterals: sourcekitd_api_uid_t
  /// `key.codecomplete.use_new_api`
  package let useNewAPI: sourcekitd_api_uid_t
  /// `key.codecomplete.addcallwithnodefaultargs`
  package let addCallWithNoDefaultArgs: sourcekitd_api_uid_t
  /// `key.codecomplete.include_semantic_components`
  package let includeSemanticComponents: sourcekitd_api_uid_t
  /// `key.codecomplete.use_xpc_serialization`
  package let useXPCSerialization: sourcekitd_api_uid_t
  /// `key.codecomplete.maxresults`
  package let maxResults: sourcekitd_api_uid_t
  /// `key.annotated.typename`
  package let annotatedTypeName: sourcekitd_api_uid_t
  /// `key.priority_bucket`
  package let priorityBucket: sourcekitd_api_uid_t
  /// `key.identifier`
  package let identifier: sourcekitd_api_uid_t
  /// `key.text_match_score`
  package let textMatchScore: sourcekitd_api_uid_t
  /// `key.semantic_score`
  package let semanticScore: sourcekitd_api_uid_t
  /// `key.semantic_score_components`
  package let semanticScoreComponents: sourcekitd_api_uid_t
  /// `key.symbol_popularity`
  package let symbolPopularity: sourcekitd_api_uid_t
  /// `key.module_popularity`
  package let modulePopularity: sourcekitd_api_uid_t
  /// `key.popularity.key`
  package let popularityKey: sourcekitd_api_uid_t
  /// `key.popularity.value.int.billion`
  package let popularityValueIntBillion: sourcekitd_api_uid_t
  /// `key.recent_completions`
  package let recentCompletions: sourcekitd_api_uid_t
  /// `key.unfiltered_result_count`
  package let unfilteredResultCount: sourcekitd_api_uid_t
  /// `key.member_access_types`
  package let memberAccessTypes: sourcekitd_api_uid_t
  /// `key.has_diagnostic`
  package let hasDiagnostic: sourcekitd_api_uid_t
  /// `key.group_id`
  package let groupId: sourcekitd_api_uid_t
  /// `key.scoped_popularity_table_path`
  package let scopedPopularityTablePath: sourcekitd_api_uid_t
  /// `key.popular_modules`
  package let popularModules: sourcekitd_api_uid_t
  /// `key.notorious_modules`
  package let notoriousModules: sourcekitd_api_uid_t
  /// `key.codecomplete.setpopularapi_used_score_components`
  package let usedScoreComponents: sourcekitd_api_uid_t
  /// `key.editor.format.usetabs`
  package let useTabs: sourcekitd_api_uid_t
  /// `key.editor.format.indentwidth`
  package let indentWidth: sourcekitd_api_uid_t
  /// `key.editor.format.tabwidth`
  package let tabWidth: sourcekitd_api_uid_t
  /// `key.editor.format.indent_switch_case`
  package let indentSwitchCase: sourcekitd_api_uid_t

  package init(api: sourcekitd_api_functions_t) {
    versionMajor = api.uid_get_from_cstr("key.version_major")!
    versionMinor = api.uid_get_from_cstr("key.version_minor")!
    versionPatch = api.uid_get_from_cstr("key.version_patch")!
    results = api.uid_get_from_cstr("key.results")!
    request = api.uid_get_from_cstr("key.request")!
    notification = api.uid_get_from_cstr("key.notification")!
    kind = api.uid_get_from_cstr("key.kind")!
    accessLevel = api.uid_get_from_cstr("key.accessibility")!
    setterAccessLevel = api.uid_get_from_cstr("key.setter_accessibility")!
    keyword = api.uid_get_from_cstr("key.keyword")!
    name = api.uid_get_from_cstr("key.name")!
    usr = api.uid_get_from_cstr("key.usr")!
    originalUSR = api.uid_get_from_cstr("key.original_usr")!
    defaultImplementationOf = api.uid_get_from_cstr("key.default_implementation_of")!
    interestedUSR = api.uid_get_from_cstr("key.interested_usr")!
    genericParams = api.uid_get_from_cstr("key.generic_params")!
    genericRequirements = api.uid_get_from_cstr("key.generic_requirements")!
    docFullAsXML = api.uid_get_from_cstr("key.doc.full_as_xml")!
    docComment = api.uid_get_from_cstr("key.doc_comment")!
    line = api.uid_get_from_cstr("key.line")!
    column = api.uid_get_from_cstr("key.column")!
    receiverUSR = api.uid_get_from_cstr("key.receiver_usr")!
    receivers = api.uid_get_from_cstr("key.receivers")!
    isDynamic = api.uid_get_from_cstr("key.is_dynamic")!
    isImplicit = api.uid_get_from_cstr("key.is_implicit")!
    filePath = api.uid_get_from_cstr("key.filepath")!
    moduleInterfaceName = api.uid_get_from_cstr("key.module_interface_name")!
    hash = api.uid_get_from_cstr("key.hash")!
    severity = api.uid_get_from_cstr("key.severity")!
    offset = api.uid_get_from_cstr("key.offset")!
    length = api.uid_get_from_cstr("key.length")!
    sourceFile = api.uid_get_from_cstr("key.sourcefile")!
    primaryFile = api.uid_get_from_cstr("key.primary_file")!
    enableSyntaxMap = api.uid_get_from_cstr("key.enablesyntaxmap")!
    enableStructure = api.uid_get_from_cstr("key.enablesubstructure")!
    id = api.uid_get_from_cstr("key.id")!
    description = api.uid_get_from_cstr("key.description")!
    typeName = api.uid_get_from_cstr("key.typename")!
    runtimeName = api.uid_get_from_cstr("key.runtime_name")!
    selectorName = api.uid_get_from_cstr("key.selector_name")!
    annotatedDecl = api.uid_get_from_cstr("key.annotated_decl")!
    fullyAnnotatedDecl = api.uid_get_from_cstr("key.fully_annotated_decl")!
    fullyAnnotatedGenericSignature = api.uid_get_from_cstr("key.fully_annotated_generic_signature")!
    signatures = api.uid_get_from_cstr("key.signatures")!
    activeSignature = api.uid_get_from_cstr("key.active_signature")!
    parameters = api.uid_get_from_cstr("key.parameters")!
    activeParameter = api.uid_get_from_cstr("key.active_parameter")!
    docBrief = api.uid_get_from_cstr("key.doc.brief")!
    context = api.uid_get_from_cstr("key.context")!
    typeRelation = api.uid_get_from_cstr("key.typerelation")!
    moduleImportDepth = api.uid_get_from_cstr("key.moduleimportdepth")!
    numBytesToErase = api.uid_get_from_cstr("key.num_bytes_to_erase")!
    notRecommended = api.uid_get_from_cstr("key.not_recommended")!
    declarations = api.uid_get_from_cstr("key.declarations")!
    enableDeclarations = api.uid_get_from_cstr("key.enabledeclarations")!
    annotations = api.uid_get_from_cstr("key.annotations")!
    semanticTokens = api.uid_get_from_cstr("key.semantic_tokens")!
    diagnosticStage = api.uid_get_from_cstr("key.diagnostic_stage")!
    syntaxMap = api.uid_get_from_cstr("key.syntaxmap")!
    isSystem = api.uid_get_from_cstr("key.is_system")!
    related = api.uid_get_from_cstr("key.related")!
    inherits = api.uid_get_from_cstr("key.inherits")!
    conforms = api.uid_get_from_cstr("key.conforms")!
    extends = api.uid_get_from_cstr("key.extends")!
    dependencies = api.uid_get_from_cstr("key.dependencies")!
    entities = api.uid_get_from_cstr("key.entities")!
    nameOffset = api.uid_get_from_cstr("key.nameoffset")!
    nameLength = api.uid_get_from_cstr("key.namelength")!
    bodyOffset = api.uid_get_from_cstr("key.bodyoffset")!
    bodyLength = api.uid_get_from_cstr("key.bodylength")!
    docOffset = api.uid_get_from_cstr("key.docoffset")!
    docLength = api.uid_get_from_cstr("key.doclength")!
    isActive = api.uid_get_from_cstr("key.is_active")!
    isLocal = api.uid_get_from_cstr("key.is_local")!
    inheritedTypes = api.uid_get_from_cstr("key.inheritedtypes")!
    attributes = api.uid_get_from_cstr("key.attributes")!
    attribute = api.uid_get_from_cstr("key.attribute")!
    elements = api.uid_get_from_cstr("key.elements")!
    subStructure = api.uid_get_from_cstr("key.substructure")!
    ranges = api.uid_get_from_cstr("key.ranges")!
    fixits = api.uid_get_from_cstr("key.fixits")!
    generatedBuffers = api.uid_get_from_cstr("key.generated_buffers")!
    bufferText = api.uid_get_from_cstr("key.buffer_text")!
    originalLocation = api.uid_get_from_cstr("key.original_location")!
    diagnostics = api.uid_get_from_cstr("key.diagnostics")!
    educationalNotePaths = api.uid_get_from_cstr("key.educational_note_paths")!
    formatOptions = api.uid_get_from_cstr("key.editor.format.options")!
    codeCompleteOptions = api.uid_get_from_cstr("key.codecomplete.options")!
    typeContextInfoOptions = api.uid_get_from_cstr("key.typecontextinfo.options")!
    conformingMethodListOptions = api.uid_get_from_cstr("key.conformingmethods.options")!
    filterRules = api.uid_get_from_cstr("key.codecomplete.filterrules")!
    nextRequestStart = api.uid_get_from_cstr("key.nextrequeststart")!
    popular = api.uid_get_from_cstr("key.popular")!
    unpopular = api.uid_get_from_cstr("key.unpopular")!
    hide = api.uid_get_from_cstr("key.hide")!
    platform = api.uid_get_from_cstr("key.platform")!
    isDeprecated = api.uid_get_from_cstr("key.is_deprecated")!
    isUnavailable = api.uid_get_from_cstr("key.is_unavailable")!
    isOptional = api.uid_get_from_cstr("key.is_optional")!
    isAsync = api.uid_get_from_cstr("key.is_async")!
    message = api.uid_get_from_cstr("key.message")!
    introduced = api.uid_get_from_cstr("key.introduced")!
    deprecated = api.uid_get_from_cstr("key.deprecated")!
    obsoleted = api.uid_get_from_cstr("key.obsoleted")!
    cancelBuilds = api.uid_get_from_cstr("key.cancel_builds")!
    removeCache = api.uid_get_from_cstr("key.removecache")!
    typeUsr = api.uid_get_from_cstr("key.typeusr")!
    containerTypeUsr = api.uid_get_from_cstr("key.containertypeusr")!
    moduleGroups = api.uid_get_from_cstr("key.modulegroups")!
    baseName = api.uid_get_from_cstr("key.basename")!
    argNames = api.uid_get_from_cstr("key.argnames")!
    selectorPieces = api.uid_get_from_cstr("key.selectorpieces")!
    nameKind = api.uid_get_from_cstr("key.namekind")!
    localizationKey = api.uid_get_from_cstr("key.localization_key")!
    isZeroArgSelector = api.uid_get_from_cstr("key.is_zero_arg_selector")!
    swiftVersion = api.uid_get_from_cstr("key.swift_version")!
    value = api.uid_get_from_cstr("key.value")!
    enableDiagnostics = api.uid_get_from_cstr("key.enablediagnostics")!
    groupName = api.uid_get_from_cstr("key.groupname")!
    actionName = api.uid_get_from_cstr("key.actionname")!
    synthesizedExtension = api.uid_get_from_cstr("key.synthesizedextensions")!
    usingSwiftArgs = api.uid_get_from_cstr("key.usingswiftargs")!
    names = api.uid_get_from_cstr("key.names")!
    uiDs = api.uid_get_from_cstr("key.uids")!
    syntacticOnly = api.uid_get_from_cstr("key.syntactic_only")!
    parentLoc = api.uid_get_from_cstr("key.parent_loc")!
    isTestCandidate = api.uid_get_from_cstr("key.is_test_candidate")!
    overrides = api.uid_get_from_cstr("key.overrides")!
    associatedUSRs = api.uid_get_from_cstr("key.associated_usrs")!
    moduleName = api.uid_get_from_cstr("key.modulename")!
    relatedDecls = api.uid_get_from_cstr("key.related_decls")!
    simplified = api.uid_get_from_cstr("key.simplified")!
    rangeContent = api.uid_get_from_cstr("key.rangecontent")!
    cancelOnSubsequentRequest = api.uid_get_from_cstr("key.cancel_on_subsequent_request")!
    includeNonEditableBaseNames = api.uid_get_from_cstr("key.include_non_editable_base_names")!
    renameLocations = api.uid_get_from_cstr("key.renamelocations")!
    locations = api.uid_get_from_cstr("key.locations")!
    nameType = api.uid_get_from_cstr("key.nametype")!
    newName = api.uid_get_from_cstr("key.newname")!
    categorizedEdits = api.uid_get_from_cstr("key.categorizededits")!
    categorizedRanges = api.uid_get_from_cstr("key.categorizedranges")!
    rangesWorthNote = api.uid_get_from_cstr("key.rangesworthnote")!
    edits = api.uid_get_from_cstr("key.edits")!
    endLine = api.uid_get_from_cstr("key.endline")!
    endColumn = api.uid_get_from_cstr("key.endcolumn")!
    argIndex = api.uid_get_from_cstr("key.argindex")!
    text = api.uid_get_from_cstr("key.text")!
    category = api.uid_get_from_cstr("key.category")!
    categories = api.uid_get_from_cstr("key.categories")!
    isFunctionLike = api.uid_get_from_cstr("key.is_function_like")!
    isNonProtocolType = api.uid_get_from_cstr("key.is_non_protocol_type")!
    refactorActions = api.uid_get_from_cstr("key.refactor_actions")!
    retrieveRefactorActions = api.uid_get_from_cstr("key.retrieve_refactor_actions")!
    symbolGraph = api.uid_get_from_cstr("key.symbol_graph")!
    retrieveSymbolGraph = api.uid_get_from_cstr("key.retrieve_symbol_graph")!
    parentContexts = api.uid_get_from_cstr("key.parent_contexts")!
    referencedSymbols = api.uid_get_from_cstr("key.referenced_symbols")!
    isSPI = api.uid_get_from_cstr("key.is_spi")!
    actionUID = api.uid_get_from_cstr("key.actionuid")!
    actionUnavailableReason = api.uid_get_from_cstr("key.actionunavailablereason")!
    compileID = api.uid_get_from_cstr("key.compileid")!
    compilerArgsString = api.uid_get_from_cstr("key.compilerargs-string")!
    implicitMembers = api.uid_get_from_cstr("key.implicitmembers")!
    expectedTypes = api.uid_get_from_cstr("key.expectedtypes")!
    members = api.uid_get_from_cstr("key.members")!
    typeBuffer = api.uid_get_from_cstr("key.printedtypebuffer")!
    expressionTypeList = api.uid_get_from_cstr("key.expression_type_list")!
    expressionOffset = api.uid_get_from_cstr("key.expression_offset")!
    expressionLength = api.uid_get_from_cstr("key.expression_length")!
    expressionType = api.uid_get_from_cstr("key.expression_type")!
    variableTypeList = api.uid_get_from_cstr("key.variable_type_list")!
    variableOffset = api.uid_get_from_cstr("key.variable_offset")!
    variableLength = api.uid_get_from_cstr("key.variable_length")!
    variableType = api.uid_get_from_cstr("key.variable_type")!
    variableTypeExplicit = api.uid_get_from_cstr("key.variable_type_explicit")!
    fullyQualified = api.uid_get_from_cstr("key.fully_qualified")!
    canonicalizeType = api.uid_get_from_cstr("key.canonicalize_type")!
    internalDiagnostic = api.uid_get_from_cstr("key.internal_diagnostic")!
    vfsName = api.uid_get_from_cstr("key.vfs.name")!
    vfsOptions = api.uid_get_from_cstr("key.vfs.options")!
    files = api.uid_get_from_cstr("key.files")!
    optimizeForIDE = api.uid_get_from_cstr("key.optimize_for_ide")!
    requiredBystanders = api.uid_get_from_cstr("key.required_bystanders")!
    reusingASTContext = api.uid_get_from_cstr("key.reusingastcontext")!
    completionMaxASTContextReuseCount = api.uid_get_from_cstr("key.completion_max_astcontext_reuse_count")!
    completionCheckDependencyInterval = api.uid_get_from_cstr("key.completion_check_dependency_interval")!
    annotatedTypename = api.uid_get_from_cstr("key.annotated.typename")!
    compileOperation = api.uid_get_from_cstr("key.compile_operation")!
    effectiveAccess = api.uid_get_from_cstr("key.effective_access")!
    declarationLang = api.uid_get_from_cstr("key.decl_lang")!
    secondarySymbols = api.uid_get_from_cstr("key.secondary_symbols")!
    simulateLongRequest = api.uid_get_from_cstr("key.simulate_long_request")!
    isSynthesized = api.uid_get_from_cstr("key.is_synthesized")!
    bufferName = api.uid_get_from_cstr("key.buffer_name")!
    barriersEnabled = api.uid_get_from_cstr("key.barriers_enabled")!
    expansions = api.uid_get_from_cstr("key.expansions")!
    macroRoles = api.uid_get_from_cstr("key.macro_roles")!
    expandedMacroReplacements = api.uid_get_from_cstr("key.expanded_macro_replacements")!
    indexStorePath = api.uid_get_from_cstr("key.index_store_path")!
    indexUnitOutputPath = api.uid_get_from_cstr("key.index_unit_output_path")!
    includeLocals = api.uid_get_from_cstr("key.include_locals")!
    compress = api.uid_get_from_cstr("key.compress")!
    ignoreClangModules = api.uid_get_from_cstr("key.ignore_clang_modules")!
    includeSystemModules = api.uid_get_from_cstr("key.include_system_modules")!
    ignoreStdlib = api.uid_get_from_cstr("key.ignore_stdlib")!
    disableImplicitModules = api.uid_get_from_cstr("key.disable_implicit_modules")!
    compilerArgs = api.uid_get_from_cstr("key.compilerargs")!
    sourceText = api.uid_get_from_cstr("key.sourcetext")!
    sortByName = api.uid_get_from_cstr("key.codecomplete.sort.byname")!
    useImportDepth = api.uid_get_from_cstr("key.codecomplete.sort.useimportdepth")!
    groupOverloads = api.uid_get_from_cstr("key.codecomplete.group.overloads")!
    groupStems = api.uid_get_from_cstr("key.codecomplete.group.stems")!
    filterText = api.uid_get_from_cstr("key.codecomplete.filtertext")!
    requestLimit = api.uid_get_from_cstr("key.codecomplete.requestlimit")!
    requestStart = api.uid_get_from_cstr("key.codecomplete.requeststart")!
    hideUnderscores = api.uid_get_from_cstr("key.codecomplete.hideunderscores")!
    hideLowPriority = api.uid_get_from_cstr("key.codecomplete.hidelowpriority")!
    hideByName = api.uid_get_from_cstr("key.codecomplete.hidebyname")!
    includeExactMatch = api.uid_get_from_cstr("key.codecomplete.includeexactmatch")!
    addInnerResults = api.uid_get_from_cstr("key.codecomplete.addinnerresults")!
    addInnerOperators = api.uid_get_from_cstr("key.codecomplete.addinneroperators")!
    addInitsToTopLevel = api.uid_get_from_cstr("key.codecomplete.addinitstotoplevel")!
    fuzzyMatching = api.uid_get_from_cstr("key.codecomplete.fuzzymatching")!
    topNonLiteral = api.uid_get_from_cstr("key.codecomplete.showtopnonliteralresults")!
    contextWeight = api.uid_get_from_cstr("key.codecomplete.sort.contextweight")!
    fuzzyWeight = api.uid_get_from_cstr("key.codecomplete.sort.fuzzyweight")!
    popularityBonus = api.uid_get_from_cstr("key.codecomplete.sort.popularitybonus")!
    annotatedDescription = api.uid_get_from_cstr("key.codecomplete.annotateddescription")!
    includeObjectLiterals = api.uid_get_from_cstr("key.codecomplete.includeobjectliterals")!
    useNewAPI = api.uid_get_from_cstr("key.codecomplete.use_new_api")!
    addCallWithNoDefaultArgs = api.uid_get_from_cstr("key.codecomplete.addcallwithnodefaultargs")!
    includeSemanticComponents = api.uid_get_from_cstr("key.codecomplete.include_semantic_components")!
    useXPCSerialization = api.uid_get_from_cstr("key.codecomplete.use_xpc_serialization")!
    maxResults = api.uid_get_from_cstr("key.codecomplete.maxresults")!
    annotatedTypeName = api.uid_get_from_cstr("key.annotated.typename")!
    priorityBucket = api.uid_get_from_cstr("key.priority_bucket")!
    identifier = api.uid_get_from_cstr("key.identifier")!
    textMatchScore = api.uid_get_from_cstr("key.text_match_score")!
    semanticScore = api.uid_get_from_cstr("key.semantic_score")!
    semanticScoreComponents = api.uid_get_from_cstr("key.semantic_score_components")!
    symbolPopularity = api.uid_get_from_cstr("key.symbol_popularity")!
    modulePopularity = api.uid_get_from_cstr("key.module_popularity")!
    popularityKey = api.uid_get_from_cstr("key.popularity.key")!
    popularityValueIntBillion = api.uid_get_from_cstr("key.popularity.value.int.billion")!
    recentCompletions = api.uid_get_from_cstr("key.recent_completions")!
    unfilteredResultCount = api.uid_get_from_cstr("key.unfiltered_result_count")!
    memberAccessTypes = api.uid_get_from_cstr("key.member_access_types")!
    hasDiagnostic = api.uid_get_from_cstr("key.has_diagnostic")!
    groupId = api.uid_get_from_cstr("key.group_id")!
    scopedPopularityTablePath = api.uid_get_from_cstr("key.scoped_popularity_table_path")!
    popularModules = api.uid_get_from_cstr("key.popular_modules")!
    notoriousModules = api.uid_get_from_cstr("key.notorious_modules")!
    usedScoreComponents = api.uid_get_from_cstr("key.codecomplete.setpopularapi_used_score_components")!
    useTabs = api.uid_get_from_cstr("key.editor.format.usetabs")!
    indentWidth = api.uid_get_from_cstr("key.editor.format.indentwidth")!
    tabWidth = api.uid_get_from_cstr("key.editor.format.tabwidth")!
    indentSwitchCase = api.uid_get_from_cstr("key.editor.format.indent_switch_case")!
  }
}

// swift-format-ignore: TypeNamesShouldBeCapitalized
// Matching C style types
package struct sourcekitd_api_requests {
  /// `source.request.protocol_version`
  package let protocolVersion: sourcekitd_api_uid_t
  /// `source.request.compiler_version`
  package let compilerVersion: sourcekitd_api_uid_t
  /// `source.request.crash_exit`
  package let crashWithExit: sourcekitd_api_uid_t
  /// `source.request.demangle`
  package let demangle: sourcekitd_api_uid_t
  /// `source.request.mangle_simple_class`
  package let mangleSimpleClass: sourcekitd_api_uid_t
  /// `source.request.indexsource`
  package let index: sourcekitd_api_uid_t
  /// `source.request.docinfo`
  package let docInfo: sourcekitd_api_uid_t
  /// `source.request.codecomplete`
  package let codeComplete: sourcekitd_api_uid_t
  /// `source.request.codecomplete.open`
  package let codeCompleteOpen: sourcekitd_api_uid_t
  /// `source.request.codecomplete.close`
  package let codeCompleteClose: sourcekitd_api_uid_t
  /// `source.request.codecomplete.update`
  package let codeCompleteUpdate: sourcekitd_api_uid_t
  /// `source.request.codecomplete.cache.ondisk`
  package let codeCompleteCacheOnDisk: sourcekitd_api_uid_t
  /// `source.request.codecomplete.setpopularapi`
  package let codeCompleteSetPopularAPI: sourcekitd_api_uid_t
  /// `source.request.codecomplete.setcustom`
  package let codeCompleteSetCustom: sourcekitd_api_uid_t
  /// `source.request.signaturehelp`
  package let signatureHelp: sourcekitd_api_uid_t
  /// `source.request.typecontextinfo`
  package let typeContextInfo: sourcekitd_api_uid_t
  /// `source.request.conformingmethods`
  package let conformingMethodList: sourcekitd_api_uid_t
  /// `source.request.activeregions`
  package let activeRegions: sourcekitd_api_uid_t
  /// `source.request.cursorinfo`
  package let cursorInfo: sourcekitd_api_uid_t
  /// `source.request.rangeinfo`
  package let rangeInfo: sourcekitd_api_uid_t
  /// `source.request.relatedidents`
  package let relatedIdents: sourcekitd_api_uid_t
  /// `source.request.editor.open`
  package let editorOpen: sourcekitd_api_uid_t
  /// `source.request.editor.open.interface`
  package let editorOpenInterface: sourcekitd_api_uid_t
  /// `source.request.editor.open.interface.header`
  package let editorOpenHeaderInterface: sourcekitd_api_uid_t
  /// `source.request.editor.open.interface.swiftsource`
  package let editorOpenSwiftSourceInterface: sourcekitd_api_uid_t
  /// `source.request.editor.open.interface.swifttype`
  package let editorOpenSwiftTypeInterface: sourcekitd_api_uid_t
  /// `source.request.editor.extract.comment`
  package let editorExtractTextFromComment: sourcekitd_api_uid_t
  /// `source.request.editor.close`
  package let editorClose: sourcekitd_api_uid_t
  /// `source.request.editor.replacetext`
  package let editorReplaceText: sourcekitd_api_uid_t
  /// `source.request.editor.formattext`
  package let editorFormatText: sourcekitd_api_uid_t
  /// `source.request.editor.expand_placeholder`
  package let editorExpandPlaceholder: sourcekitd_api_uid_t
  /// `source.request.editor.find_usr`
  package let editorFindUSR: sourcekitd_api_uid_t
  /// `source.request.editor.find_interface_doc`
  package let editorFindInterfaceDoc: sourcekitd_api_uid_t
  /// `source.request.buildsettings.register`
  package let buildSettingsRegister: sourcekitd_api_uid_t
  /// `source.request.module.groups`
  package let moduleGroups: sourcekitd_api_uid_t
  /// `source.request.name.translation`
  package let nameTranslation: sourcekitd_api_uid_t
  /// `source.request.convert.markup.xml`
  package let markupToXML: sourcekitd_api_uid_t
  /// `source.request.statistics`
  package let statistics: sourcekitd_api_uid_t
  /// `source.request.find-syntactic-rename-ranges`
  package let findRenameRanges: sourcekitd_api_uid_t
  /// `source.request.find-local-rename-ranges`
  package let findLocalRenameRanges: sourcekitd_api_uid_t
  /// `source.request.semantic.refactoring`
  package let semanticRefactoring: sourcekitd_api_uid_t
  /// `source.request.enable-compile-notifications`
  package let enableCompileNotifications: sourcekitd_api_uid_t
  /// `source.request.test_notification`
  package let testNotification: sourcekitd_api_uid_t
  /// `source.request.expression.type`
  package let collectExpressionType: sourcekitd_api_uid_t
  /// `source.request.variable.type`
  package let collectVariableType: sourcekitd_api_uid_t
  /// `source.request.configuration.global`
  package let globalConfiguration: sourcekitd_api_uid_t
  /// `source.request.dependency_updated`
  package let dependencyUpdated: sourcekitd_api_uid_t
  /// `source.request.diagnostics`
  package let diagnostics: sourcekitd_api_uid_t
  /// `source.request.semantic_tokens`
  package let semanticTokens: sourcekitd_api_uid_t
  /// `source.request.compile`
  package let compile: sourcekitd_api_uid_t
  /// `source.request.compile.close`
  package let compileClose: sourcekitd_api_uid_t
  /// `source.request.enable_request_barriers`
  package let enableRequestBarriers: sourcekitd_api_uid_t
  /// `source.request.syntactic_macro_expansion`
  package let syntacticMacroExpansion: sourcekitd_api_uid_t
  /// `source.request.index_to_store`
  package let indexToStore: sourcekitd_api_uid_t
  /// `source.request.codecomplete.documentation`
  package let codeCompleteDocumentation: sourcekitd_api_uid_t
  /// `source.request.codecomplete.diagnostic`
  package let codeCompleteDiagnostic: sourcekitd_api_uid_t

  package init(api: sourcekitd_api_functions_t) {
    protocolVersion = api.uid_get_from_cstr("source.request.protocol_version")!
    compilerVersion = api.uid_get_from_cstr("source.request.compiler_version")!
    crashWithExit = api.uid_get_from_cstr("source.request.crash_exit")!
    demangle = api.uid_get_from_cstr("source.request.demangle")!
    mangleSimpleClass = api.uid_get_from_cstr("source.request.mangle_simple_class")!
    index = api.uid_get_from_cstr("source.request.indexsource")!
    docInfo = api.uid_get_from_cstr("source.request.docinfo")!
    codeComplete = api.uid_get_from_cstr("source.request.codecomplete")!
    codeCompleteOpen = api.uid_get_from_cstr("source.request.codecomplete.open")!
    codeCompleteClose = api.uid_get_from_cstr("source.request.codecomplete.close")!
    codeCompleteUpdate = api.uid_get_from_cstr("source.request.codecomplete.update")!
    codeCompleteCacheOnDisk = api.uid_get_from_cstr("source.request.codecomplete.cache.ondisk")!
    codeCompleteSetPopularAPI = api.uid_get_from_cstr("source.request.codecomplete.setpopularapi")!
    codeCompleteSetCustom = api.uid_get_from_cstr("source.request.codecomplete.setcustom")!
    signatureHelp = api.uid_get_from_cstr("source.request.signaturehelp")!
    typeContextInfo = api.uid_get_from_cstr("source.request.typecontextinfo")!
    conformingMethodList = api.uid_get_from_cstr("source.request.conformingmethods")!
    activeRegions = api.uid_get_from_cstr("source.request.activeregions")!
    cursorInfo = api.uid_get_from_cstr("source.request.cursorinfo")!
    rangeInfo = api.uid_get_from_cstr("source.request.rangeinfo")!
    relatedIdents = api.uid_get_from_cstr("source.request.relatedidents")!
    editorOpen = api.uid_get_from_cstr("source.request.editor.open")!
    editorOpenInterface = api.uid_get_from_cstr("source.request.editor.open.interface")!
    editorOpenHeaderInterface = api.uid_get_from_cstr("source.request.editor.open.interface.header")!
    editorOpenSwiftSourceInterface = api.uid_get_from_cstr("source.request.editor.open.interface.swiftsource")!
    editorOpenSwiftTypeInterface = api.uid_get_from_cstr("source.request.editor.open.interface.swifttype")!
    editorExtractTextFromComment = api.uid_get_from_cstr("source.request.editor.extract.comment")!
    editorClose = api.uid_get_from_cstr("source.request.editor.close")!
    editorReplaceText = api.uid_get_from_cstr("source.request.editor.replacetext")!
    editorFormatText = api.uid_get_from_cstr("source.request.editor.formattext")!
    editorExpandPlaceholder = api.uid_get_from_cstr("source.request.editor.expand_placeholder")!
    editorFindUSR = api.uid_get_from_cstr("source.request.editor.find_usr")!
    editorFindInterfaceDoc = api.uid_get_from_cstr("source.request.editor.find_interface_doc")!
    buildSettingsRegister = api.uid_get_from_cstr("source.request.buildsettings.register")!
    moduleGroups = api.uid_get_from_cstr("source.request.module.groups")!
    nameTranslation = api.uid_get_from_cstr("source.request.name.translation")!
    markupToXML = api.uid_get_from_cstr("source.request.convert.markup.xml")!
    statistics = api.uid_get_from_cstr("source.request.statistics")!
    findRenameRanges = api.uid_get_from_cstr("source.request.find-syntactic-rename-ranges")!
    findLocalRenameRanges = api.uid_get_from_cstr("source.request.find-local-rename-ranges")!
    semanticRefactoring = api.uid_get_from_cstr("source.request.semantic.refactoring")!
    enableCompileNotifications = api.uid_get_from_cstr("source.request.enable-compile-notifications")!
    testNotification = api.uid_get_from_cstr("source.request.test_notification")!
    collectExpressionType = api.uid_get_from_cstr("source.request.expression.type")!
    collectVariableType = api.uid_get_from_cstr("source.request.variable.type")!
    globalConfiguration = api.uid_get_from_cstr("source.request.configuration.global")!
    dependencyUpdated = api.uid_get_from_cstr("source.request.dependency_updated")!
    diagnostics = api.uid_get_from_cstr("source.request.diagnostics")!
    semanticTokens = api.uid_get_from_cstr("source.request.semantic_tokens")!
    compile = api.uid_get_from_cstr("source.request.compile")!
    compileClose = api.uid_get_from_cstr("source.request.compile.close")!
    enableRequestBarriers = api.uid_get_from_cstr("source.request.enable_request_barriers")!
    syntacticMacroExpansion = api.uid_get_from_cstr("source.request.syntactic_macro_expansion")!
    indexToStore = api.uid_get_from_cstr("source.request.index_to_store")!
    codeCompleteDocumentation = api.uid_get_from_cstr("source.request.codecomplete.documentation")!
    codeCompleteDiagnostic = api.uid_get_from_cstr("source.request.codecomplete.diagnostic")!
  }
}

// swift-format-ignore: TypeNamesShouldBeCapitalized
// Matching C style types
package struct sourcekitd_api_values {
  /// `source.lang.swift.decl.function.free`
  package let declFunctionFree: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.free`
  package let refFunctionFree: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.method.instance`
  package let declMethodInstance: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.method.instance`
  package let refMethodInstance: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.method.static`
  package let declMethodStatic: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.method.static`
  package let refMethodStatic: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.method.class`
  package let declMethodClass: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.method.class`
  package let refMethodClass: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.getter`
  package let declAccessorGetter: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.getter`
  package let refAccessorGetter: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.setter`
  package let declAccessorSetter: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.setter`
  package let refAccessorSetter: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.willset`
  package let declAccessorWillSet: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.willset`
  package let refAccessorWillSet: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.didset`
  package let declAccessorDidSet: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.didset`
  package let refAccessorDidSet: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.address`
  package let declAccessorAddress: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.address`
  package let refAccessorAddress: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.mutableaddress`
  package let declAccessorMutableAddress: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.mutableaddress`
  package let refAccessorMutableAddress: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.read`
  package let declAccessorRead: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.read`
  package let refAccessorRead: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.modify`
  package let declAccessorModify: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.modify`
  package let refAccessorModify: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.init`
  package let declAccessorInit: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.init`
  package let refAccessorInit: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.mutate`
  package let declAccessorMutate: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.mutate`
  package let refAccessorMutate: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.accessor.borrow`
  package let declAccessorBorrow: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.accessor.borrow`
  package let refAccessorBorrow: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.constructor`
  package let declConstructor: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.constructor`
  package let refConstructor: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.destructor`
  package let declDestructor: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.destructor`
  package let refDestructor: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.operator.prefix`
  package let declFunctionPrefixOperator: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.operator.postfix`
  package let declFunctionPostfixOperator: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.operator.infix`
  package let declFunctionInfixOperator: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.operator.prefix`
  package let refFunctionPrefixOperator: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.operator.postfix`
  package let refFunctionPostfixOperator: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.operator.infix`
  package let refFunctionInfixOperator: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.precedencegroup`
  package let declPrecedenceGroup: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.precedencegroup`
  package let refPrecedenceGroup: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.function.subscript`
  package let declSubscript: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.function.subscript`
  package let refSubscript: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.var.global`
  package let declVarGlobal: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.var.global`
  package let refVarGlobal: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.var.instance`
  package let declVarInstance: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.var.instance`
  package let refVarInstance: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.var.static`
  package let declVarStatic: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.var.static`
  package let refVarStatic: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.var.class`
  package let declVarClass: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.var.class`
  package let refVarClass: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.var.local`
  package let declVarLocal: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.var.local`
  package let refVarLocal: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.var.parameter`
  package let declVarParam: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.module`
  package let declModule: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.class`
  package let declClass: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.class`
  package let refClass: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.actor`
  package let declActor: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.actor`
  package let refActor: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.struct`
  package let declStruct: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.struct`
  package let refStruct: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.enum`
  package let declEnum: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.enum`
  package let refEnum: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.enumcase`
  package let declEnumCase: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.enumelement`
  package let declEnumElement: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.enumelement`
  package let refEnumElement: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.protocol`
  package let declProtocol: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.protocol`
  package let refProtocol: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.extension`
  package let declExtension: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.extension.struct`
  package let declExtensionStruct: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.extension.class`
  package let declExtensionClass: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.extension.enum`
  package let declExtensionEnum: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.extension.protocol`
  package let declExtensionProtocol: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.associatedtype`
  package let declAssociatedType: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.associatedtype`
  package let refAssociatedType: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.opaquetype`
  package let declOpaqueType: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.opaquetype`
  package let refOpaqueType: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.typealias`
  package let declTypeAlias: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.typealias`
  package let refTypeAlias: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.generic_type_param`
  package let declGenericTypeParam: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.generic_type_param`
  package let refGenericTypeParam: sourcekitd_api_uid_t
  /// `source.lang.swift.decl.macro`
  package let declMacro: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.macro`
  package let refMacro: sourcekitd_api_uid_t
  /// `source.lang.swift.ref.module`
  package let refModule: sourcekitd_api_uid_t
  /// `source.lang.swift.commenttag`
  package let commentTag: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.foreach`
  package let stmtForEach: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.for`
  package let stmtFor: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.while`
  package let stmtWhile: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.repeatwhile`
  package let stmtRepeatWhile: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.if`
  package let stmtIf: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.guard`
  package let stmtGuard: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.switch`
  package let stmtSwitch: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.case`
  package let stmtCase: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt.brace`
  package let stmtBrace: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.call`
  package let exprCall: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.argument`
  package let exprArg: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.array`
  package let exprArray: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.dictionary`
  package let exprDictionary: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.object_literal`
  package let exprObjectLiteral: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.tuple`
  package let exprTuple: sourcekitd_api_uid_t
  /// `source.lang.swift.expr.closure`
  package let exprClosure: sourcekitd_api_uid_t
  /// `source.lang.swift.structure.elem.id`
  package let structureElemId: sourcekitd_api_uid_t
  /// `source.lang.swift.structure.elem.expr`
  package let structureElemExpr: sourcekitd_api_uid_t
  /// `source.lang.swift.structure.elem.init_expr`
  package let structureElemInitExpr: sourcekitd_api_uid_t
  /// `source.lang.swift.structure.elem.condition_expr`
  package let structureElemCondExpr: sourcekitd_api_uid_t
  /// `source.lang.swift.structure.elem.pattern`
  package let structureElemPattern: sourcekitd_api_uid_t
  /// `source.lang.swift.structure.elem.typeref`
  package let structureElemTypeRef: sourcekitd_api_uid_t
  /// `source.lang.swift.range.singlestatement`
  package let rangeSingleStatement: sourcekitd_api_uid_t
  /// `source.lang.swift.range.singleexpression`
  package let rangeSingleExpression: sourcekitd_api_uid_t
  /// `source.lang.swift.range.singledeclaration`
  package let rangeSingleDeclaration: sourcekitd_api_uid_t
  /// `source.lang.swift.range.multistatement`
  package let rangeMultiStatement: sourcekitd_api_uid_t
  /// `source.lang.swift.range.multitypememberdeclaration`
  package let rangeMultiTypeMemberDeclaration: sourcekitd_api_uid_t
  /// `source.lang.swift.range.invalid`
  package let rangeInvalid: sourcekitd_api_uid_t
  /// `source.lang.name.kind.objc`
  package let nameObjc: sourcekitd_api_uid_t
  /// `source.lang.name.kind.swift`
  package let nameSwift: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.keyword`
  package let keyword: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.identifier`
  package let identifier: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.operator`
  package let `operator`: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.typeidentifier`
  package let typeIdentifier: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.buildconfig.keyword`
  package let buildConfigKeyword: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.buildconfig.id`
  package let buildConfigId: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.pounddirective.keyword`
  package let poundDirectiveKeyword: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.attribute.id`
  package let attributeId: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.attribute.builtin`
  package let attributeBuiltin: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.number`
  package let number: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.string`
  package let string: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.string_interpolation_anchor`
  package let stringInterpolation: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.comment`
  package let comment: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.doccomment`
  package let docComment: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.doccomment.field`
  package let docCommentField: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.comment.mark`
  package let commentMarker: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.comment.url`
  package let commentURL: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.placeholder`
  package let placeholder: sourcekitd_api_uid_t
  /// `source.lang.swift.syntaxtype.objectliteral`
  package let objectLiteral: sourcekitd_api_uid_t
  /// `source.lang.swift.expr`
  package let expr: sourcekitd_api_uid_t
  /// `source.lang.swift.stmt`
  package let stmt: sourcekitd_api_uid_t
  /// `source.lang.swift.type`
  package let type: sourcekitd_api_uid_t
  /// `source.lang.swift.foreach.sequence`
  package let forEachSequence: sourcekitd_api_uid_t
  /// `source.diagnostic.severity.note`
  package let diagNote: sourcekitd_api_uid_t
  /// `source.diagnostic.severity.warning`
  package let diagWarning: sourcekitd_api_uid_t
  /// `source.diagnostic.severity.error`
  package let diagError: sourcekitd_api_uid_t
  /// `source.diagnostic.severity.remark`
  package let diagRemark: sourcekitd_api_uid_t
  /// `source.diagnostic.category.deprecation`
  package let diagDeprecation: sourcekitd_api_uid_t
  /// `source.diagnostic.category.no_usage`
  package let diagNoUsage: sourcekitd_api_uid_t
  /// `source.codecompletion.everything`
  package let codeCompletionEverything: sourcekitd_api_uid_t
  /// `source.codecompletion.module`
  package let codeCompletionModule: sourcekitd_api_uid_t
  /// `source.codecompletion.keyword`
  package let codeCompletionKeyword: sourcekitd_api_uid_t
  /// `source.codecompletion.literal`
  package let codeCompletionLiteral: sourcekitd_api_uid_t
  /// `source.codecompletion.custom`
  package let codeCompletionCustom: sourcekitd_api_uid_t
  /// `source.codecompletion.identifier`
  package let codeCompletionIdentifier: sourcekitd_api_uid_t
  /// `source.codecompletion.description`
  package let codeCompletionDescription: sourcekitd_api_uid_t
  /// `source.edit.kind.active`
  package let editActive: sourcekitd_api_uid_t
  /// `source.edit.kind.inactive`
  package let editInactive: sourcekitd_api_uid_t
  /// `source.edit.kind.selector`
  package let editSelector: sourcekitd_api_uid_t
  /// `source.edit.kind.string`
  package let editString: sourcekitd_api_uid_t
  /// `source.edit.kind.comment`
  package let editComment: sourcekitd_api_uid_t
  /// `source.edit.kind.mismatch`
  package let editMismatch: sourcekitd_api_uid_t
  /// `source.edit.kind.unknown`
  package let editUnknown: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.basename`
  package let renameRangeBase: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.keyword-basename`
  package let renameRangeKeywordBase: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.parameter-and-whitespace`
  package let renameRangeParam: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.noncollapsible-parameter`
  package let renameRangeNoncollapsibleParam: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.decl-argument-label`
  package let renameRangeDeclArgLabel: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.call-argument-label`
  package let renameRangeCallArgLabel: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.call-argument-colon`
  package let renameRangeCallArgColon: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.call-argument-combined`
  package let renameRangeCallArgCombined: sourcekitd_api_uid_t
  /// `source.refactoring.range.kind.selector-argument-label`
  package let renameRangeSelectorArgLabel: sourcekitd_api_uid_t
  /// `source.syntacticrename.definition`
  package let definition: sourcekitd_api_uid_t
  /// `source.syntacticrename.reference`
  package let reference: sourcekitd_api_uid_t
  /// `source.syntacticrename.call`
  package let call: sourcekitd_api_uid_t
  /// `source.syntacticrename.unknown`
  package let unknown: sourcekitd_api_uid_t
  /// `source.statistic.num-requests`
  package let statNumRequests: sourcekitd_api_uid_t
  /// `source.statistic.num-semantic-requests`
  package let statNumSemaRequests: sourcekitd_api_uid_t
  /// `source.statistic.instruction-count`
  package let statInstructionCount: sourcekitd_api_uid_t
  /// `source.lang.swift`
  package let swift: sourcekitd_api_uid_t
  /// `source.lang.objc`
  package let objC: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.expression`
  package let macroRoleExpression: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.declaration`
  package let macroRoleDeclaration: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.codeitem`
  package let macroRoleCodeItem: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.accessor`
  package let macroRoleAccessor: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.member_attribute`
  package let macroRoleMemberAttribute: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.member`
  package let macroRoleMember: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.peer`
  package let macroRolePeer: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.conformance`
  package let macroRoleConformance: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.extension`
  package let macroRoleExtension: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.preamble`
  package let macroRolePreamble: sourcekitd_api_uid_t
  /// `source.lang.swift.macro_role.body`
  package let macroRoleBody: sourcekitd_api_uid_t
  /// `source.lang.swift.keyword`
  package let completionKindKeyword: sourcekitd_api_uid_t
  /// `source.lang.swift.pattern`
  package let completionKindPattern: sourcekitd_api_uid_t
  /// `source.diagnostic.stage.swift.sema`
  package let semaDiagStage: sourcekitd_api_uid_t
  /// `source.diagnostic.stage.swift.parse`
  package let parseDiagStage: sourcekitd_api_uid_t
  /// `source.notification.sema_disabled`
  package let semaDisabledNotification: sourcekitd_api_uid_t
  /// `source.notification.sema_enabled`
  package let semaEnabledNotification: sourcekitd_api_uid_t
  /// `source.notification.editor.documentupdate`
  package let documentUpdateNotification: sourcekitd_api_uid_t

  package init(api: sourcekitd_api_functions_t) {
    declFunctionFree = api.uid_get_from_cstr("source.lang.swift.decl.function.free")!
    refFunctionFree = api.uid_get_from_cstr("source.lang.swift.ref.function.free")!
    declMethodInstance = api.uid_get_from_cstr("source.lang.swift.decl.function.method.instance")!
    refMethodInstance = api.uid_get_from_cstr("source.lang.swift.ref.function.method.instance")!
    declMethodStatic = api.uid_get_from_cstr("source.lang.swift.decl.function.method.static")!
    refMethodStatic = api.uid_get_from_cstr("source.lang.swift.ref.function.method.static")!
    declMethodClass = api.uid_get_from_cstr("source.lang.swift.decl.function.method.class")!
    refMethodClass = api.uid_get_from_cstr("source.lang.swift.ref.function.method.class")!
    declAccessorGetter = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.getter")!
    refAccessorGetter = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.getter")!
    declAccessorSetter = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.setter")!
    refAccessorSetter = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.setter")!
    declAccessorWillSet = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.willset")!
    refAccessorWillSet = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.willset")!
    declAccessorDidSet = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.didset")!
    refAccessorDidSet = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.didset")!
    declAccessorAddress = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.address")!
    refAccessorAddress = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.address")!
    declAccessorMutableAddress = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.mutableaddress")!
    refAccessorMutableAddress = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.mutableaddress")!
    declAccessorRead = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.read")!
    refAccessorRead = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.read")!
    declAccessorModify = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.modify")!
    refAccessorModify = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.modify")!
    declAccessorInit = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.init")!
    refAccessorInit = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.init")!
    declAccessorMutate = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.mutate")!
    refAccessorMutate = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.mutate")!
    declAccessorBorrow = api.uid_get_from_cstr("source.lang.swift.decl.function.accessor.borrow")!
    refAccessorBorrow = api.uid_get_from_cstr("source.lang.swift.ref.function.accessor.borrow")!
    declConstructor = api.uid_get_from_cstr("source.lang.swift.decl.function.constructor")!
    refConstructor = api.uid_get_from_cstr("source.lang.swift.ref.function.constructor")!
    declDestructor = api.uid_get_from_cstr("source.lang.swift.decl.function.destructor")!
    refDestructor = api.uid_get_from_cstr("source.lang.swift.ref.function.destructor")!
    declFunctionPrefixOperator = api.uid_get_from_cstr("source.lang.swift.decl.function.operator.prefix")!
    declFunctionPostfixOperator = api.uid_get_from_cstr("source.lang.swift.decl.function.operator.postfix")!
    declFunctionInfixOperator = api.uid_get_from_cstr("source.lang.swift.decl.function.operator.infix")!
    refFunctionPrefixOperator = api.uid_get_from_cstr("source.lang.swift.ref.function.operator.prefix")!
    refFunctionPostfixOperator = api.uid_get_from_cstr("source.lang.swift.ref.function.operator.postfix")!
    refFunctionInfixOperator = api.uid_get_from_cstr("source.lang.swift.ref.function.operator.infix")!
    declPrecedenceGroup = api.uid_get_from_cstr("source.lang.swift.decl.precedencegroup")!
    refPrecedenceGroup = api.uid_get_from_cstr("source.lang.swift.ref.precedencegroup")!
    declSubscript = api.uid_get_from_cstr("source.lang.swift.decl.function.subscript")!
    refSubscript = api.uid_get_from_cstr("source.lang.swift.ref.function.subscript")!
    declVarGlobal = api.uid_get_from_cstr("source.lang.swift.decl.var.global")!
    refVarGlobal = api.uid_get_from_cstr("source.lang.swift.ref.var.global")!
    declVarInstance = api.uid_get_from_cstr("source.lang.swift.decl.var.instance")!
    refVarInstance = api.uid_get_from_cstr("source.lang.swift.ref.var.instance")!
    declVarStatic = api.uid_get_from_cstr("source.lang.swift.decl.var.static")!
    refVarStatic = api.uid_get_from_cstr("source.lang.swift.ref.var.static")!
    declVarClass = api.uid_get_from_cstr("source.lang.swift.decl.var.class")!
    refVarClass = api.uid_get_from_cstr("source.lang.swift.ref.var.class")!
    declVarLocal = api.uid_get_from_cstr("source.lang.swift.decl.var.local")!
    refVarLocal = api.uid_get_from_cstr("source.lang.swift.ref.var.local")!
    declVarParam = api.uid_get_from_cstr("source.lang.swift.decl.var.parameter")!
    declModule = api.uid_get_from_cstr("source.lang.swift.decl.module")!
    declClass = api.uid_get_from_cstr("source.lang.swift.decl.class")!
    refClass = api.uid_get_from_cstr("source.lang.swift.ref.class")!
    declActor = api.uid_get_from_cstr("source.lang.swift.decl.actor")!
    refActor = api.uid_get_from_cstr("source.lang.swift.ref.actor")!
    declStruct = api.uid_get_from_cstr("source.lang.swift.decl.struct")!
    refStruct = api.uid_get_from_cstr("source.lang.swift.ref.struct")!
    declEnum = api.uid_get_from_cstr("source.lang.swift.decl.enum")!
    refEnum = api.uid_get_from_cstr("source.lang.swift.ref.enum")!
    declEnumCase = api.uid_get_from_cstr("source.lang.swift.decl.enumcase")!
    declEnumElement = api.uid_get_from_cstr("source.lang.swift.decl.enumelement")!
    refEnumElement = api.uid_get_from_cstr("source.lang.swift.ref.enumelement")!
    declProtocol = api.uid_get_from_cstr("source.lang.swift.decl.protocol")!
    refProtocol = api.uid_get_from_cstr("source.lang.swift.ref.protocol")!
    declExtension = api.uid_get_from_cstr("source.lang.swift.decl.extension")!
    declExtensionStruct = api.uid_get_from_cstr("source.lang.swift.decl.extension.struct")!
    declExtensionClass = api.uid_get_from_cstr("source.lang.swift.decl.extension.class")!
    declExtensionEnum = api.uid_get_from_cstr("source.lang.swift.decl.extension.enum")!
    declExtensionProtocol = api.uid_get_from_cstr("source.lang.swift.decl.extension.protocol")!
    declAssociatedType = api.uid_get_from_cstr("source.lang.swift.decl.associatedtype")!
    refAssociatedType = api.uid_get_from_cstr("source.lang.swift.ref.associatedtype")!
    declOpaqueType = api.uid_get_from_cstr("source.lang.swift.decl.opaquetype")!
    refOpaqueType = api.uid_get_from_cstr("source.lang.swift.ref.opaquetype")!
    declTypeAlias = api.uid_get_from_cstr("source.lang.swift.decl.typealias")!
    refTypeAlias = api.uid_get_from_cstr("source.lang.swift.ref.typealias")!
    declGenericTypeParam = api.uid_get_from_cstr("source.lang.swift.decl.generic_type_param")!
    refGenericTypeParam = api.uid_get_from_cstr("source.lang.swift.ref.generic_type_param")!
    declMacro = api.uid_get_from_cstr("source.lang.swift.decl.macro")!
    refMacro = api.uid_get_from_cstr("source.lang.swift.ref.macro")!
    refModule = api.uid_get_from_cstr("source.lang.swift.ref.module")!
    commentTag = api.uid_get_from_cstr("source.lang.swift.commenttag")!
    stmtForEach = api.uid_get_from_cstr("source.lang.swift.stmt.foreach")!
    stmtFor = api.uid_get_from_cstr("source.lang.swift.stmt.for")!
    stmtWhile = api.uid_get_from_cstr("source.lang.swift.stmt.while")!
    stmtRepeatWhile = api.uid_get_from_cstr("source.lang.swift.stmt.repeatwhile")!
    stmtIf = api.uid_get_from_cstr("source.lang.swift.stmt.if")!
    stmtGuard = api.uid_get_from_cstr("source.lang.swift.stmt.guard")!
    stmtSwitch = api.uid_get_from_cstr("source.lang.swift.stmt.switch")!
    stmtCase = api.uid_get_from_cstr("source.lang.swift.stmt.case")!
    stmtBrace = api.uid_get_from_cstr("source.lang.swift.stmt.brace")!
    exprCall = api.uid_get_from_cstr("source.lang.swift.expr.call")!
    exprArg = api.uid_get_from_cstr("source.lang.swift.expr.argument")!
    exprArray = api.uid_get_from_cstr("source.lang.swift.expr.array")!
    exprDictionary = api.uid_get_from_cstr("source.lang.swift.expr.dictionary")!
    exprObjectLiteral = api.uid_get_from_cstr("source.lang.swift.expr.object_literal")!
    exprTuple = api.uid_get_from_cstr("source.lang.swift.expr.tuple")!
    exprClosure = api.uid_get_from_cstr("source.lang.swift.expr.closure")!
    structureElemId = api.uid_get_from_cstr("source.lang.swift.structure.elem.id")!
    structureElemExpr = api.uid_get_from_cstr("source.lang.swift.structure.elem.expr")!
    structureElemInitExpr = api.uid_get_from_cstr("source.lang.swift.structure.elem.init_expr")!
    structureElemCondExpr = api.uid_get_from_cstr("source.lang.swift.structure.elem.condition_expr")!
    structureElemPattern = api.uid_get_from_cstr("source.lang.swift.structure.elem.pattern")!
    structureElemTypeRef = api.uid_get_from_cstr("source.lang.swift.structure.elem.typeref")!
    rangeSingleStatement = api.uid_get_from_cstr("source.lang.swift.range.singlestatement")!
    rangeSingleExpression = api.uid_get_from_cstr("source.lang.swift.range.singleexpression")!
    rangeSingleDeclaration = api.uid_get_from_cstr("source.lang.swift.range.singledeclaration")!
    rangeMultiStatement = api.uid_get_from_cstr("source.lang.swift.range.multistatement")!
    rangeMultiTypeMemberDeclaration = api.uid_get_from_cstr("source.lang.swift.range.multitypememberdeclaration")!
    rangeInvalid = api.uid_get_from_cstr("source.lang.swift.range.invalid")!
    nameObjc = api.uid_get_from_cstr("source.lang.name.kind.objc")!
    nameSwift = api.uid_get_from_cstr("source.lang.name.kind.swift")!
    keyword = api.uid_get_from_cstr("source.lang.swift.syntaxtype.keyword")!
    identifier = api.uid_get_from_cstr("source.lang.swift.syntaxtype.identifier")!
    `operator` = api.uid_get_from_cstr("source.lang.swift.syntaxtype.operator")!
    typeIdentifier = api.uid_get_from_cstr("source.lang.swift.syntaxtype.typeidentifier")!
    buildConfigKeyword = api.uid_get_from_cstr("source.lang.swift.syntaxtype.buildconfig.keyword")!
    buildConfigId = api.uid_get_from_cstr("source.lang.swift.syntaxtype.buildconfig.id")!
    poundDirectiveKeyword = api.uid_get_from_cstr("source.lang.swift.syntaxtype.pounddirective.keyword")!
    attributeId = api.uid_get_from_cstr("source.lang.swift.syntaxtype.attribute.id")!
    attributeBuiltin = api.uid_get_from_cstr("source.lang.swift.syntaxtype.attribute.builtin")!
    number = api.uid_get_from_cstr("source.lang.swift.syntaxtype.number")!
    string = api.uid_get_from_cstr("source.lang.swift.syntaxtype.string")!
    stringInterpolation = api.uid_get_from_cstr("source.lang.swift.syntaxtype.string_interpolation_anchor")!
    comment = api.uid_get_from_cstr("source.lang.swift.syntaxtype.comment")!
    docComment = api.uid_get_from_cstr("source.lang.swift.syntaxtype.doccomment")!
    docCommentField = api.uid_get_from_cstr("source.lang.swift.syntaxtype.doccomment.field")!
    commentMarker = api.uid_get_from_cstr("source.lang.swift.syntaxtype.comment.mark")!
    commentURL = api.uid_get_from_cstr("source.lang.swift.syntaxtype.comment.url")!
    placeholder = api.uid_get_from_cstr("source.lang.swift.syntaxtype.placeholder")!
    objectLiteral = api.uid_get_from_cstr("source.lang.swift.syntaxtype.objectliteral")!
    expr = api.uid_get_from_cstr("source.lang.swift.expr")!
    stmt = api.uid_get_from_cstr("source.lang.swift.stmt")!
    type = api.uid_get_from_cstr("source.lang.swift.type")!
    forEachSequence = api.uid_get_from_cstr("source.lang.swift.foreach.sequence")!
    diagNote = api.uid_get_from_cstr("source.diagnostic.severity.note")!
    diagWarning = api.uid_get_from_cstr("source.diagnostic.severity.warning")!
    diagError = api.uid_get_from_cstr("source.diagnostic.severity.error")!
    diagRemark = api.uid_get_from_cstr("source.diagnostic.severity.remark")!
    diagDeprecation = api.uid_get_from_cstr("source.diagnostic.category.deprecation")!
    diagNoUsage = api.uid_get_from_cstr("source.diagnostic.category.no_usage")!
    codeCompletionEverything = api.uid_get_from_cstr("source.codecompletion.everything")!
    codeCompletionModule = api.uid_get_from_cstr("source.codecompletion.module")!
    codeCompletionKeyword = api.uid_get_from_cstr("source.codecompletion.keyword")!
    codeCompletionLiteral = api.uid_get_from_cstr("source.codecompletion.literal")!
    codeCompletionCustom = api.uid_get_from_cstr("source.codecompletion.custom")!
    codeCompletionIdentifier = api.uid_get_from_cstr("source.codecompletion.identifier")!
    codeCompletionDescription = api.uid_get_from_cstr("source.codecompletion.description")!
    editActive = api.uid_get_from_cstr("source.edit.kind.active")!
    editInactive = api.uid_get_from_cstr("source.edit.kind.inactive")!
    editSelector = api.uid_get_from_cstr("source.edit.kind.selector")!
    editString = api.uid_get_from_cstr("source.edit.kind.string")!
    editComment = api.uid_get_from_cstr("source.edit.kind.comment")!
    editMismatch = api.uid_get_from_cstr("source.edit.kind.mismatch")!
    editUnknown = api.uid_get_from_cstr("source.edit.kind.unknown")!
    renameRangeBase = api.uid_get_from_cstr("source.refactoring.range.kind.basename")!
    renameRangeKeywordBase = api.uid_get_from_cstr("source.refactoring.range.kind.keyword-basename")!
    renameRangeParam = api.uid_get_from_cstr("source.refactoring.range.kind.parameter-and-whitespace")!
    renameRangeNoncollapsibleParam = api.uid_get_from_cstr("source.refactoring.range.kind.noncollapsible-parameter")!
    renameRangeDeclArgLabel = api.uid_get_from_cstr("source.refactoring.range.kind.decl-argument-label")!
    renameRangeCallArgLabel = api.uid_get_from_cstr("source.refactoring.range.kind.call-argument-label")!
    renameRangeCallArgColon = api.uid_get_from_cstr("source.refactoring.range.kind.call-argument-colon")!
    renameRangeCallArgCombined = api.uid_get_from_cstr("source.refactoring.range.kind.call-argument-combined")!
    renameRangeSelectorArgLabel = api.uid_get_from_cstr("source.refactoring.range.kind.selector-argument-label")!
    definition = api.uid_get_from_cstr("source.syntacticrename.definition")!
    reference = api.uid_get_from_cstr("source.syntacticrename.reference")!
    call = api.uid_get_from_cstr("source.syntacticrename.call")!
    unknown = api.uid_get_from_cstr("source.syntacticrename.unknown")!
    statNumRequests = api.uid_get_from_cstr("source.statistic.num-requests")!
    statNumSemaRequests = api.uid_get_from_cstr("source.statistic.num-semantic-requests")!
    statInstructionCount = api.uid_get_from_cstr("source.statistic.instruction-count")!
    swift = api.uid_get_from_cstr("source.lang.swift")!
    objC = api.uid_get_from_cstr("source.lang.objc")!
    macroRoleExpression = api.uid_get_from_cstr("source.lang.swift.macro_role.expression")!
    macroRoleDeclaration = api.uid_get_from_cstr("source.lang.swift.macro_role.declaration")!
    macroRoleCodeItem = api.uid_get_from_cstr("source.lang.swift.macro_role.codeitem")!
    macroRoleAccessor = api.uid_get_from_cstr("source.lang.swift.macro_role.accessor")!
    macroRoleMemberAttribute = api.uid_get_from_cstr("source.lang.swift.macro_role.member_attribute")!
    macroRoleMember = api.uid_get_from_cstr("source.lang.swift.macro_role.member")!
    macroRolePeer = api.uid_get_from_cstr("source.lang.swift.macro_role.peer")!
    macroRoleConformance = api.uid_get_from_cstr("source.lang.swift.macro_role.conformance")!
    macroRoleExtension = api.uid_get_from_cstr("source.lang.swift.macro_role.extension")!
    macroRolePreamble = api.uid_get_from_cstr("source.lang.swift.macro_role.preamble")!
    macroRoleBody = api.uid_get_from_cstr("source.lang.swift.macro_role.body")!
    completionKindKeyword = api.uid_get_from_cstr("source.lang.swift.keyword")!
    completionKindPattern = api.uid_get_from_cstr("source.lang.swift.pattern")!
    semaDiagStage = api.uid_get_from_cstr("source.diagnostic.stage.swift.sema")!
    parseDiagStage = api.uid_get_from_cstr("source.diagnostic.stage.swift.parse")!
    semaDisabledNotification = api.uid_get_from_cstr("source.notification.sema_disabled")!
    semaEnabledNotification = api.uid_get_from_cstr("source.notification.sema_enabled")!
    documentUpdateNotification = api.uid_get_from_cstr("source.notification.editor.documentupdate")!
  }
}
