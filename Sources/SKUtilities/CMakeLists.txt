set(sources
  Debouncer.swift
  Dictionary+InitWithElementsKeyedBy.swift
  LineTable.swift
)

add_library(SKUtilities STATIC ${sources})
set_target_properties(SKUtilities PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKUtilities PRIVATE
  SKLogging
  SwiftExtensions
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

add_library(SKUtilitiesForPlugin STATIC ${sources})
set_target_properties(SKUtilitiesForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SKUtilitiesForPlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias SKLogging=SKLoggingForPlugin"
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
  >)
target_link_libraries(SKUtilitiesForPlugin PRIVATE
  SKLoggingForPlugin
  SwiftExtensionsForPlugin
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)