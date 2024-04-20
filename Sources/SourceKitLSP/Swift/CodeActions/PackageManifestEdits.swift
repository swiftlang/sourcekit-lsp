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
    guard
      let token = scope.firstToken,
      let call = token.findEnclosingCall()
    else {
      return []
    }

    var actions = [CodeAction]()

    // If there's a target name, offer to create a test target derived from it.
    if let targetName = call.findStringArgument(label: "name") {
        do {
            let target = try TargetDescription(
                name: "\(targetName)Tests",
                dependencies: [ .byName(name: targetName, condition: nil) ],
                type: .test
            )

            let edits = try AddTarget.addTarget(target, to: scope.file)
            actions.append(
              CodeAction(
                title: "Add test target for this target",
                kind: .refactor,
                edit: edits.asWorkspaceEdit(snapshot: scope.snapshot)
              )
            )
        } catch {
            // nothing to do
        }
    }

    return actions
  }
}

fileprivate extension PackageEditResult {
    /// Translate package manifest edits into a workspace edit. This can
    /// involve both modifications to the manifest file as well as the creation
    /// of new files.
    func asWorkspaceEdit(snapshot: DocumentSnapshot) -> WorkspaceEdit {
        // The edits to perform on the manifest itself.
        let manifestTextEdits = manifestEdits.map { edit in
            TextEdit(
                range: snapshot.range(of: edit.range),
                newText: edit.replacement
            )
        }

        // If we couldn't figure out the manifest directory, or there are no
        // files to add, the only changes are the manifest edits. We're done
        // here.
        let manifestDirectoryURI = snapshot.uri.fileURL?
            .deletingLastPathComponent()
        guard let manifestDirectoryURI, !auxiliaryFiles.isEmpty else {
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
                .init(
                    textDocument: .init(snapshot.uri, version: nil),
                    edits: manifestTextEdits.map { .textEdit($0) }
                )
            )
        )

        // Create an populate all of the auxiliary files.
        for (relativePath, contents) in auxiliaryFiles {
            guard let uri = URL(
                string: relativePath.pathString,
                relativeTo: manifestDirectoryURI
            ) else {
                continue
            }

            let documentURI = DocumentURI(uri)
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
                    .init(
                        textDocument: .init(documentURI, version: nil),
                        edits: [ .textEdit(edit) ]
                    )
                )
            )
        }

        return WorkspaceEdit(
            changes: [ snapshot.uri: manifestTextEdits ],
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
}
