add_library(InProcessClient STATIC
  InProcessSourceKitLSPClient.swift
  LanguageServiceRegistry+staticallyKnownServices.swift)

set_target_properties(InProcessClient PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(InProcessClient PUBLIC
  BuildServerIntegration
  ClangLanguageService
  Crypto
  LanguageServerProtocolExtensions
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SwiftToolsProtocols::SKLogging
  SKOptions
  SourceKitLSP
  SwiftExtensions
  SwiftLanguageService
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  ToolchainRegistry
  TSCBasic
)

target_link_libraries(InProcessClient PRIVATE
  TSCExtensions
)
