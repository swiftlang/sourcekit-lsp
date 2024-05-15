
add_library(SemanticIndex STATIC
  CheckedIndex.swift
  IndexTaskDescription.swift
  PreparationTaskDescription.swift
  SemanticIndexManager.swift
  UpdateIndexStoreTaskDescription.swift
)
set_target_properties(SemanticIndex PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SemanticIndex PRIVATE
  LSPLogging
  SKCore
  IndexStoreDB
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
