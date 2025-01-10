set(sources
  CustomLogStringConvertible.swift
  Error+ForLogging.swift
  Logging.swift
  LoggingScope.swift
  NonDarwinLogging.swift
  OrLog.swift
  SetGlobalLogFileHandler.swift
  SplitLogMessage.swift)

add_library(SKLogging STATIC ${sources})
set_target_properties(SKLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKLogging PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(SKLogging PUBLIC
  SwiftExtensions
  Crypto)

add_library(SKLoggingForPlugin STATIC ${sources})
set_target_properties(SKLoggingForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(SKLoggingForPlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:
    -DNO_CRYPTO_DEPENDENCY;
    "SHELL:-module-alias SwiftExtensions=SwiftExtensionsForPlugin"
  >)
target_link_libraries(SKLoggingForPlugin PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(SKLoggingForPlugin PUBLIC
  SwiftExtensionsForPlugin)
