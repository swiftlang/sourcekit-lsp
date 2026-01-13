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

import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import SemanticIndex
package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax

extension SwiftLanguageService {
  package func addMissingImports(_ request: CodeActionRequest) async throws -> [CodeAction] {
    let snapshot = try await self.latestSnapshot(for: request.textDocument.uri)

    guard let buildSettings = await self.compileCommand(for: request.textDocument.uri, fallbackAfterTimeout: true),
      !buildSettings.isFallback
    else {
      return []
    }

    guard
      let index = await self.sourceKitLSPServer?.workspaceForDocument(uri: request.textDocument.uri)?.index(
        checkedFor: .modifiedFiles
      )
    else {
      return []
    }

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let existingImports = Self.extractExistingImports(from: syntaxTree)
    let currentModule = Self.extractModuleName(from: buildSettings.compilerArgs)

    return Self.findMissingImports(
      diagnostics: request.context.diagnostics,
      existingImports: existingImports,
      currentModule: currentModule,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: request.textDocument.uri,
      lookup: { typeName in Self.findModulesDefining(typeName, in: index) }
    )
  }

  /// Finds missing import code actions for diagnostics.
  package static func findMissingImports(
    diagnostics: [Diagnostic],
    existingImports: Set<String>,
    currentModule: String?,
    syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot,
    uri: DocumentURI,
    lookup: (String) -> Set<String>
  ) -> [CodeAction] {
    let missingTypeDiagnostics = diagnostics.filter(isMissingTypeOrValueDiagnostic)
    guard !missingTypeDiagnostics.isEmpty else { return [] }

    let insertionPosition = importInsertionPosition(in: syntaxTree, snapshot: snapshot)

    return missingTypeDiagnostics.flatMap { diagnostic in
      createImportActions(
        for: diagnostic,
        lookup: lookup,
        existingImports: existingImports,
        currentModule: currentModule,
        insertionPosition: insertionPosition,
        uri: uri
      )
    }
  }

  /// Extracts existing imports from the syntax tree.
  private static func extractExistingImports(from syntaxTree: SourceFileSyntax) -> Set<String> {
    Set(
      syntaxTree.statements
        .compactMap { $0.item.as(ImportDeclSyntax.self) }
        .compactMap { $0.path.first?.name.text }
    )
  }

  /// Extracts the module name from Swift compiler arguments.
  private static func extractModuleName(from compilerArgs: [String]) -> String? {
    guard let moduleNameIndex = compilerArgs.lastIndex(of: "-module-name"),
      moduleNameIndex + 1 < compilerArgs.count
    else {
      return nil
    }
    return compilerArgs[moduleNameIndex + 1]
  }

  /// Finds all modules that define a given type by querying the index.
  /// This abstracts away the slow index lookup operation.
  private static func findModulesDefining(_ typeName: String, in index: CheckedIndex) -> Set<String> {
    var modules: Set<String> = []
    index.forEachCanonicalSymbolOccurrence(byName: typeName) { occurrence in
      guard IndexSymbolKind.typeKinds.contains(occurrence.symbol.kind) else {
        return true
      }

      // Prefer container name (module), fall back to location module name
      let moduleName = index.containerNames(of: occurrence).first ?? occurrence.location.moduleName
      if !moduleName.isEmpty {
        modules.insert(moduleName)
      }
      return true
    }
    return modules
  }

  /// Calculates where to insert a new import statement.
  /// Inserts after the last import if any exist, otherwise at the file start.
  private static func importInsertionPosition(
    in syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot
  ) -> Position {
    let importDecls = syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }

    if let lastImport = importDecls.last {
      return snapshot.position(of: lastImport.endPosition)
    }

    let startPosition = syntaxTree.statements.first?.position ?? AbsolutePosition(utf8Offset: 0)
    return snapshot.position(of: startPosition)
  }

  /// Extracts the type name from a diagnostic message.
  private static func extractTypeName(from message: String) -> String? {
    for prefix in ["cannot find type '", "cannot find '"] {
      if let typeName = extractQuotedText(from: message, after: prefix, before: "' in scope") {
        return typeName
      }
    }
    return nil
  }

  /// Extracts text between two markers in a string.
  private static func extractQuotedText(from text: String, after prefix: String, before suffix: String) -> String? {
    guard let prefixRange = text.range(of: prefix, options: .caseInsensitive),
      let suffixRange = text.range(of: suffix, options: .caseInsensitive, range: prefixRange.upperBound..<text.endIndex)
    else {
      return nil
    }
    return String(text[prefixRange.upperBound..<suffixRange.lowerBound])
  }

  /// Checks if a diagnostic indicates a missing type or value.
  private static func isMissingTypeOrValueDiagnostic(_ diagnostic: Diagnostic) -> Bool {
    if let code = diagnostic.codeString {
      return code == "cannot_find_type_in_scope" || code == "cannot_find_in_scope"
    }
    return diagnostic.message.localizedCaseInsensitiveContains("cannot find")
      && diagnostic.message.localizedCaseInsensitiveContains("in scope")
  }

  /// Creates import code actions for a diagnostic.
  private static func createImportActions(
    for diagnostic: Diagnostic,
    lookup: (String) -> Set<String>,
    existingImports: Set<String>,
    currentModule: String?,
    insertionPosition: Position,
    uri: DocumentURI
  ) -> [CodeAction] {
    guard let typeName = extractTypeName(from: diagnostic.message) else {
      return []
    }

    return lookup(typeName)
      .sorted()
      .filter { module in
        !existingImports.contains(module) && module != currentModule
      }
      .map { module in
        let edit = WorkspaceEdit(changes: [
          uri: [TextEdit(range: insertionPosition..<insertionPosition, newText: "import \(module)\n")]
        ])
        return CodeAction(title: "Import \(module)", kind: .quickFix, diagnostics: [diagnostic], edit: edit)
      }
  }
}

// MARK: - Extensions

private extension IndexSymbolKind {
  static let typeKinds: Set<IndexSymbolKind> = [.struct, .class, .enum, .protocol, .typealias]
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
