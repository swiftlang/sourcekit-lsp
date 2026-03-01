add_library(SwiftSourceKitPlugin SHARED
  ASTCompletion/ASTCompletionItem.swift
  ASTCompletion/CompletionSession.swift
  SKDResponse.swift
  SKDResponseArrayBuilder.swift
  SourceKitPluginError.swift
  SKDRequestDictionaryReader.swift
  SKDRequestArrayReader.swift
  CompletionResultsArrayBuilder.swift
  SKDResponseValue.swift
  CompletionProvider.swift
  SKDResponseDictionaryBuilder.swift
  CodeCompletion/Location.swift
  CodeCompletion/Connection.swift
  CodeCompletion/CompletionContext.swift
  CodeCompletion/Completion+ItemKind.swift
  CodeCompletion/Completion+SemanticContext.swift
  CodeCompletion/Completion+Identifier.swift
  CodeCompletion/TextEdit.swift
  CodeCompletion/Completion+TypeRelation.swift
  CodeCompletion/CompletionItem.swift
  CodeCompletion/WithArrayOfCStrings.swift
  CodeCompletion/CompletionOptions.swift
  CodeCompletion/Completion+Diagnostic.swift
  CodeCompletion/CompletionSorting.swift
  CodeCompletion/Completion+PriorityBucket.swift
  CodeCompletion/Position.swift
  SourceKitDWrappers.swift
  Plugin.swift)

set_target_properties(SwiftSourceKitPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SwiftSourceKitPlugin PRIVATE 
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias CompletionScoring=CompletionScoringForPlugin"
    "SHELL:-module-alias SKLogging=_SKLoggingForPlugin"
    "SHELL:-module-alias SKUtilities=SKUtilitiesForPlugin"
    "SHELL:-module-alias SourceKitD=SourceKitDForPlugin"
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
target_link_libraries(SwiftSourceKitPlugin PRIVATE
  Csourcekitd
  CompletionScoringForPlugin
  SKUtilitiesForPlugin
  SwiftToolsProtocols::_SKLoggingForPlugin
  SourceKitDForPlugin
  SwiftSourceKitPluginCommon
  SwiftExtensionsForPlugin
  SwiftToolsProtocols::_ToolsProtocolsSwiftExtensionsForPlugin
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

install(TARGETS SwiftSourceKitPlugin
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
