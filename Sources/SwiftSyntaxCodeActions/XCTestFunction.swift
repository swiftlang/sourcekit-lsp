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
      let kind = $0.name.tokenKind
      return kind == .keyword(.static) || kind == .keyword(.class)
    }) else {
      return false
    }

    return true
  }
}
