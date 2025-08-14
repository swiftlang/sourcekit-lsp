
add_library(SourceKitLSP STATIC
  CapabilityRegistry.swift
  DocumentManager.swift
  DocumentSnapshot+FromFileContents.swift
  DocumentSnapshot+PositionConversions.swift
  GeneratedInterfaceDocumentURLData.swift
  Hooks.swift
  IndexProgressManager.swift
  IndexStoreDB+MainFilesProvider.swift
  LanguageService.swift
  LanguageServiceRegistry.swift
  LogMessageNotification+representingStructureUsingEmojiPrefixIfNecessary.swift
  MacroExpansionReferenceDocumentURLData.swift
  MessageHandlingDependencyTracker.swift
  ReferenceDocumentURL.swift
  Rename.swift
  SemanticTokensLegend+SourceKitLSPLegend.swift
  SharedWorkDoneProgressManager.swift
  SourceKitIndexDelegate.swift
  SourceKitLSPCommandMetadata.swift
  SourceKitLSPServer.swift
  SymbolLocation+DocumentURI.swift
  SyntacticTestIndex.swift
  TestDiscovery.swift
  TextEdit+IsNoop.swift
  Workspace.swift
)
target_sources(SourceKitLSP PRIVATE
  Documentation/DocCDocumentationHandler.swift
  Documentation/DocumentationLanguageService.swift
)
set_target_properties(SourceKitLSP PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
target_link_libraries(SourceKitLSP PUBLIC
  BuildServerProtocol
  BuildServerIntegration
  LanguageServerProtocol
  LanguageServerProtocolExtensions
  SemanticIndex
  SKOptions
  SKUtilities
  SwiftExtensions
  ToolchainRegistry
  IndexStoreDB
  SwiftSyntax::SwiftSyntax
)
target_link_libraries(SourceKitLSP PRIVATE
  LanguageServerProtocolJSONRPC
  SKLogging
  SourceKitD
  TSCExtensions
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>
)

