
add_library(SKOptions STATIC
  BuildConfiguration.swift
  ExperimentalFeatures.swift
  SourceKitLSPOptions.swift
  WorkspaceType.swift)
set_target_properties(SKOptions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKOptions PUBLIC
  LanguageServerProtocol
  LanguageServerProtocolExtensions
  SKLogging
  TSCBasic)
