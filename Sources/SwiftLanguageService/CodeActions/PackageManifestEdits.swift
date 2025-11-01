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

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftParser
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax

/// Syntactic code action provider to provide refactoring actions that
/// edit a package manifest.
struct PackageManifestEdits: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    guard let call = scope.innermostNodeContainingRange?.findEnclosingCall() else {
      return []
    }

    return addTargetActions(call: call, in: scope) + addTestTargetActions(call: call, in: scope)
      + addProductActions(call: call, in: scope)
  }

  /// Produce code actions to add new targets of various kinds.
  static func addTargetActions(
    call: FunctionCallExprSyntax,
    in scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    do {
      var actions: [CodeAction] = []
      let variants: [(PackageTarget.TargetKind, String)] = [
        (.library, "library"),
        (.executable, "executable"),
        (.macro, "macro"),
      ]

      for (type, name) in variants {
        let target = PackageTarget(
          name: "NewTarget",
          type: type
        )

        guard
          let edit = try AddPackageTarget.textRefactor(
            syntax: scope.file,
            in: .init(target: target)
          ).asWorkspaceEdit(snapshot: scope.snapshot)
        else {
          continue
        }

        actions.append(
          CodeAction(
            title: "Add \(name) target",
            kind: .refactor,
            edit: edit
          )
        )
      }

      return actions
    } catch {
      return []
    }
  }

  /// Produce code actions to add test target(s) if we are currently on
  /// a target for which we know how to create a test.
  static func addTestTargetActions(
    call: FunctionCallExprSyntax,
    in scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    guard let calledMember = call.findMemberAccessCallee(),
      targetsThatAllowTests.contains(calledMember),
      let targetName = call.findStringArgument(label: "name")
    else {
      return []
    }

    do {
      var actions: [CodeAction] = []

      let variants: [(AddPackageTarget.TestHarness, String)] = [
        (.swiftTesting, "Swift Testing"),
        (.xctest, "XCTest"),
      ]
      for (testingLibrary, libraryName) in variants {
        // Describe the target we are going to create.
        let target = PackageTarget(
          name: "\(targetName)Tests",
          type: .test,
          dependencies: [.byName(name: targetName)],
        )

        guard
          let edit = try AddPackageTarget.textRefactor(
            syntax: scope.file,
            in: .init(target: target, testHarness: testingLibrary)
          ).asWorkspaceEdit(snapshot: scope.snapshot)
        else {
          continue
        }

        actions.append(
          CodeAction(
            title: "Add test target (\(libraryName))",
            kind: .refactor,
            edit: edit
          )
        )
      }

      return actions
    } catch {
      return []
    }
  }

  /// A list of target kinds that allow the creation of tests.
  static let targetsThatAllowTests: [String] = [
    "executableTarget",
    "macro",
    "target",
  ]

  /// Produce code actions to add a product if we are currently on
  /// a target for which we can create a product.
  static func addProductActions(
    call: FunctionCallExprSyntax,
    in scope: SyntaxCodeActionScope
  ) -> [CodeAction] {
    guard let calledMember = call.findMemberAccessCallee(),
      targetsThatAllowProducts.contains(calledMember),
      let targetName = call.findStringArgument(label: "name")
    else {
      return []
    }

    do {
      let type: ProductDescription.ProductType =
        calledMember == "executableTarget"
        ? .executable
        : .library(.automatic)

      // Describe the target we are going to create.
      let product = ProductDescription(
        name: targetName,
        type: type,
        targets: [targetName]
      )

      guard
        let edit = try AddProduct.textRefactor(
          syntax: scope.file,
          in: .init(product: product)
        ).asWorkspaceEdit(snapshot: scope.snapshot)
      else {
        return []
      }

      return [
        CodeAction(
          title: "Add product to export this target",
          kind: .refactor,
          edit: edit
        )
      ]
    } catch {
      return []
    }
  }

  /// A list of target kinds that allow the creation of tests.
  static let targetsThatAllowProducts: [String] = [
    "executableTarget",
    "target",
  ]
}

fileprivate extension SyntaxProtocol {
  // Find an enclosing call syntax expression.
  func findEnclosingCall() -> FunctionCallExprSyntax? {
    var current = Syntax(self)
    while true {
      if let call = current.as(FunctionCallExprSyntax.self) {
        return call
      }

      if let parent = current.parent {
        current = parent
        continue
      }

      return nil
    }
  }
}

fileprivate extension FunctionCallExprSyntax {
  /// Find an argument with the given label that has a string literal as
  /// its argument.
  func findStringArgument(label: String) -> String? {
    for arg in arguments {
      if arg.label?.text == label {
        return arg.expression.as(StringLiteralExprSyntax.self)?
          .representedLiteralValue
      }
    }

    return nil
  }

  /// Find the callee when it is a member access expression referencing
  /// a declaration when a specific name.
  func findMemberAccessCallee() -> String? {
    guard
      let memberAccess = self.calledExpression
        .as(MemberAccessExprSyntax.self)
    else {
      return nil
    }

    return memberAccess.declName.baseName.text
  }
}
