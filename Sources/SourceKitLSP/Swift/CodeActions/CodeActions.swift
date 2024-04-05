import SwiftRefactor

/// List of all of the syntax-local code actions.
public let allLocalCodeActions: [CodeActionProvider.Type] = [
  AddSeparatorsToIntegerLiteral.self,
  ConvertIntegerLiteral.self,
  ConvertJSONToCodableStruct.self,
  Demorgan.self,
  FormatRawStringLiteral.self,
  MigrateToNewIfLetSyntax.self,
  OpaqueParameterToGeneric.self,
  RemoveSeparatorsFromIntegerLiteral.self,
]
