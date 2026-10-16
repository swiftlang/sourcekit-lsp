
add_library(DocumentationLanguageService STATIC
  BuildSystemIntegrationExtensions.swift
  DocCCatalogIndexManager.swift
  DoccDocumentationError.swift
  DoccDocumentationHandler.swift
  DocCDocumentationManager.swift
  DocCReferenceResolutionService.swift
  DocCServer.swift
  DocCSymbolInformation.swift
  DocCSymbolLink.swift
  DocumentationLanguageService.swift
  EmptySymbolGraph.swift
  IndexStoreDB+Extensions.swift)
set_target_properties(DocumentationLanguageService PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(DocumentationLanguageService PRIVATE
  BuildServerIntegration
  BuildServerProtocol
  DocCCommon
  IndexStoreDB
  LanguageServerProtocol
  Markdown
  SemanticIndex
  SKLogging
  SKOptions
  SKUtilties
  SourceKitLSP
  SwiftDocC
  SwiftExtensions
  SwiftSyntax
  SymbolKit
  ToolchainRegistry
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
