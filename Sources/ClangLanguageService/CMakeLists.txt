add_library(ClangLanguageService STATIC
  ClangLanguageService.swift
  SemanticTokenTranslator.swift
)

set_target_properties(ClangLanguageService PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)

target_link_libraries(ClangLanguageService PUBLIC
  SwiftToolsProtocols::LanguageServerProtocol
  SKOptions
  SourceKitLSP
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  ToolchainRegistry
  SwiftSyntax::SwiftSyntax
)

target_link_libraries(ClangLanguageService PRIVATE
  BuildServerIntegration
  LanguageServerProtocolExtensions
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SwiftToolsProtocols::SKLogging
  TSCExtensions
)
