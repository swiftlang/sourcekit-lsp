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
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

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

    return Self.findMissingImports(
      diagnostics: request.context.diagnostics,
      existingImports: existingImports,
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
    uri: DocumentURI,
    lookup: (String) -> Set<String>
  ) -> [CodeAction] {
    // Filter for diagnostics that indicate a missing type.
    let missingTypeDiagnostics = diagnostics.filter { diagnostic in
      return diagnostic.message.range(of: "cannot find", options: .caseInsensitive) != nil
        && diagnostic.message.range(of: "in scope", options: .caseInsensitive) != nil
    }

    if missingTypeDiagnostics.isEmpty {
      return []
    }

    var codeActions: [CodeAction] = []

    for diagnostic in missingTypeDiagnostics {
      // Extract the missing type name from the diagnostic message.
      guard let range = diagnostic.message.range(of: "cannot find '", options: .caseInsensitive),
        let endRange = diagnostic.message.range(
          of: "' in scope",
          options: .caseInsensitive,
          range: range.upperBound..<diagnostic.message.endIndex
        )
      else {
        continue
      }
      let typeName = String(diagnostic.message[range.upperBound..<endRange.lowerBound])

      let modulesDefiningType = lookup(typeName)

      for module in modulesDefiningType.sorted() {
        if existingImports.contains(module) { continue }

        let newImportText = "import \(module)\n"
        let edit = WorkspaceEdit(changes: [
          uri: [
            TextEdit(range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0), newText: newImportText)
          ]
        ])

        codeActions.append(
          CodeAction(title: "Import \(module)", kind: .quickFix, diagnostics: [diagnostic], edit: edit)
        )
      }
    }

    return codeActions
  }
}
