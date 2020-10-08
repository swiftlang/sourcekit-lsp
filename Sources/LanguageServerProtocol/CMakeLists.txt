add_library(LanguageServerProtocol
  Cancellation.swift
  Connection.swift
  CustomCodable.swift
  Error.swift
  Message.swift
  MessageRegistry.swift
  Messages.swift
  PositionRange.swift
  Request.swift
  RequestID.swift

  Notifications/CancelRequestNotification.swift
  Notifications/ConfigurationNotification.swift
  Notifications/DidChangeWorkspaceFoldersNotification.swift
  Notifications/ExitNotification.swift
  Notifications/InitializedNotification.swift
  Notifications/LogMessageNotification.swift
  Notifications/PublishDiagnosticsNotification.swift
  Notifications/ShowMessageNotification.swift
  Notifications/TextSynchronizationNotifications.swift

  Requests/ApplyEditRequest.swift
  Requests/CodeActionRequest.swift
  Requests/ColorPresentationRequest.swift
  Requests/CompletionRequest.swift
  Requests/DefinitionRequest.swift
  Requests/DocumentColorRequest.swift
  Requests/DocumentHighlightRequest.swift
  Requests/DocumentSymbolRequest.swift
  Requests/ExecuteCommandRequest.swift
  Requests/FoldingRangeRequest.swift
  Requests/FormattingRequests.swift
  Requests/HoverRequest.swift
  Requests/ImplementationRequest.swift
  Requests/InitializeRequest.swift
  Requests/PollIndexRequest.swift
  Requests/ReferencesRequest.swift
  Requests/ShowMessageRequest.swift
  Requests/ShutdownRequest.swift
  Requests/SymbolInfoRequest.swift
  Requests/WorkspaceFoldersRequest.swift
  Requests/WorkspaceSymbolsRequest.swift

  SupportTypes/ClientCapabilities.swift
  SupportTypes/CodeActionKind.swift
  SupportTypes/Command.swift
  SupportTypes/CompletionItem.swift
  SupportTypes/CompletionItemKind.swift
  SupportTypes/Diagnostic.swift
  SupportTypes/DocumentURI.swift
  SupportTypes/FoldingRangeKind.swift
  SupportTypes/Language.swift
  SupportTypes/Location.swift
  SupportTypes/LocationLink.swift
  SupportTypes/LocationsOrLocationLinksResponse.swift
  SupportTypes/LSPAny.swift
  SupportTypes/MarkupContent.swift
  SupportTypes/Position.swift
  SupportTypes/ServerCapabilities.swift
  SupportTypes/SKCompletionOptions.swift
  SupportTypes/SymbolKind.swift
  SupportTypes/TextDocumentContentChangeEvent.swift
  SupportTypes/TextDocumentEdit.swift
  SupportTypes/TextDocumentIdentifier.swift
  SupportTypes/TextDocumentItem.swift
  SupportTypes/TextDocumentSaveReason.swift
  SupportTypes/TextEdit.swift
  SupportTypes/VersionedTextDocumentIdentifier.swift
  SupportTypes/WindowMessageType.swift
  SupportTypes/WorkspaceEdit.swift
  SupportTypes/WorkspaceFolder.swift
  SupportTypes/WorkspaceSettings.swift)
set_target_properties(LanguageServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  if(dispatch_FOUND)
    target_link_libraries(LanguageServerProtocol PUBLIC
      swiftDispatch)
  endif()
  if(Foundation_FOUND)
    target_link_libraries(LanguageServerProtocol PUBLIC
      Foundation)
  endif()
endif()

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS LanguageServerProtocol
    ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>
    RUNTIME DESTINATION bin)
  install(FILES
    $<TARGET_PROPERTY:LanguageServerProtocol,Swift_MODULE_DIRECTORY>/LanguageServerProtocol.swiftdoc
    $<TARGET_PROPERTY:LanguageServerProtocol,Swift_MODULE_DIRECTORY>/LanguageServerProtocol.swiftmodule
    DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>/${swift_arch})
endif()
