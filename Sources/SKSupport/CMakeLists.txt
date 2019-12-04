if(CMAKE_VERSION VERSION_LESS 3.16)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
    set(CMAKE_LINK_LIBRARY_SUFFIX "")
  endif()
endif()

add_library(SKSupport
  BuildConfiguration.swift
  ByteString.swift
  FileSystem.swift
  LineTable.swift
  Platform.swift
  Random.swift
  Result.swift
  dlopen.swift)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSupport PRIVATE
  TSCUtility)

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS SKSupport
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:SKSupport,Swift_MODULE_DIRECTORY>/SKSupport.swiftdoc
    $<TARGET_PROPERTY:SKSupport,Swift_MODULE_DIRECTORY>/SKSupport.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
