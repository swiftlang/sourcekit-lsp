
add_library(SourceKitLSP STATIC
  CapabilityRegistry.swift
  DocumentManager.swift
  DocumentSnapshot+FromFileContents.swift
  IndexProgressManager.swift
  IndexStoreDB+MainFilesProvider.swift
  LanguageServerType.swift
  LanguageService.swift
  MessageHandlingDependencyTracker.swift
  Rename.swift
  SemanticTokensLegend+SourceKitLSPLegend.swift
  SharedWorkDoneProgressManager.swift
  SourceKitIndexDelegate.swift
  SourceKitLSPCommandMetadata.swift
  SourceKitLSPServer.swift
  SymbolLocation+DocumentURI.swift
  TestDiscovery.swift
  TestHooks.swift
  TextEdit+IsNoop.swift
  Workspace.swift
)
target_sources(SourceKitLSP PRIVATE
  Clang/ClangLanguageService.swift
  Clang/SemanticTokenTranslator.swift
)
target_sources(SourceKitLSP PRIVATE
  Documentation/DocumentationLanguageService.swift
)
target_sources(SourceKitLSP PRIVATE
  Swift/AdjustPositionToStartOfIdentifier.swift
  Swift/ClosureCompletionFormat.swift
  Swift/CodeActions/AddDocumentation.swift
  Swift/CodeActions/ConvertIntegerLiteral.swift
  Swift/CodeActions/ConvertJSONToCodableStruct.swift
  Swift/CodeActions/ConvertStringConcatenationToStringInterpolation.swift
  Swift/CodeActions/PackageManifestEdits.swift
  Swift/CodeActions/SyntaxCodeActionProvider.swift
  Swift/CodeActions/SyntaxCodeActions.swift
  Swift/CodeActions/SyntaxRefactoringCodeActionProvider.swift
  Swift/CodeCompletion.swift
  Swift/CodeCompletionSession.swift
  Swift/CommentXML.swift
  Swift/CursorInfo.swift
  Swift/Diagnostic.swift
  Swift/DiagnosticReportManager.swift
  Swift/DocumentFormatting.swift
  Swift/DocumentSymbols.swift
  Swift/ExpandMacroCommand.swift
  Swift/FoldingRange.swift
  Swift/GeneratedInterfaceManager.swift
  Swift/MacroExpansion.swift
  Swift/MacroExpansionReferenceDocumentURLData.swift
  Swift/OpenInterface.swift
  Swift/RefactoringEdit.swift
  Swift/RefactoringResponse.swift
  Swift/ReferenceDocumentURL.swift
  Swift/RelatedIdentifiers.swift
  Swift/RewriteSourceKitPlaceholders.swift
  Swift/SemanticRefactorCommand.swift
  Swift/SemanticRefactoring.swift
  Swift/SemanticTokens.swift
  Swift/SwiftCodeLensScanner.swift
  Swift/SwiftCommand.swift
  Swift/SwiftLanguageService.swift
  Swift/SwiftTestingScanner.swift
  Swift/SymbolInfo.swift
  Swift/SyntacticSwiftXCTestScanner.swift
  Swift/SyntacticTestIndex.swift
  Swift/SyntaxHighlightingToken.swift
  Swift/SyntaxHighlightingTokenParser.swift
  Swift/SyntaxHighlightingTokens.swift
  Swift/SyntaxTreeManager.swift
  Swift/VariableTypeInfo.swift
)
set_target_properties(SourceKitLSP PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SourceKitLSP PUBLIC
  BuildServerProtocol
  BuildSystemIntegration
  LanguageServerProtocol
  LanguageServerProtocolExtensions
  LanguageServerProtocolJSONRPC
  SemanticIndex
  SKLogging
  SKOptions
  SKUtilities
  SourceKitD
  SwiftExtensions
  ToolchainRegistry
  IndexStoreDB
  SwiftSyntax::SwiftBasicFormat
  SwiftSyntax::SwiftDiagnostics
  SwiftSyntax::SwiftIDEUtils
  SwiftSyntax::SwiftParser
  SwiftSyntax::SwiftParserDiagnostics
  SwiftSyntax::SwiftRefactor
  SwiftSyntax::SwiftSyntax)
target_link_libraries(SourceKitLSP PRIVATE
  PackageModelSyntax
  TSCExtensions
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

