
add_library(SKSwiftPMWorkspace STATIC
  SwiftPMWorkspace.swift)
set_target_properties(SKSwiftPMWorkspace PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKSwiftPMWorkspace PRIVATE
  BuildServerProtocol
  LanguageServerProtocol
  SKCore)
target_link_libraries(SKSwiftPMWorkspace PUBLIC
  Build)
