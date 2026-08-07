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

package extension FunctionDeclSyntax {
  /// Returns whether the function matches the syntactic heuristic for an XCTest
  /// test method.
  ///
  /// The heuristic checks that the function:
  /// - Has a name starting with `test` (and is longer than just `test`).
  /// - Takes no parameters.
  /// - Has no return type.
  /// - Is an instance method (not `static` or `class`).
  ///
  /// This intentionally excludes functions with an explicit `Void` return type.
  /// While those are valid XCTest methods, helper functions whose names start
  /// with `test` and return a value are expected to be more common.
  var isXCTestFunction: Bool {
    let name = self.name.text

    guard name.hasPrefix("test"), name.count > 4 else {
      return false
    }

    guard signature.parameterClause.parameters.isEmpty else {
      return false
    }

    guard signature.returnClause == nil else {
      return false
    }

    guard
      !modifiers.contains(where: {
        $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
      })
    else {
      return false
    }

    return true
  }

  /// Returns whether the function matches the XCTest heuristic and is an
  /// immediate member of a class or extension declaration.
  var isSyntacticXCTestMethod: Bool {
    guard isXCTestFunction else { return false }

    guard let memberBlockItem = parent?.as(MemberBlockItemSyntax.self),
      let memberBlockItemList = memberBlockItem.parent?.as(MemberBlockItemListSyntax.self),
      let memberBlock = memberBlockItemList.parent?.as(MemberBlockSyntax.self),
      let parentDecl = memberBlock.parent
    else {
      return false
    }

    return parentDecl.is(ClassDeclSyntax.self) || parentDecl.is(ExtensionDeclSyntax.self)
  }
}
