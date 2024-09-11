add_library(BuildServerProtocol STATIC
  BuildTargets.swift
  DidChangeBuildTargetNotification.swift
  DidChangeWatchedFilesNotification.swift
  InitializeBuild.swift
  InverseSourcesRequest.swift
  LogMessageNotification.swift
  Messages.swift
  PrepareTargetsRequest.swift
  RegisterForChangeNotifications.swift
  ShutdownBuild.swift
  SourceKitOptionsRequest.swift)
set_target_properties(BuildServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildServerProtocol PRIVATE
  LanguageServerProtocol)
