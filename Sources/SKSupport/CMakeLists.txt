
add_library(SKSupport STATIC
  AbsolutePath+Init.swift
  ByteString.swift
  Connection+Send.swift
  Debouncer.swift
  Dictionary+InitWithElementsKeyedBy.swift
  DocumentURI+CustomLogStringConvertible.swift
  ExperimentalFeatures.swift
  FileSystem.swift
  LineTable.swift
  LocalConnection.swift
  Process+Run.swift
  SwitchableProcessResultExitStatus.swift
)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSupport PUBLIC
  CAtomics
)
target_link_libraries(SKSupport PRIVATE
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKLogging
  SourceKitD
  SwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
