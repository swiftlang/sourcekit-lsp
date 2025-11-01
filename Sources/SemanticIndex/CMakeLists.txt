
add_library(SemanticIndex STATIC
  CheckedIndex.swift
  IndexTaskDescription.swift
  IndexHooks.swift
  PreparationTaskDescription.swift
  SemanticIndexManager.swift
  TaskScheduler.swift
  UpdateIndexStoreTaskDescription.swift
  UpToDateTracker.swift
)
set_target_properties(SemanticIndex PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SemanticIndex PRIVATE
  BuildServerIntegration
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftToolsProtocols::SKLogging
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  ToolchainRegistry
  TSCExtensions
  IndexStoreDB
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
