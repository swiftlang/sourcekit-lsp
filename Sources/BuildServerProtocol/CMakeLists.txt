add_library(BuildServerProtocol STATIC
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
