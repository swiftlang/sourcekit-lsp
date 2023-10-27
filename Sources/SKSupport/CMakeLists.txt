
add_library(SKSupport STATIC
  AsyncQueue.swift
  AsyncUtils.swift
  BuildConfiguration.swift
  ByteString.swift
  Connection+Send.swift
  dlopen.swift
  FileSystem.swift
  LineTable.swift
  LoggableMessageTypes.swift
  Random.swift
  Result.swift
  ThreadSafeBox.swift
)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSupport PRIVATE
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
