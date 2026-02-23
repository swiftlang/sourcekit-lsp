//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
import Csourcekitd
import Foundation
package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

/// The remove unused imports command tries to remove unnecessary imports in a file on a best-effort basis by deleting
/// imports in reverse source order and seeing if the file still builds. Note that while this works in most cases, there
/// are a few edge cases, in which this isn't correct. We decided that those are rare enough that the benefits of the
/// refactoring action outweigh these potential issues.
///
/// ### 1. Overload resolution changing
///
/// LibA.swift
/// ```swift
/// func foo(_ x: Int) -> Int { "Wrong" }
/// ```
///
/// LibB.swift
/// ```swift
/// func foo(_ x: Double) -> Int { "Correct" }
/// ```
///
/// Test.swift
/// ```swift
/// import LibA
/// import LibB
///
/// print(foo(1.2))
/// ```
///
/// The action will remove the import to LibB because the code still compiles fine without it (we now pick the
/// `foo(_:Int)` overload instead of `foo(_:Double)`). This seems pretty unlikely though.
///
/// ### 2. Loaded extension used by other source file
///
/// Importing a module in this file might make members and conformances available to other source files as well, so just
/// checking the current source file for issues is not technically enough. The former of those issues is fixed by the
/// upcoming `MemberImportVisibility` language feature and importing a module and only using a conformance from it in a
/// different file seems pretty unlikely.
package struct RemoveUnusedImportsCommand: SwiftCommand {
  package static let identifier: String = "remove.unused.imports.command"
  package var title: String = "Remove Unused Imports"

  /// The text document related to the refactoring action.
  package var textDocument: TextDocumentIdentifier

  internal init(textDocument: TextDocumentIdentifier) {
    self.textDocument = textDocument
  }

  package init?(fromLSPDictionary dictionary: [String: LanguageServerProtocol.LSPAny]) {
    guard case .dictionary(let documentDict)? = dictionary[CodingKeys.textDocument.stringValue] else {
      return nil
    }
    guard let textDocument = TextDocumentIdentifier(fromLSPDictionary: documentDict) else {
      return nil
    }

    self.init(
      textDocument: textDocument
    )
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.textDocument.stringValue: textDocument.encodeToLSPAny()
    ])
  }
}

extension SwiftLanguageService {
  func retrieveRemoveUnusedImportsCodeAction(_ request: CodeActionRequest) async throws -> [CodeAction] {
    let snapshot = try await self.latestSnapshot(for: request.textDocument.uri)

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    guard
      let node = SyntaxCodeActionScope(snapshot: snapshot, syntaxTree: syntaxTree, request: request)?
        .innermostNodeContainingRange,
      node.findParentOfSelf(ofType: ImportDeclSyntax.self, stoppingIf: { _ in false }) != nil
    else {
      // Only offer the remove unused imports code action on an import statement.
      return []
    }

    guard
      let buildSettings = await self.compileCommand(for: request.textDocument.uri, fallbackAfterTimeout: true),
      !buildSettings.isFallback,
      try await !diagnosticReportManager.diagnosticReport(for: snapshot, buildSettings: buildSettings).items
        .contains(where: { $0.severity == .error })
    else {
      // If the source file contains errors, we can't remove unused imports because we can't tell if removing import
      // decls would introduce an error in the source file.
      return []
    }

    let command = RemoveUnusedImportsCommand(textDocument: request.textDocument)
    return [
      CodeAction(
        title: command.title,
        kind: .sourceOrganizeImports,
        diagnostics: nil,
        edit: nil,
        command: command.asCommand()
      )
    ]
  }

  private final class ImportCollector: SyntaxVisitor {
    var imports: [ImportDeclSyntax] = []

    init() {
      super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
      imports.append(node)
      return .skipChildren
    }
  }

  func removeUnusedImports(_ command: RemoveUnusedImportsCommand) async throws {
    let snapshot = try await self.latestSnapshot(for: command.textDocument.uri)
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    guard let compileCommand = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false) else {
      throw ResponseError.unknown(
        "Cannot remove unused imports because the build settings for the file could not be determined"
      )
    }

    // We need to fake a file path instead of some other URI scheme because the sourcekitd diagnostics request complains
    // that the source file is not part of the input files for arbitrary scheme URLs.
    // https://github.com/swiftlang/swift/issues/85003
    #if os(Windows)
    let temporaryDocUri = DocumentURI(
      filePath: #"C:\sourcekit-lsp-remove-unused-imports\\#(UUID().uuidString).swift"#,
      isDirectory: false
    )
    #else
    let temporaryDocUri = DocumentURI(
      filePath: "/sourcekit-lsp-remove-unused-imports/\(UUID().uuidString).swift",
      isDirectory: false
    )
    #endif
    let patchedCompileCommand = SwiftCompileCommand(
      FileBuildSettings(
        compilerArguments: compileCommand.compilerArgs,
        language: .swift,
        isFallback: compileCommand.isFallback
      )
      .patching(newFile: temporaryDocUri, originalFile: snapshot.uri)
    )

    func temporaryDocumentHasErrorDiagnostic() async throws -> Bool {
      let response = try await self.send(
        sourcekitdRequest: \.diagnostics,
        sourcekitd.dictionary([
          keys.sourceFile: temporaryDocUri.pseudoPath,
          keys.compilerArgs: patchedCompileCommand.compilerArgs as [any SKDRequestValue],
        ]),
        snapshot: nil
      )
      guard let diagnostics = (response[sourcekitd.keys.diagnostics] as SKDResponseArray?) else {
        return true
      }
      // swift-format-ignore: ReplaceForEachWithForLoop
      // Reference is to `SKDResponseArray.forEach`, not `Array.forEach`.
      let hasErrorDiagnostic = !diagnostics.forEach { _, diagnostic in
        switch diagnostic[sourcekitd.keys.severity] as sourcekitd_api_uid_t? {
        case sourcekitd.values.diagError: return false
        case sourcekitd.values.diagWarning: return true
        case sourcekitd.values.diagNote: return true
        case sourcekitd.values.diagRemark: return true
        default: return false
        }
      }

      return hasErrorDiagnostic
    }

    let openRequest = openDocumentSourcekitdRequest(snapshot: snapshot, compileCommand: patchedCompileCommand)
    openRequest.set(sourcekitd.keys.name, to: temporaryDocUri.pseudoPath)
    _ = try await self.send(
      sourcekitdRequest: \.editorOpen,
      openRequest,
      snapshot: nil
    )

    return try await run {
      guard try await !temporaryDocumentHasErrorDiagnostic() else {
        // If the source file has errors to start with, we can't check if removing an import declaration would introduce
        // a new error, give up. This really shouldn't happen anyway because the remove unused imports code action is
        // only offered if the source file is free of error.
        throw ResponseError.unknown("Failed to remove unused imports because the document currently contains errors")
      }

      // Only consider import declarations at the top level and ignore ones eg. inside `#if` clauses since those might
      // be inactive in the current build configuration and thus we can't reliably check if they are needed.
      let collector = ImportCollector()
      collector.walk(syntaxTree)
      let importDecls = collector.imports

      var declsToRemove: [ImportDeclSyntax] = []

      // Try removing the import decls and see if the file still compiles without syntax errors. Do this in reverse
      // order of the import declarations so we don't need to adjust offsets of the import decls as we iterate through
      // them.
      for importDecl in importDecls.reversed() {
        let startOffset = snapshot.utf8Offset(of: snapshot.position(of: importDecl.position))
        let endOffset = snapshot.utf8Offset(of: snapshot.position(of: importDecl.endPosition))
        let removeImportReq = sourcekitd.dictionary([
          keys.name: temporaryDocUri.pseudoPath,
          keys.enableSyntaxMap: 0,
          keys.enableStructure: 0,
          keys.enableDiagnostics: 0,
          keys.syntacticOnly: 1,
          keys.offset: startOffset,
          keys.length: endOffset - startOffset,
          keys.sourceText: "",
        ])

        _ = try await self.send(sourcekitdRequest: \.editorReplaceText, removeImportReq, snapshot: nil)

        if try await temporaryDocumentHasErrorDiagnostic() {
          // The file now has syntax error where it didn't before. Add the import decl back in again.
          let addImportReq = sourcekitd.dictionary([
            keys.name: temporaryDocUri.pseudoPath,
            keys.enableSyntaxMap: 0,
            keys.enableStructure: 0,
            keys.enableDiagnostics: 0,
            keys.syntacticOnly: 1,
            keys.offset: startOffset,
            keys.length: 0,
            keys.sourceText: importDecl.description,
          ])
          _ = try await self.send(sourcekitdRequest: \.editorReplaceText, addImportReq, snapshot: nil)

          continue
        }

        declsToRemove.append(importDecl)
      }

      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }

      let edits = declsToRemove.reversed().map { importDecl in
        var range = snapshot.range(of: importDecl)

        let isAtStartOfFile = importDecl.previousToken(viewMode: .sourceAccurate) == nil

        if isAtStartOfFile {
          // If this is at the start of the source file, keep its leading trivia since we should consider those as a
          // file header instead of belonging to the import decl.
          range = snapshot.position(of: importDecl.positionAfterSkippingLeadingTrivia)..<range.upperBound
        }

        // If we are removing the first import statement in the file and it is followed by a newline (which will belong
        // to the next token), remove that newline as well so we are not left with an empty line at the start of the
        // source file.
        if isAtStartOfFile,
          let nextToken = importDecl.nextToken(viewMode: .sourceAccurate),
          nextToken.leadingTrivia.first?.isNewline ?? false
        {
          let nextTokenWillBeRemoved =
            nextToken.ancestorOrSelf(mapping: { (node) -> Syntax? in
              guard let importDecl = node.as(ImportDeclSyntax.self), declsToRemove.contains(importDecl) else {
                return nil
              }
              return node
            }) != nil
          if !nextTokenWillBeRemoved {
            range = range.lowerBound..<snapshot.position(of: nextToken.position.advanced(by: 1))
          }
        }

        return TextEdit(range: range, newText: "")
      }
      let applyResponse = try await sourceKitLSPServer.sendRequestToClient(
        ApplyEditRequest(
          edit: WorkspaceEdit(
            changes: [snapshot.uri: edits]
          )
        )
      )
      if !applyResponse.applied {
        let reason: String
        if let failureReason = applyResponse.failureReason {
          reason = " reason: \(failureReason)"
        } else {
          reason = ""
        }
        logger.error("client refused to apply edit for removing unused imports: \(reason)")
      }
    } cleanup: {
      let req = closeDocumentSourcekitdRequest(uri: temporaryDocUri)
      await orLog("Closing temporary sourcekitd document to remove unused imports") {
        _ = try await self.send(sourcekitdRequest: \.editorClose, req, snapshot: nil)
      }
    }
  }
}
