if(CMAKE_VERSION VERSION_LESS 3.16)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
    set(CMAKE_LINK_LIBRARY_SUFFIX "")
  endif()
endif()

add_library(SKSwiftPMWorkspace
  SwiftPMWorkspace.swift)
set_target_properties(SKSwiftPMWorkspace PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSwiftPMWorkspace PRIVATE
  BuildServerProtocol
  LanguageServerProtocol
  SKCore)
target_link_libraries(SKSwiftPMWorkspace PUBLIC
  Build)

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS SKSwiftPMWorkspace
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:SKSwiftPMWorkspace,Swift_MODULE_DIRECTORY>/SKSwiftPMWorkspace.swiftdoc
    $<TARGET_PROPERTY:SKSwiftPMWorkspace,Swift_MODULE_DIRECTORY>/SKSwiftPMWorkspace.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
