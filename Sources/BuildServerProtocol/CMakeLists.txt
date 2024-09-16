add_library(BuildServerProtocol STATIC
  Messages.swift

  Messages/TextDocumentSourceKitOptionsRequest.swift
  Messages/OnBuildTargetDidChangeNotification.swift
  Messages/InitializeBuildRequest.swift
  Messages/BuildTargetSourcesRequest.swift
  Messages/OnBuildExitNotification.swift
  Messages/RegisterForChangeNotifications.swift
  Messages/OnBuildLogMessageNotification.swift
  Messages/WorkDoneProgress.swift
  Messages/OnWatchedFilesDidChangeNotification.swift
  Messages/OnBuildInitializedNotification.swift
  Messages/WorkspaceWaitForBuildSystemUpdates.swift
  Messages/BuildShutdownRequest.swift
  Messages/WorkspaceBuildTargetsRequest.swift
  Messages/BuildTargetPrepareRequest.swift

  SupportTypes/TextDocumentIdentifier.swift
  SupportTypes/TaskId.swift
  SupportTypes/BuildTarget.swift
  SupportTypes/MessageType.swift)
set_target_properties(BuildServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildServerProtocol PRIVATE
  LanguageServerProtocol)
