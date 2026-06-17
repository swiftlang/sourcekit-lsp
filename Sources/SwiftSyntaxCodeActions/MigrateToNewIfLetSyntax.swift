//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftParser
import SwiftRefactor
package import SwiftSyntax

/// ``MigrateToNewIfLetSyntax`` will visit each if expression in the Syntax tree, and
/// checks if there is an if condition which is of the pre Swift 5.7 "if-let-style"
/// and rewrites it to the new one.
///
/// - Seealso: https://github.com/apple/swift-evolution/blob/main/proposals/0345-if-let-shorthand.md
///
/// ## Before
///
/// ```swift
/// if let foo = foo {
///   // ...
/// }
/// ```
///
/// ## After
///
/// ```swift
/// if let foo {
///   // ...
/// }
package struct MigrateToNewIfLetSyntax: SyntaxRefactoringProvider {
  package static func refactor(syntax node: IfExprSyntax, in context: ()) -> IfExprSyntax {
    // Visit all conditions in the node.
    let newConditions = node.conditions.enumerated().map { (index, condition) -> ConditionElementListSyntax.Element in
      var conditionCopy = condition
      // Check if the condition is an optional binding ...
      if var binding = condition.condition.as(OptionalBindingConditionSyntax.self),
        // ... that binds an identifier (and not a tuple) ...
        let bindingIdentifier = binding.pattern.as(IdentifierPatternSyntax.self),
        // ... and has an initializer that is also an identifier ...
        let initializerIdentifier = binding.initializer?.value.as(DeclReferenceExprSyntax.self),
        // ... and both sides of the assignment are the same identifiers.
        bindingIdentifier.identifier.text == initializerIdentifier.baseName.text
      {
        // Remove the initializer ...
        binding.initializer = nil
        // ... and remove whitespace before the comma (in `if` statements with multiple conditions).
        if index != node.conditions.count - 1 {
          binding.pattern = binding.pattern.with(\.trailingTrivia, [])
        }
        conditionCopy.condition = .optionalBinding(binding)
      }
      return conditionCopy
    }
    return node.with(\.conditions, ConditionElementListSyntax(newConditions))
  }
}
