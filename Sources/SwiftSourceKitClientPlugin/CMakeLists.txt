add_library(SwiftSourceKitClientPlugin SHARED
  ClientPlugin.swift)

set_target_properties(SwiftSourceKitClientPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SwiftSourceKitClientPlugin PRIVATE 
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias SourceKitD=SourceKitDForPlugin"
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
target_link_libraries(SwiftSourceKitClientPlugin PRIVATE
  Csourcekitd
  SourceKitD
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  SwiftSourceKitPluginCommon
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

install(TARGETS SwiftSourceKitClientPlugin
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
