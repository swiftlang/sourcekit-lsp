
add_library(SKUtilities STATIC
  Debouncer.swift
  Dictionary+InitWithElementsKeyedBy.swift
  LineTable.swift
)
set_target_properties(SKUtilities PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKUtilities PRIVATE
  SKLogging
  SwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
