//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

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
