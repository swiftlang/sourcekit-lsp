
add_library(SKSupport STATIC
  AsyncQueue.swift
  AsyncUtils.swift
  BuildConfiguration.swift
  ByteString.swift
  Collection+Only.swift
  Collection+PartitionIntoBatches.swift
  Connection+Send.swift
  dlopen.swift
  DocumentURI+CustomLogStringConvertible.swift
  FileSystem.swift
  LineTable.swift
  Process+LaunchWithWorkingDirectoryIfPossible.swift
  Process+WaitUntilExitWithCancellation.swift
  Random.swift
  Result.swift
  SwitchableProcessResultExitStatus.swift
  ThreadSafeBox.swift
  WorkspaceType.swift
)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSupport PRIVATE
  LanguageServerProtocol
  LSPLogging
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
