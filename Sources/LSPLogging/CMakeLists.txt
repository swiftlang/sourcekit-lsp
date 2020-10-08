add_library(LSPLogging
  LogLevel.swift
  Logging.swift)
set_target_properties(LSPLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  if(Foundation_FOUND)
    target_link_libraries(LSPLogging PRIVATE
      Foundation)
  endif()
endif()

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS LSPLogging
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:LSPLogging,Swift_MODULE_DIRECTORY>/LSPLogging.swiftdoc
    $<TARGET_PROPERTY:LSPLogging,Swift_MODULE_DIRECTORY>/LSPLogging.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
