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

package enum SwiftTestingDisabledTrait {
  case none
  case disabled
  case conditionallyDisabled
}

extension FunctionCallExprSyntax {
  package var swiftTestingDisabledTrait: SwiftTestingDisabledTrait {
    guard let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
      memberAccess.declName.baseName.text == "disabled"
    else {
      return .none
    }

    let isValidBase: Bool = {
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
    }()

    guard isValidBase else {
      return .none
    }

    let isConditional = trailingClosure != nil || arguments.lazy
      .compactMap(\.label?.text)
      .contains("if")

    return isConditional ? .conditionallyDisabled : .disabled
  }
}
