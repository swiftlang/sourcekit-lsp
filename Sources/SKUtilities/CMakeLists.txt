set(sources
  Debouncer.swift
  Dictionary+InitWithElementsKeyedBy.swift
  LineTable.swift
  LRUCache.swift
)

add_library(SKUtilities STATIC ${sources})
set_target_properties(SKUtilities PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKUtilities PRIVATE
  SwiftToolsProtocols::SKLogging
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

add_library(SKUtilitiesForPlugin STATIC ${sources})
set_target_properties(SKUtilitiesForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SKUtilitiesForPlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias SKLogging=_SKLoggingForPlugin"
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
target_link_libraries(SKUtilitiesForPlugin PRIVATE
  SwiftToolsProtocols::_SKLoggingForPlugin
  SwiftExtensionsForPlugin
  SwiftToolsProtocols::_ToolsProtocolsSwiftExtensionsForPlugin
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
