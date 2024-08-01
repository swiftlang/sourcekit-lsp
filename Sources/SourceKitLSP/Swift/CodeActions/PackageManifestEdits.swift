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

import LanguageServerProtocol
import PackageModel
import PackageModelSyntax
import SwiftRefactor
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
      let variants: [(TargetDescription.TargetKind, String)] = [
        (.regular, "library"),
        (.executable, "executable"),
        (.macro, "macro"),
      ]

      for (type, name) in variants {
        let target = try TargetDescription(
          name: "NewTarget",
          type: type
        )

        let edits = try AddTarget.addTarget(
          target,
          to: scope.file
        )

        actions.append(
          CodeAction(
            title: "Add \(name) target",
            kind: .refactor,
            edit: edits.asWorkspaceEdit(snapshot: scope.snapshot)
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

      let variants: [(AddTarget.TestHarness, String)] = [
        (.swiftTesting, "Swift Testing"),
        (.xctest, "XCTest"),
      ]
      for (testingLibrary, libraryName) in variants {
        // Describe the target we are going to create.
        let target = try TargetDescription(
          name: "\(targetName)Tests",
          dependencies: [.byName(name: targetName, condition: nil)],
          type: .test
        )

        let edits = try AddTarget.addTarget(
          target,
          to: scope.file,
          configuration: .init(testHarness: testingLibrary)
        )

        actions.append(
          CodeAction(
            title: "Add test target (\(libraryName))",
            kind: .refactor,
            edit: edits.asWorkspaceEdit(snapshot: scope.snapshot)
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
      let type: ProductType =
        calledMember == "executableTarget"
        ? .executable
        : .library(.automatic)

      // Describe the target we are going to create.
      let product = try ProductDescription(
        name: targetName,
        type: type,
        targets: [targetName]
      )

      let edits = try AddProduct.addProduct(product, to: scope.file)
      return [
        CodeAction(
          title: "Add product to export this target",
          kind: .refactor,
          edit: edits.asWorkspaceEdit(snapshot: scope.snapshot)
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

fileprivate extension PackageEditResult {
  /// Translate package manifest edits into a workspace edit. This can
  /// involve both modifications to the manifest file as well as the creation
  /// of new files.
  /// `snapshot` is the latest snapshot of the `Package.swift` file.
  func asWorkspaceEdit(snapshot: DocumentSnapshot) -> WorkspaceEdit {
    // The edits to perform on the manifest itself.
    let manifestTextEdits = manifestEdits.map { edit in
      TextEdit(
        range: snapshot.absolutePositionRange(of: edit.range),
        newText: edit.replacement
      )
    }

    // If we couldn't figure out the manifest directory, or there are no
    // files to add, the only changes are the manifest edits. We're done
    // here.
    let manifestDirectoryURL = snapshot.uri.fileURL?
      .deletingLastPathComponent()
    guard let manifestDirectoryURL, !auxiliaryFiles.isEmpty else {
      return WorkspaceEdit(
        changes: [snapshot.uri: manifestTextEdits]
      )
    }

    // Use the more full-featured documentChanges, which takes precedence
    // over the individual changes to documents.
    var documentChanges: [WorkspaceEditDocumentChange] = []

    // Put the manifest changes into the array.
    documentChanges.append(
      .textDocumentEdit(
        TextDocumentEdit(
          textDocument: .init(snapshot.uri, version: snapshot.version),
          edits: manifestTextEdits.map { .textEdit($0) }
        )
      )
    )

    // Create an populate all of the auxiliary files.
    for (relativePath, contents) in auxiliaryFiles {
      guard
        let url = URL(
          string: relativePath.pathString,
          relativeTo: manifestDirectoryURL
        )
      else {
        continue
      }

      let documentURI = DocumentURI(url)
      let createFile = CreateFile(
        uri: documentURI
      )

      let zeroPosition = Position(line: 0, utf16index: 0)
      let edit = TextEdit(
        range: zeroPosition..<zeroPosition,
        newText: contents.description
      )

      documentChanges.append(.createFile(createFile))
      documentChanges.append(
        .textDocumentEdit(
          TextDocumentEdit(
            textDocument: .init(documentURI, version: snapshot.version),
            edits: [.textEdit(edit)]
          )
        )
      )
    }

    return WorkspaceEdit(
      changes: [snapshot.uri: manifestTextEdits],
      documentChanges: documentChanges
    )
  }
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
