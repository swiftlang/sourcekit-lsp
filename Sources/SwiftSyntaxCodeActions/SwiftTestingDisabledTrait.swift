//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

package extension FunctionCallExprSyntax {
  var isSwiftTestingDisabledTrait: Bool {
    guard let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
      memberAccess.declName.baseName.text == "disabled"
    else {
      return false
    }

    guard let base = memberAccess.base else {
      return true
    }

    if let declRef = base.as(DeclReferenceExprSyntax.self) {
      return declRef.baseName.text == "ConditionTrait"
    }

    if let baseMemberAccess = base.as(MemberAccessExprSyntax.self),
      baseMemberAccess.declName.baseName.text == "ConditionTrait",
      let moduleRef = baseMemberAccess.base?.as(DeclReferenceExprSyntax.self)
    {
      return moduleRef.baseName.text == "Testing"
    }

    return false
  }

  var isSwiftTestingConditionalDisabledTrait: Bool {
    guard isSwiftTestingDisabledTrait else {
      return false
    }

    if trailingClosure != nil {
      return true
    }

    return arguments.lazy
      .compactMap(\.label?.text)
      .contains("if")
  }

  var isSwiftTestingUnconditionalDisabledTrait: Bool {
    isSwiftTestingDisabledTrait && !isSwiftTestingConditionalDisabledTrait
  }
}
