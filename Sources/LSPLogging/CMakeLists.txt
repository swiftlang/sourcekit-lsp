add_library(LSPLogging STATIC
  LogLevel.swift
  Logging.swift)
set_target_properties(LSPLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LSPLogging PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
