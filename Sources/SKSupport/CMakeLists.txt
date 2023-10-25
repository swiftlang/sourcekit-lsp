
add_library(SKSupport STATIC
  BuildConfiguration.swift
  ByteString.swift
  dlopen.swift
  FileSystem.swift
  LineTable.swift
  Random.swift
  Result.swift
  Task+ValuePropagatingCancellation.swift
  ThreadSafeBox.swift
)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSupport PRIVATE
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
