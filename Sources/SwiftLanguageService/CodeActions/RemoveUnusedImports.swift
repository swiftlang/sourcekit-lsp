//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
import Csourcekitd
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitD
import SourceKitLSP
import SwiftSyntax

// MARK: - Command

struct RemoveUnusedImportsCommand: SwiftCommand {
  static let identifier = "remove.unused.imports.command"
  var title = "Remove Unused Imports"

  let textDocument: TextDocumentIdentifier

  init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }

  init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard
      case .dictionary(let doc)? = dictionary["textDocument"],
      let textDocument = TextDocumentIdentifier(fromLSPDictionary: doc)
    else {
      return nil
    }
    self.textDocument = textDocument
  }

  func encodeToLSPAny() -> LSPAny {
    .dictionary([
      "textDocument": textDocument.encodeToLSPAny()
    ])
  }
}

// MARK: - Code Action Discovery

extension SwiftLanguageService {

  func retrieveRemoveUnusedImportsCodeAction(
    _ request: CodeActionRequest
  ) async throws -> [CodeAction] {

    let snapshot = try await latestSnapshot(for: request.textDocument.uri)
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    // 1. Only offer on import statements
    guard
      let scope = SyntaxCodeActionScope(
        snapshot: snapshot,
        syntaxTree: syntaxTree,
        request: request
      ),
      scope.innermostNodeContainingRange?
        .findParentOfSelf(ofType: ImportDeclSyntax.self, stoppingIf: { _ in false }) != nil
    else {
      return []
    }

    // 2. Require real build settings
    guard
      let buildSettings = await compileCommand(
        for: snapshot.uri,
        fallbackAfterTimeout: true
      ),
      !buildSettings.isFallback
    else {
      return []
    }

    // 3. Require error-free source
    let diagnostics =
      try await diagnosticReportManager
        .diagnosticReport(for: snapshot, buildSettings: buildSettings)

    guard diagnostics.items.allSatisfy({ $0.severity != .error }) else {
      return []
    }

    let command = RemoveUnusedImportsCommand(textDocument: request.textDocument)

    return [
      CodeAction(
        title: command.title,
        kind: .sourceOrganizeImports,
        edit: nil,
        command: command.asCommand()
      )
    ]
  }
}

// MARK: - Helper Functions

/// Recursively collects all import declarations from a syntax tree, including those inside #if clauses
private func collectAllImports(from node: Syntax) -> [ImportDeclSyntax] {
  var imports: [ImportDeclSyntax] = []
  
  // If this node is an import declaration, add it
  if let importDecl = node.as(ImportDeclSyntax.self) {
    imports.append(importDecl)
  }
  
  // Recursively search through all child nodes
  for child in node.children(viewMode: .sourceAccurate) {
    imports.append(contentsOf: collectAllImports(from: child))
  }
  
  return imports
}

/// Overload for SourceFileSyntax
private func collectAllImports(from sourceFile: SourceFileSyntax) -> [ImportDeclSyntax] {
  return collectAllImports(from: Syntax(sourceFile))
}

// MARK: - Command Execution

extension SwiftLanguageService {

  func removeUnusedImports(
    _ command: RemoveUnusedImportsCommand
  ) async throws {

    let snapshot = try await latestSnapshot(for: command.textDocument.uri)
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    guard let compileCommand = await compileCommand(
      for: snapshot.uri,
      fallbackAfterTimeout: false
    ) else {
      throw ResponseError.unknown("No build settings")
    }

    // Temporary document URI
    let tempURI = DocumentURI(
      filePath: "/sourcekit-lsp-remove-unused-imports/\(UUID().uuidString).swift",
      isDirectory: false
    )

    let patchedCompileCommand = SwiftCompileCommand(
      FileBuildSettings(
        compilerArguments: compileCommand.compilerArgs,
        language: .swift,
        isFallback: false
      ).patching(newFile: tempURI, originalFile: snapshot.uri)
    )

    // Open temp document
    let open = openDocumentSourcekitdRequest(
      snapshot: snapshot,
      compileCommand: patchedCompileCommand
    )
    open.set(sourcekitd.keys.name, to: tempURI.pseudoPath)

    _ = try await send(
      sourcekitdRequest: \.editorOpen,
      open,
      snapshot: nil
    )

    defer {
      let close = closeDocumentSourcekitdRequest(uri: tempURI)
      Task {
        _ = try? await self.send(
          sourcekitdRequest: \.editorClose,
          close,
          snapshot: nil
        )
      }
    }

    // Collect all imports (including those inside #if clauses)
    let importDecls = collectAllImports(from: syntaxTree)

    var removable: [ImportDeclSyntax] = []
    let keys = sourcekitd.keys
    let values = sourcekitd.values

    for importDecl in importDecls.reversed() {
      let start = snapshot.utf8Offset(
        of: snapshot.position(of: importDecl.position)
      )
      let end = snapshot.utf8Offset(
        of: snapshot.position(of: importDecl.endPosition)
      )

      let removeReq = sourcekitd.dictionary([
        keys.name: tempURI.pseudoPath,
        keys.offset: start,
        keys.length: end - start,
        keys.sourceText: "",
        keys.syntacticOnly: 1
      ])

      _ = try await send(
        sourcekitdRequest: \.editorReplaceText,
        removeReq,
        snapshot: nil
      )

      let diagnostics = try await send(
        sourcekitdRequest: \.diagnostics,
        sourcekitd.dictionary([
          keys.sourceFile: tempURI.pseudoPath,
          keys.compilerArgs: patchedCompileCommand.compilerArgs as [any SKDRequestValue],
        ]),
        snapshot: nil
      )

      var hasError = false
      if let diagnosticArray = diagnostics[keys.diagnostics] as SKDResponseArray? {
        diagnosticArray.forEach { (_, diag) -> Bool in
          if let severity = diag[keys.severity] as sourcekitd_api_uid_t?,
             severity == values.diagError {
            hasError = true
            return false
          }
          return true
        }
      }

      if hasError {
        // Revert removal
        let revertReq = sourcekitd.dictionary([
          keys.name: tempURI.pseudoPath,
          keys.offset: start,
          keys.length: 0,
          keys.sourceText: importDecl.description,
          keys.syntacticOnly: 1
        ])

        _ = try await send(
          sourcekitdRequest: \.editorReplaceText,
          revertReq,
          snapshot: nil
        )
      } else {
        removable.append(importDecl)
      }
    }

    guard let server = sourceKitLSPServer else { return }

    let edits = removable.reversed().map {
      TextEdit(range: snapshot.range(of: $0), newText: "")
    }

    _ = try await server.sendRequestToClient(
      ApplyEditRequest(
        edit: WorkspaceEdit(changes: [snapshot.uri: edits])
      )
    )
  }
}
