add_library(InProcessClient STATIC
  InProcessSourceKitLSPClient.swift)

set_target_properties(InProcessClient PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(InProcessClient PUBLIC
  BuildServerIntegration
  LanguageServerProtocol
  SKLogging
  SKOptions
  SourceKitLSP
  ToolchainRegistry
)

target_link_libraries(InProcessClient PRIVATE
  TSCExtensions
)
