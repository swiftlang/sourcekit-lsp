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

extension FunctionDeclSyntax {
  package var isXCTestFunction: Bool {
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

    guard !modifiers.contains(where: {
      $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
    }) else {
      return false
    }

    return true
  }

  package var isSyntacticXCTestMethod: Bool {
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
