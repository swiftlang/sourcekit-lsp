add_library(LSPLogging STATIC
  CustomLogStringConvertible.swift
  Error+ForLogging.swift
  Logging.swift
  LoggingScope.swift
  NonDarwinLogging.swift
  OrLog.swift
  SplitLogMessage.swift)
set_target_properties(LSPLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LSPLogging PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(LSPLogging PUBLIC
  Crypto)
