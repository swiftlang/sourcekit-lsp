
add_library(LanguageServerProtocolExtensions STATIC
  Connection+Send.swift
  DocumentURI+symlinkTarget.swift
  Language+Inference.swift
  ResponseError+Init.swift
  WorkDoneProgressManager.swift
)
set_target_properties(LanguageServerProtocolExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LanguageServerProtocolExtensions PUBLIC
  SourceKitD)
target_link_libraries(LanguageServerProtocolExtensions PRIVATE
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SwiftToolsProtocols::SKLogging
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
