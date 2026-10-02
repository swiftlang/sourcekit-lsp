add_library(SwiftSourceKitClientPlugin SHARED
  ClientPlugin.swift)

set_target_properties(SwiftSourceKitClientPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SwiftSourceKitClientPlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias SKLogging=_SKLoggingForPlugin"
    "SHELL:-module-alias SourceKitD=SourceKitDForPlugin"
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
target_link_libraries(SwiftSourceKitClientPlugin PRIVATE
  Csourcekitd
  SourceKitD
  SwiftExtensions
  SwiftToolsProtocols::_SKLoggingForPlugin
  SwiftToolsProtocols::_ToolsProtocolsSwiftExtensionsForPlugin
  SwiftSourceKitPluginCommon
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

install(TARGETS SwiftSourceKitClientPlugin DESTINATION lib)
if(MSVC)
  install(FILES $<TARGET_FILE_DIR:SwiftSourceKitClientPlugin>/$<TARGET_FILE_BASE_NAME:SwiftSourceKitClientPlugin>.pdb
    DESTINATION lib
    OPTIONAL)
endif()
