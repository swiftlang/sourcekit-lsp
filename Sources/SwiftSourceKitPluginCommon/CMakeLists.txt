add_library(SwiftSourceKitPluginCommon STATIC
  CompletionResultsArray.swift
  DynamicallyLoadedSourceKitdD+forPlugin.swift)

target_compile_options(SwiftSourceKitPluginCommon PRIVATE 
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias SourceKitD=SourceKitDForPlugin"
    "SHELL:-module-alias SKLogging=_SKLoggingForPlugin"
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
set_target_properties(SwiftSourceKitPluginCommon PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SwiftSourceKitPluginCommon PRIVATE
  Csourcekitd
  SourceKitDForPlugin
  SwiftToolsProtocols::_SKLoggingForPlugin
  SwiftExtensionsForPlugin
  SwiftToolsProtocols::_ToolsProtocolsSwiftExtensionsForPlugin
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)
