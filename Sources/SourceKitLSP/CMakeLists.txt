
add_library(SourceKitLSP STATIC
  CapabilityRegistry.swift
  DocumentManager.swift
  DocumentTokens.swift
  IndexStoreDB+MainFilesProvider.swift
  RangeAdjuster.swift
  SourceKitIndexDelegate.swift
  SourceKitLSPCommandMetadata.swift
  SourceKitServer+Options.swift
  SourceKitServer.swift
  ToolchainLanguageServer.swift
  Workspace.swift)
target_sources(SourceKitLSP PRIVATE
  Clang/ClangLanguageServer.swift)
target_sources(SourceKitLSP PRIVATE
  Swift/CodeCompletion.swift
  Swift/CodeCompletionSession.swift
  Swift/CommentXML.swift
  Swift/CursorInfo.swift
  Swift/Diagnostic.swift
  Swift/EditorPlaceholder.swift
  Swift/ExpressionTypeInfo.swift
  Swift/OpenInterface.swift
  Swift/SemanticRefactorCommand.swift
  Swift/SemanticRefactoring.swift
  Swift/SourceKitD+ResponseError.swift
  Swift/SwiftCommand.swift
  Swift/SwiftLanguageServer.swift
  Swift/SyntaxHighlightingToken.swift
  Swift/SyntaxHighlightingTokenParser.swift
  Swift/VariableTypeInfo.swift)
set_target_properties(SourceKitLSP PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
# TODO(compnerd) reduce the exposure here, why is everything PUBLIC-ly linked?
target_link_libraries(SourceKitLSP PUBLIC
  Csourcekitd
  BuildServerProtocol
  IndexStoreDB
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKCore
  SKSwiftPMWorkspace
  SourceKitD
  SwiftSyntax::SwiftBasicFormat
  SwiftSyntax::SwiftParser
  SwiftSyntax::SwiftDiagnostics
  SwiftSyntax::SwiftSyntax
  SwiftSyntax::IDEUtils
  TSCUtility)
target_link_libraries(SourceKitLSP PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

