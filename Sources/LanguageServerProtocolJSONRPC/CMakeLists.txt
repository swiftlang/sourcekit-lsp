add_library(LanguageServerProtocolJSONRPC STATIC
  DisableSigpipe.swift
  JSONRPCConnection.swift
  LoggableMessageTypes.swift
  MessageCoding.swift
  MessageSplitting.swift)
set_target_properties(LanguageServerProtocolJSONRPC PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LanguageServerProtocolJSONRPC PRIVATE
  LanguageServerProtocol
  LSPLogging)
target_link_libraries(LanguageServerProtocolJSONRPC PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:swiftDispatch>
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
