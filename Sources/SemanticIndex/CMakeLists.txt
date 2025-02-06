
add_library(SemanticIndex STATIC
  CheckedIndex.swift
  IndexTaskDescription.swift
  IndexTestHooks.swift
  PreparationTaskDescription.swift
  SemanticIndexManager.swift
  TaskScheduler.swift
  UpdateIndexStoreTaskDescription.swift
  UpToDateTracker.swift
)
set_target_properties(SemanticIndex PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SemanticIndex PRIVATE
  BuildSystemIntegration
  LanguageServerProtocol
  SKLogging
  SwiftExtensions
  ToolchainRegistry
  TSCExtensions
  IndexStoreDB
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
