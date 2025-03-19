
add_library(DocCDocumentation STATIC
  BuildSystemIntegrationExtensions.swift
  DocCCatalogIndexManager.swift
  DocCDocumentationManager.swift
  DocCReferenceResolutionService.swift
  DocCSymbolLink.swift
  DoccDocumentationError.swift
  DocCDocumentationManagerImpl.swift
  DocCServer.swift
)
set_target_properties(DocCDocumentation PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(DocCDocumentation PUBLIC
  BuildServerProtocol
  BuildSystemIntegration
  IndexStoreDB
  LanguageServerProtocol
  SemanticIndex
  SwiftExtensions)
