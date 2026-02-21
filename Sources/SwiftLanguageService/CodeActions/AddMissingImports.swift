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

internal import BuildServerIntegration
import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
@_spi(SourceKitLSP) package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax

/// Command that defers the actual import insertion to execution time.
package struct AddMissingImportsCommand: SwiftCommand {
  package static let identifier = "sourcekit-lsp.add.missing.import"
  package var title: String

  /// The text document to add the import to.
  package var textDocument: TextDocumentIdentifier

  /// The module name to import.
  package var moduleName: String

  private enum CodingKeys: String, CodingKey {
    case textDocument, moduleName, title
  }

  internal init(title: String, textDocument: TextDocumentIdentifier, moduleName: String) {
    self.title = title
    self.textDocument = textDocument
    self.moduleName = moduleName
  }

  package init?(fromLSPDictionary dictionary: [String: LanguageServerProtocol.LSPAny]) {
    guard case .string(let title)? = dictionary[CodingKeys.title.stringValue] else {
      return nil
    }
    guard case .dictionary(let documentDict)? = dictionary[CodingKeys.textDocument.stringValue] else {
      return nil
    }
    guard let textDocument = TextDocumentIdentifier(fromLSPDictionary: documentDict) else {
      return nil
    }
    guard case .string(let moduleName)? = dictionary[CodingKeys.moduleName.stringValue] else {
      return nil
    }
    self.init(title: title, textDocument: textDocument, moduleName: moduleName)
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.title.stringValue: .string(title),
      CodingKeys.textDocument.stringValue: textDocument.encodeToLSPAny(),
      CodingKeys.moduleName.stringValue: .string(moduleName),
    ])
  }
}

extension SwiftLanguageService {
  /// Retrieves code actions to add missing imports for unresolved symbols.
  ///
  /// This is the initial code action request handler. It identifies which modules
  /// define missing symbols and returns commands for each candidate. The actual
  /// import insertion is deferred to `executeAddMissingImport`.
  package func addMissingImports(_ request: CodeActionRequest) async throws -> [CodeAction] {
    // Early exit if no relevant diagnostics
    let relevantDiagnostics = request.context.diagnostics.filter(AddMissingImportsHelper.isMissingTypeOrValueDiagnostic)
    guard !relevantDiagnostics.isEmpty else { return [] }

    guard let buildSettings = await self.compileCommand(for: request.textDocument.uri, fallbackAfterTimeout: true),
      !buildSettings.isFallback
    else {
      return []
    }

    guard
      let workspace = await self.sourceKitLSPServer?.workspaceForDocument(uri: request.textDocument.uri),
      let index = await workspace.index(checkedFor: .modifiedFiles)
    else {
      return []
    }

    let snapshot = try await self.latestSnapshot(for: request.textDocument.uri)
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    // Only consider unconditional module imports
    let existingImports = Set(
      syntaxTree.statements
        .compactMap { $0.item.as(ImportDeclSyntax.self) }
        .filter { $0.importKindSpecifier == nil && $0.path.count == 1 }
        .compactMap { $0.path.first?.name.text }
    )

    var currentModule: String? = nil
    if let canonicalTarget = await workspace.buildServerManager.canonicalTarget(for: request.textDocument.uri) {
      currentModule = await workspace.buildServerManager.moduleName(for: request.textDocument.uri, in: canonicalTarget)
    }

    var codeActions: [CodeAction] = []

    for diagnostic in relevantDiagnostics {
      guard let symbolName = AddMissingImportsHelper.extractSymbolName(from: diagnostic.message) else {
        continue
      }

      let candidateModules = AddMissingImportsHelper.findModulesDefining(symbolName, in: index)
        .filter { !existingImports.contains($0) && $0 != currentModule }
        .sorted()

      for moduleName in candidateModules {
        let command = AddMissingImportsCommand(
          title: "Import \(moduleName)",
          textDocument: request.textDocument,
          moduleName: moduleName
        )
        codeActions.append(
          CodeAction(
            title: command.title,
            kind: .quickFix,
            diagnostics: [diagnostic],
            edit: nil,
            command: command.asCommand()
          )
        )
      }
    }

    return codeActions
  }

  /// Executes the add missing import command.
  ///
  /// Called when the user selects the code action. Computes the insertion position
  /// and applies the import edit to the document.
  func executeAddMissingImport(_ command: AddMissingImportsCommand) async throws {
    let snapshot = try await self.latestSnapshot(for: command.textDocument.uri)
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    let allImportDecls = syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
    let insertPosition = AddMissingImportsHelper.importInsertionPosition(
      for: command.moduleName,
      in: syntaxTree,
      snapshot: snapshot
    )

    // Determine import text based on insertion position:
    // - If inserting at end of last import: prepend newline
    // - Otherwise (before import or no imports): append newline
    let lastImportEnd = allImportDecls.last.map { snapshot.position(of: $0.endPosition) }
    let importText =
      if lastImportEnd == insertPosition {
        "\nimport \(command.moduleName)"
      } else {
        "import \(command.moduleName)\n"
      }

    guard let sourceKitLSPServer else {
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let applyResponse = try await sourceKitLSPServer.sendRequestToClient(
      ApplyEditRequest(
        edit: WorkspaceEdit(
          changes: [snapshot.uri: [TextEdit(range: insertPosition..<insertPosition, newText: importText)]]
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
      logger.error("client refused to apply edit for adding import: \(reason)")
    }
  }
}

/// Helper enum providing static functions for the add missing imports refactoring.
private enum AddMissingImportsHelper {

  /// Diagnostic codes that indicate a missing type or value.
  private static let missingSymbolDiagnosticCodes: Set<String> = [
    "cannot_find_type_in_scope",
    "cannot_find_in_scope",
    "cannot_find_type_in_scope_did_you_mean",
    "cannot_find_in_scope_corrected",
  ]

  /// Regex pattern for extracting type/symbol name from diagnostic messages.
  nonisolated(unsafe) private static let symbolNameRegex = /[Cc]annot find (?:type )?'(\w+)' in scope/

  /// Extracts the symbol name from a diagnostic message using regex.
  static func extractSymbolName(from message: String) -> String? {
    guard let match = message.firstMatch(of: symbolNameRegex) else {
      return nil
    }
    return String(match.output.1)
  }

  /// Checks if a diagnostic indicates a missing type or value in scope.
  static func isMissingTypeOrValueDiagnostic(_ diagnostic: Diagnostic) -> Bool {
    guard let code = diagnostic.codeString else {
      return false
    }
    return missingSymbolDiagnosticCodes.contains(code)
  }

  /// Finds all modules that define a given symbol by querying the semantic index.
  static func findModulesDefining(_ symbolName: String, in index: CheckedIndex) -> Set<String> {
    var modules: Set<String> = []
    index.forEachCanonicalSymbolOccurrence(byName: symbolName) { occurrence in
      guard occurrence.roles.contains(.definition) || occurrence.roles.contains(.declaration) else {
        return true
      }
      let moduleName = occurrence.location.moduleName
      if !moduleName.isEmpty {
        modules.insert(moduleName)
      }
      return true
    }
    return modules
  }

  /// Calculates where to insert a new import statement for alphabetical ordering.
  /// If existing imports are not sorted alphabetically, falls back to inserting at the end.
  static func importInsertionPosition(
    for newModule: String,
    in syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot
  ) -> Position {
    let importDecls = syntaxTree.statements
      .compactMap { $0.item.as(ImportDeclSyntax.self) }
      .filter { $0.importKindSpecifier == nil && $0.path.count == 1 }

    let importNames = importDecls.compactMap { $0.path.first?.name.text }

    let isSorted = zip(importNames, importNames.dropFirst()).allSatisfy { $0 <= $1 }

    if isSorted,
      let insertBeforeImport = importDecls.first(where: { importDecl in
        guard let firstPath = importDecl.path.first?.name.text else { return false }
        return firstPath > newModule
      })
    {
      return snapshot.position(of: insertBeforeImport.position)
    } else if let lastImport = importDecls.last {
      return snapshot.position(of: lastImport.endPosition)
    }
    if let firstStatement = syntaxTree.statements.first {
      return snapshot.position(of: firstStatement.positionAfterSkippingLeadingTrivia)
    }
    return snapshot.position(of: AbsolutePosition(utf8Offset: 0))
  }
}

private extension Diagnostic {
  var codeString: String? {
    switch code {
    case .string(let code): return code
    case .number(let code): return String(code)
    case nil: return nil
    }
  }
}

extension SwiftLanguageService {
  /// Finds missing import code actions for diagnostics indicating unresolved symbols.
  /// Exposed for unit testing.
  package static func findMissingImports(
    diagnostics: [Diagnostic],
    existingImports: Set<String>,
    currentModule: String?,
    syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot,
    uri: DocumentURI,
    lookup: (String) -> Set<String>
  ) -> [CodeAction] {
    let missingSymbolDiagnostics = diagnostics.filter(AddMissingImportsHelper.isMissingTypeOrValueDiagnostic)
    guard !missingSymbolDiagnostics.isEmpty else { return [] }

    return missingSymbolDiagnostics.flatMap { diagnostic -> [CodeAction] in
      guard let symbolName = AddMissingImportsHelper.extractSymbolName(from: diagnostic.message) else {
        return []
      }

      let candidateModules = lookup(symbolName)
        .filter { !existingImports.contains($0) && $0 != currentModule }
        .sorted()

      return candidateModules.map { module in
        let insertPosition = AddMissingImportsHelper.importInsertionPosition(
          for: module,
          in: syntaxTree,
          snapshot: snapshot
        )
        let hasExistingImports = !syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }.isEmpty

        let importText: String
        if hasExistingImports {
          let allImportDecls = syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
          let lastImportEnd = allImportDecls.last.map { snapshot.position(of: $0.endPosition) }
          if lastImportEnd == insertPosition {
            importText = "\nimport \(module)"
          } else {
            importText = "import \(module)\n"
          }
        } else {
          importText = "import \(module)\n"
        }

        let edit = WorkspaceEdit(changes: [
          uri: [TextEdit(range: insertPosition..<insertPosition, newText: importText)]
        ])
        return CodeAction(title: "Import \(module)", kind: .quickFix, diagnostics: [diagnostic], edit: edit)
      }
    }
  }
}
