add_library(SKLogging STATIC
  CustomLogStringConvertible.swift
  Error+ForLogging.swift
  Logging.swift
  LoggingScope.swift
  NonDarwinLogging.swift
  OrLog.swift
  SetGlobalLogFileHandler.swift
  SplitLogMessage.swift)
set_target_properties(SKLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKLogging PRIVATE
  SwiftExtensions
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(SKLogging PUBLIC
  Crypto)
