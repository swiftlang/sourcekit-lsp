
add_library(TSCExtensions STATIC
  AbsolutePath+Init.swift
  ByteString.swift
  Process+Run.swift
  SwitchableProcessResultExitStatus.swift
  URL+appendingRelativePath.swift
)
set_target_properties(TSCExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(TSCExtensions PRIVATE
  SKLogging
  SwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
