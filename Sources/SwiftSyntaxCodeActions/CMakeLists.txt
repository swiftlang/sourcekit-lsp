add_library(SwiftSyntaxCodeActions STATIC
  AddDocumentation.swift
  ApplyDeMorganLaw.swift
  ConvertCommentToDocComment.swift
  ConvertIfLetToGuard.swift
  ConvertIntegerLiteral.swift
  ConvertJSONToCodableStruct.swift
  ConvertStringConcatenationToStringInterpolation.swift
  IndentationRemover.swift
  PackageManifestEdits.swift
  SyntaxCodeActionProvider.swift
  SyntaxCodeActions.swift
  SyntaxRefactoringCodeActionProvider.swift
)
set_target_properties(SwiftSyntaxCodeActions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SwiftSyntaxCodeActions PUBLIC
  SourceKitLSP
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftSyntax::SwiftSyntax
)

target_link_libraries(SwiftSyntaxCodeActions PRIVATE
  SwiftToolsProtocols::SKLogging
  SwiftExtensions
  SwiftSyntax::SwiftBasicFormat
  SwiftSyntax::SwiftOperators
  SwiftSyntax::SwiftParser
  SwiftSyntax::SwiftRefactor
  SwiftSyntax::SwiftSyntaxBuilder
)
