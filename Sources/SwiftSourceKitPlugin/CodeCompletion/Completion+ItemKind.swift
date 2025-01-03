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

extension CompletionItem {
  enum ItemKind {
    // Decls
    case module
    case `class`
    case actor
    case `struct`
    case `enum`
    case enumElement
    case `protocol`
    case associatedType
    case typeAlias
    case genericTypeParam
    case constructor
    case destructor
    case `subscript`
    case staticMethod
    case instanceMethod
    case prefixOperatorFunction
    case postfixOperatorFunction
    case infixOperatorFunction
    case freeFunction
    case staticVar
    case instanceVar
    case localVar
    case globalVar
    case precedenceGroup
    // Other
    case keyword
    case `operator`
    case literal
    case pattern
    case macro
    case unknown
  }
}
