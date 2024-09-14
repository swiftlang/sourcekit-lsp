add_library(BuildServerProtocol STATIC
  BuildTargetSourcesRequest.swift
  BuildTargetsRequest.swift
  DidChangeBuildTargetNotification.swift
  DidChangeWatchedFilesNotification.swift
  InitializeBuild.swift
  LogMessageNotification.swift
  Messages.swift
  PrepareTargetsRequest.swift
  RegisterForChangeNotifications.swift
  ShutdownBuild.swift
  SourceKitOptionsRequest.swift
  TextDocumentIdentifier.swift
  WaitForBuildSystemUpdates.swift
  WorkDoneProgress.swift)
set_target_properties(BuildServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildServerProtocol PRIVATE
  LanguageServerProtocol)
