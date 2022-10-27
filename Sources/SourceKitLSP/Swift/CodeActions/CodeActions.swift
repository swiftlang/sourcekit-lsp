public let allCodeActions: [CodeActionProvider.Type] = [
  MigrateToNewIfLetSyntax.self,
  OpaqueParameterToGeneric.self,
  ReformatIntegerLiteral.self,
  ConvertIntegerLiteral.self,
  ConvertJSONToCodableStruct.self,
  Demorgan.self,
]
