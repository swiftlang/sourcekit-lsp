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

/// List of all of the syntactic code action providers, which can be used
/// to produce code actions using only the swift-syntax tree of a file.
let allSyntaxCodeActions: [any SyntaxCodeActionProvider.Type] = {
  var result: [any SyntaxCodeActionProvider.Type] = [
    AddDocumentation.self,
    AddSeparatorsToIntegerLiteral.self,
    ApplyDeMorganLaw.self,
    ConvertComputedPropertyToZeroParameterFunction.self,
    ConvertIfLetToGuard.self,
    ConvertIntegerLiteral.self,
    ConvertJSONToCodableStruct.self,
    ConvertStringConcatenationToStringInterpolation.self,
    ConvertZeroParameterFunctionToComputedProperty.self,
    FormatRawStringLiteral.self,
    MigrateToNewIfLetSyntax.self,
    MoveMembersToExtension.self,
    OpaqueParameterToGeneric.self,
    RemoveSeparatorsFromIntegerLiteral.self,
  ]
  #if !NO_SWIFTPM_DEPENDENCY
  result.append(PackageManifestEdits.self)
  #endif
  return result
}()

let supersededSourcekitdRefactoringActions: Set<String> = [
  "source.refactoring.kind.move.members.to.extension",  // Superseded by MoveMembersToExtension
  "source.refactoring.kind.simplify.long.number.literal",  // Superseded by AddSeparatorsToIntegerLiteral
]
