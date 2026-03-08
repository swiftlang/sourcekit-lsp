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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import Foundation
import SwiftSyntax

/// A code action that sorts import statements lexicographically.
///
/// Imports are grouped by kind, matching the behavior of swift-format's
/// `OrderedImports` rule:
/// 1. Regular imports (e.g. `import Foundation`)
/// 2. Declaration imports (e.g. `import struct Foundation.URL`)
/// 3. `@_implementationOnly` imports
/// 4. `@testable` imports
///
/// Within each group, imports are sorted lexicographically by their import
/// path. Groups are separated by a single blank line.
///
/// **Before:**
/// ```swift
/// @testable import MyModule
/// import UIKit
/// import Foundation
/// import Combine
/// ```
///
/// **After:**
/// ```swift
/// import Combine
/// import Foundation
/// import UIKit
///
/// @testable import MyModule
/// ```
struct SortImports: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    let imports = collectImports(from: scope.file)

    guard imports.count >= 2 else {
      return []
    }

    // Classify imports into groups matching swift-format's ordering.
    var regularImports: [ImportInfo] = []
    var declImports: [ImportInfo] = []
    var implementationOnlyImports: [ImportInfo] = []
    var testableImports: [ImportInfo] = []

    for info in imports {
      switch info.kind {
      case .regular:
        regularImports.append(info)
      case .declaration:
        declImports.append(info)
      case .implementationOnly:
        implementationOnlyImports.append(info)
      case .testable:
        testableImports.append(info)
      }
    }

    // Sort each group lexicographically by import path.
    regularImports.sort { $0.importPath < $1.importPath }
    declImports.sort { $0.importPath < $1.importPath }
    implementationOnlyImports.sort { $0.importPath < $1.importPath }
    testableImports.sort { $0.importPath < $1.importPath }

    // Build the sorted text with groups separated by blank lines.
    let groups: [[ImportInfo]] = [regularImports, declImports, implementationOnlyImports, testableImports]
    let nonEmptyGroups = groups.filter { !$0.isEmpty }
    let sortedText = nonEmptyGroups.map { group in
      group.map(\.importText).joined(separator: "\n")
    }.joined(separator: "\n\n")

    // Build the current text for comparison.
    let currentText = imports.map(\.importText).joined(separator: "\n")

    // Don't offer the action if nothing would change.
    if currentText == sortedText {
      return []
    }

    // Replace the entire import block.
    let startPosition = scope.snapshot.position(
      of: imports.first!.decl.positionAfterSkippingLeadingTrivia
    )
    let endPosition = scope.snapshot.position(
      of: imports.last!.decl.endPositionBeforeTrailingTrivia
    )

    return [
      CodeAction(
        title: "Sort imports",
        kind: .source,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [
              TextEdit(
                range: startPosition..<endPosition,
                newText: sortedText
              )
            ]
          ]
        )
      )
    ]
  }
}

// MARK: - Import classification

private enum ImportKind {
  case regular
  case declaration
  case implementationOnly
  case testable
}

private struct ImportInfo {
  /// The import declaration syntax node.
  let decl: ImportDeclSyntax

  /// The kind of import for grouping purposes.
  let kind: ImportKind

  /// The import path (e.g. "Foundation" or "Foundation.URL"), used for sorting.
  let importPath: String

  /// The full text of the import statement (without leading/trailing trivia),
  /// used for both comparison and output.
  let importText: String
}

/// Collects all contiguous import declarations from the top of the source file,
/// skipping any leading comments and blank lines.
private func collectImports(from file: SourceFileSyntax) -> [ImportInfo] {
  var imports: [ImportInfo] = []

  for statement in file.statements {
    guard let importDecl = statement.item.as(ImportDeclSyntax.self) else {
      // Stop at the first non-import statement.
      break
    }

    let kind = classifyImport(importDecl)
    let importPath = importDecl.path.description.trimmingCharacters(in: .whitespacesAndNewlines)

    // Build the import text without leading/trailing trivia.
    var declForText = importDecl
    declForText.leadingTrivia = []
    declForText.trailingTrivia = []
    let importText = declForText.description.trimmingCharacters(in: .whitespacesAndNewlines)

    imports.append(
      ImportInfo(
        decl: importDecl,
        kind: kind,
        importPath: importPath,
        importText: importText
      )
    )
  }

  return imports
}

/// Classifies an import declaration by its attributes and kind specifier,
/// matching the grouping used by swift-format.
private func classifyImport(_ decl: ImportDeclSyntax) -> ImportKind {
  let attributeNames = decl.attributes.compactMap {
    $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text
  }

  if attributeNames.contains("testable") {
    return .testable
  }
  if attributeNames.contains("_implementationOnly") {
    return .implementationOnly
  }
  if decl.importKindSpecifier != nil {
    return .declaration
  }
  return .regular
}
