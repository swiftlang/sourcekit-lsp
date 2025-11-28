
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
  OnDiskDocumentManager.swift
  PlaygroundDiscovery.swift
  ReferenceDocumentURL.swift
  Rename.swift
  SemanticTokensLegend+SourceKitLSPLegend.swift
  SharedWorkDoneProgressManager.swift
  SourceKitIndexDelegate.swift
  SourceKitLSPCommandMetadata.swift
  SourceKitLSPServer.swift
  SymbolLocation+DocumentURI.swift
  SwiftSyntacticIndex.swift
  TestDiscovery.swift
  TextEdit+IsNoop.swift
  Workspace.swift
)
set_target_properties(SourceKitLSP PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY}
)
target_link_libraries(SourceKitLSP PUBLIC
  SwiftToolsProtocols::BuildServerProtocol
  BuildServerIntegration
  SwiftToolsProtocols::LanguageServerProtocol
  LanguageServerProtocolExtensions
  SemanticIndex
  SKOptions
  SKUtilities
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  ToolchainRegistry
  IndexStoreDB
  SwiftSyntax::SwiftSyntax
)
target_link_libraries(SourceKitLSP PRIVATE
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SwiftToolsProtocols::SKLogging
  SourceKitD
  TSCExtensions
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>
)

