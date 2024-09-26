
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
  QueueBasedMessageHandler.swift
  RequestAndReply.swift
  ResponseError+Init.swift
  SwitchableProcessResultExitStatus.swift
  WorkDoneProgressManager.swift
)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSupport PUBLIC
  SourceKitD)
target_link_libraries(SKSupport PRIVATE
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKLogging
  SwiftExtensions
  TSCBasic
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
