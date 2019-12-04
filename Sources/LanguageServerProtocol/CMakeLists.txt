add_library(LanguageServerProtocol
  ApplyEdit.swift
  CancelRequest.swift
  Cancellation.swift
  ClientCapabilities.swift
  CodeAction.swift
  CodeActionKind.swift
  ColorPresentationRequest.swift
  Command.swift
  Completion.swift
  CompletionItem.swift
  CompletionItemKind.swift
  Configuration.swift
  Connection.swift
  CustomCodable.swift
  DefinitionRequest.swift
  Diagnostic.swift
  DocumentColor.swift
  DocumentHighlight.swift
  DocumentSymbol.swift
  DocumentURI.swift
  Error.swift
  ExecuteCommand.swift
  FoldingRange.swift
  FoldingRangeKind.swift
  Formatting.swift
  Hover.swift
  ImplementationRequest.swift
  InitializeRequest.swift
  LSPAny.swift
  Language.swift
  Location.swift
  LogMessage.swift
  MarkupContent.swift
  Message.swift
  MessageRegistry.swift
  Messages.swift
  PollIndex.swift
  Position.swift
  PositionRange.swift
  PublishDiagnostics.swift
  ReferencesRequest.swift
  Request.swift
  RequestID.swift
  ServerCapabilities.swift
  ShowMessageRequest.swift
  Shutdown.swift
  SymbolInfo.swift
  SymbolKind.swift
  TextDocumentContentChangeEvent.swift
  TextDocumentEdit.swift
  TextDocumentIdentifier.swift
  TextDocumentItem.swift
  TextDocumentSaveReason.swift
  TextEdit.swift
  TextSynchronization.swift
  VersionedTextDocumentIdentifier.swift
  WindowMessageType.swift
  WorkspaceEdit.swift
  WorkspaceFolder.swift
  WorkspaceFolders.swift
  WorkspaceSettings.swift
  WorkspaceSymbols.swift)
set_target_properties(LanguageServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
if(NOT CMAKE_SYSTEM_NAME STREQUAL Windows)
  target_link_libraries(LanguageServerProtocol PUBLIC
    Foundation)
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
