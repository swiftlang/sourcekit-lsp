//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring

/// General information about the code completion
struct CompletionContext {
  let kind: CompletionContext.Kind
  let memberAccessTypes: [String]
  let baseExprScope: PopularityIndex.Scope?

  init(kind: CompletionContext.Kind, memberAccessTypes: [String], baseExprScope: PopularityIndex.Scope?) {
    self.kind = kind
    self.memberAccessTypes = memberAccessTypes
    self.baseExprScope = baseExprScope
  }

  enum Kind {
    case none
    case `import`
    case unresolvedMember
    case dotExpr
    case stmtOrExpr
    case postfixExprBeginning
    case postfixExpr
    case postfixExprParen
    case keyPathExprObjC
    case keyPathExprSwift
    case typeDeclResultBeginning
    case typeSimpleBeginning
    case typeIdentifierWithDot
    case typeIdentifierWithoutDot
    case caseStmtKeyword
    case caseStmtBeginning
    case nominalMemberBeginning
    case accessorBeginning
    case attributeBegin
    case attributeDeclParen
    case poundAvailablePlatform
    case callArg
    case labeledTrailingClosure
    case returnStmtExpr
    case yieldStmtExpr
    case forEachSequence
    case afterPoundExpr
    case afterPoundDirective
    case platformConditon
    case afterIfStmtElse
    case genericRequirement
    case precedenceGroup
    case stmtLabel
    case effectsSpecifier
    case forEachPatternBeginning
    case typeAttrBeginning
    case optionalBinding
    case forEachKeywordIn
    case thenStmtExpr
  }
}
