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
  enum SemanticContext {
    /// Used in cases when the concept of semantic context is not applicable.
    case none

    /// A declaration from the same function.
    case local

    /// A declaration found in the immediately enclosing nominal decl.
    case currentNominal

    /// A declaration found in the superclass of the immediately enclosing
    /// nominal decl.
    case `super`

    /// A declaration found in the non-immediately enclosing nominal decl.
    ///
    /// For example, 'Foo' is visible at (1) because of this.
    /// ```
    ///   struct A {
    ///     typealias Foo = Int
    ///     struct B {
    ///       func foo() {
    ///         // (1)
    ///       }
    ///     }
    ///   }
    /// ```
    case outsideNominal

    /// A declaration from the current module.
    case currentModule

    /// A declaration imported from other module.
    case otherModule
  }
}
