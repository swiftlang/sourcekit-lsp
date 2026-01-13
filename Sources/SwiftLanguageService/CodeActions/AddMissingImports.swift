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

    // We need the index to find where the missing types are defined.
    // Workspace.index(checkedFor:) returns CheckedIndex.
    let index = await self.sourceKitLSPServer?.workspaceForDocument(uri: request.textDocument.uri)?.index(
      checkedFor: .modifiedFiles
    )
    guard let index else {
      return []
    }

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    // Identify existing imports so we don't suggest importing something that's already there
    let existingImports: Set<String> = Set(
      syntaxTree.statements
        .compactMap { $0.item.as(ImportDeclSyntax.self) }
        .compactMap { $0.path.first?.name.text }
    )

    // Extract the current module name to avoid suggesting self-imports
    let currentModule = Self.extractModuleName(from: buildSettings.compilerArgs)

    return Self.findMissingImports(
      diagnostics: request.context.diagnostics,
      existingImports: existingImports,
      currentModule: currentModule,
      syntaxTree: syntaxTree,
      snapshot: snapshot,
      uri: request.textDocument.uri
    ) { typeName in
      var modules: Set<String> = []
      index.forEachCanonicalSymbolOccurrence(byName: typeName) { occurrence in
        let validKinds: Set<IndexSymbolKind> = [.struct, .class, .enum, .protocol, .typealias]
        if validKinds.contains(occurrence.symbol.kind) {
          let containers = index.containerNames(of: occurrence)
          if let firstContainer = containers.first {
            modules.insert(firstContainer)
          } else {
            let moduleName = occurrence.location.moduleName
            if !moduleName.isEmpty {
              modules.insert(moduleName)
            }
          }
        }
        return true
      }
      return modules
    }
  }

  /// Internal logic for finding missing imports, separated for unit testing.
  package static func findMissingImports(
    diagnostics: [Diagnostic],
    existingImports: Set<String>,
    currentModule: String?,
    syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot,
    uri: DocumentURI,
    lookup: (String) -> Set<String>
  ) -> [CodeAction] {
    // Filter for diagnostics that indicate a missing type or value.
    // Check diagnostic code first (more reliable), fall back to string matching.
    let missingTypeDiagnostics = diagnostics.filter { diagnostic in
      // Primary: check for known diagnostic codes
      if let code = diagnostic.codeString {
        // Handle both type and value missing declarations
        if code == "cannot_find_type_in_scope" || code == "cannot_find_in_scope" {
          return true
        }
      }
      // Fallback: string matching for older compilers or different diagnostic formats
      // Matches both "cannot find type 'X' in scope" and "cannot find 'X' in scope"
      return diagnostic.message.range(of: "cannot find", options: .caseInsensitive) != nil
        && diagnostic.message.range(of: "in scope", options: .caseInsensitive) != nil
    }

    if missingTypeDiagnostics.isEmpty {
      return []
    }

    // Calculate the proper insertion position for new imports
    let insertionPosition = importInsertionPosition(in: syntaxTree, snapshot: snapshot)

    var codeActions: [CodeAction] = []

    for diagnostic in missingTypeDiagnostics {
      // Extract the missing type name from the diagnostic message.
      guard let typeName = extractTypeName(from: diagnostic.message) else {
        continue
      }

      let modulesDefiningType = lookup(typeName)

      for module in modulesDefiningType.sorted() {
        // Skip if already imported
        if existingImports.contains(module) { continue }

        // Skip if this is the current module (avoid self-import)
        if let currentModule, module == currentModule { continue }

        let newImportText = "import \(module)\n"
        let edit = WorkspaceEdit(changes: [
          uri: [
            TextEdit(range: insertionPosition..<insertionPosition, newText: newImportText)
          ]
        ])

        codeActions.append(
          CodeAction(title: "Import \(module)", kind: .quickFix, diagnostics: [diagnostic], edit: edit)
        )
      }
    }

    return codeActions
  }

  /// Extracts the module name from Swift compiler arguments.
  ///
  /// - Parameter compilerArgs: The compiler arguments from build settings.
  /// - Returns: The module name if found, otherwise `nil`.
  private static func extractModuleName(from compilerArgs: [String]) -> String? {
    guard let moduleNameIndex = compilerArgs.lastIndex(of: "-module-name"),
      moduleNameIndex + 1 < compilerArgs.count
    else {
      return nil
    }
    return compilerArgs[moduleNameIndex + 1]
  }

  /// Calculates the position where a new import should be inserted.
  ///
  /// The insertion logic follows this priority:
  /// 1. If imports exist, insert after the last import declaration.
  /// 2. If no imports exist, insert at the beginning of the file (before first declaration).
  ///
  /// - Parameters:
  ///   - syntaxTree: The syntax tree of the source file.
  ///   - snapshot: The document snapshot for position conversion.
  /// - Returns: The position where the import should be inserted.
  private static func importInsertionPosition(
    in syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot
  ) -> Position {
    // Find all import declarations
    let importDecls = syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }

    if let lastImport = importDecls.last {
      // Insert after the last import
      let positionAfterImport = lastImport.endPosition
      return snapshot.position(of: positionAfterImport)
    } else {
      // No imports exist - insert at the beginning of the file
      // This will be after any leading trivia (comments, headers, etc.)
      if let firstStatement = syntaxTree.statements.first {
        let firstStatementPosition = firstStatement.position
        return snapshot.position(of: firstStatementPosition)
      } else {
        // Empty file - insert at line 0
        return Position(line: 0, utf16index: 0)
      }
    }
  }

  /// Extracts the type name from a diagnostic message.
  ///
  /// - Parameter message: The diagnostic message.
  /// - Returns: The extracted type name, or `nil` if parsing fails.
  private static func extractTypeName(from message: String) -> String? {
    // Handle both "cannot find type 'X' in scope" and "cannot find 'X' in scope"
    if let range = message.range(of: "cannot find type '", options: .caseInsensitive),
      let endRange = message.range(
        of: "' in scope",
        options: .caseInsensitive,
        range: range.upperBound..<message.endIndex
      )
    {
      return String(message[range.upperBound..<endRange.lowerBound])
    }

    // Fallback to non-type variant
    if let range = message.range(of: "cannot find '", options: .caseInsensitive),
      let endRange = message.range(
        of: "' in scope",
        options: .caseInsensitive,
        range: range.upperBound..<message.endIndex
      )
    {
      return String(message[range.upperBound..<endRange.lowerBound])
    }

    return nil
  }
}

// MARK: - Diagnostic Extensions

private extension Diagnostic {
  /// Extracts the diagnostic code as a string.
  var codeString: String? {
    switch code {
    case .string(let code):
      return code
    case .number(let code):
      return String(code)
    case nil:
      return nil
    }
  }
}
