add_library(BuildServerProtocol
  BuildTargets.swift
  FileOptions.swift
  InitializeBuild.swift
  Messages.swift
  RegisterForChangeNotifications.swift
  ShutdownBuild.swift)
set_target_properties(BuildServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildServerProtocol PRIVATE
  LanguageServerProtocol)

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS BuildServerProtocol
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch}
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch}
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:BuildServerProtocol,Swift_MODULE_DIRECTORY>/BuildServerProtocol.swiftdoc
    $<TARGET_PROPERTY:BuildServerProtocol,Swift_MODULE_DIRECTORY>/BuildServerProtocol.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
