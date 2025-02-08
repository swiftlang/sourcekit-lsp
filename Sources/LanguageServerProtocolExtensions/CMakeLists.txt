
add_library(LanguageServerProtocolExtensions STATIC
  Connection+Send.swift
  DocumentURI+CustomLogStringConvertible.swift
  DocumentURI+symlinkTarget.swift
  Language+Inference.swift
  LocalConnection.swift
  QueueBasedMessageHandler.swift
  RequestAndReply.swift
  ResponseError+Init.swift
  WorkDoneProgressManager.swift
)
set_target_properties(LanguageServerProtocolExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LanguageServerProtocolExtensions PUBLIC
  SourceKitD)
target_link_libraries(LanguageServerProtocolExtensions PRIVATE
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKLogging
  SwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
