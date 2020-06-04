if(CMAKE_VERSION VERSION_LESS 3.16)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
    set(CMAKE_LINK_LIBRARY_SUFFIX "")
  endif()
endif()

add_library(SourceKitD
  SKDRequestArray.swift
  SKDRequestDictionary.swift
  SKDResponse.swift
  SKDResponseArray.swift
  SKDResponseDictionary.swift
  SourceKitD.swift
  SourceKitDImpl.swift
  SourceKitDRegistry.swift
  sourcekitd_functions.swift
  sourcekitd_uids.swift)
set_target_properties(SourceKitD PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SourceKitD PRIVATE
  Csourcekitd
  LSPLogging
  SKSupport
  TSCUtility)

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS SourceKitD
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:SourceKitD,Swift_MODULE_DIRECTORY>/SourceKitD.swiftdoc
    $<TARGET_PROPERTY:SourceKitD,Swift_MODULE_DIRECTORY>/SourceKitD.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
