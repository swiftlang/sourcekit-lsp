add_library(LanguageServerProtocolJSONRPC
  DisableSigpipe.swift
  JSONRPCConnection.swift
  MessageCoding.swift
  MessageSplitting.swift)
set_target_properties(LanguageServerProtocolJSONRPC PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LanguageServerProtocolJSONRPC PRIVATE
  LanguageServerProtocol
  LSPLogging)

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS LanguageServerProtocolJSONRPC
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:LanguageServerProtocolJSONRPC,Swift_MODULE_DIRECTORY>/LanguageServerProtocolJSONRPC.swiftdoc
    $<TARGET_PROPERTY:LanguageServerProtocolJSONRPC,Swift_MODULE_DIRECTORY>/LanguageServerProtocolJSONRPC.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
