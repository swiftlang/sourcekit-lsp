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
import Foundation
import SourceKitLSP
import SwiftSyntax

/// Code action that sorts the leading block of import statements to match swift-format's
/// OrderedImports rule: lexicographic order within groups, with groups 1) regular imports,
/// 2) declaration imports, 3) @_implementationOnly imports, 4) @testable imports (each
/// group separated by a blank line). Preserves file header comments and per-import comments.
///
/// See: https://github.com/swiftlang/swift-format/blob/main/Sources/SwiftFormat/Rules/OrderedImports.swift
struct SortImports: SyntaxCodeActionProvider {
  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    let importBlock = leadingImportBlock(in: scope.file)
    guard importBlock.count >= 2 else {
      return []
    }

    let blockRange = importBlockRange(importBlock)
    guard scope.range.overlaps(blockRange) else {
      return []
    }

    let (fileHeader, classified) = classifyAndExtractFileHeader(importBlock)
    let grouped = groupImports(classified)
    let output = formatImports(fileHeader: fileHeader, grouped: grouped)
    let currentText = buildCurrentImportBlockText(fileHeader: fileHeader, imports: importBlock)
    if output == currentText {
      return []
    }

    let firstImport = importBlock.first!
    let lastImport = importBlock.last!
    let rangeStart = firstImport.position
    let rangeEnd = lastImport.endPosition
    let editRange = scope.snapshot.position(of: rangeStart)..<scope.snapshot.position(of: rangeEnd)

    return [
      CodeAction(
        title: "Sort imports",
        kind: .sourceOrganizeImports,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [TextEdit(range: editRange, newText: output)]
          ]
        )
      )
    ]
  }
}

// MARK: - Import classification (matches swift-format OrderedImports groups)

private enum ImportGroup: Int, CaseIterable {
  case regular = 0
  case declaration = 1
  case implementationOnly = 2
  case testable = 3
}

private struct ClassifiedImport {
  let decl: ImportDeclSyntax
  let leadingComment: String  // Trivia that stays with this import when reordering
}

private func importGroup(_ decl: ImportDeclSyntax) -> ImportGroup {
  let hasTestable = decl.attributes.contains { element in
    guard let attr = element.as(AttributeSyntax.self) else { return false }
    return attributeNameEquals(attr.attributeName, "testable")
  }
  if hasTestable { return .testable }

  let hasImplOnly = decl.attributes.contains { element in
    guard let attr = element.as(AttributeSyntax.self) else { return false }
    return attributeNameEquals(attr.attributeName, "_implementationOnly")
  }
  if hasImplOnly { return .implementationOnly }

  if decl.importKindSpecifier != nil { return .declaration }
  return .regular
}

private func attributeNameEquals(_ name: TypeSyntax, _ text: String) -> Bool {
  guard let id = name.as(IdentifierTypeSyntax.self) else { return false }
  return id.name.text == text
}

// MARK: - File header and per-import leading trivia

/// Splits the first import's leading trivia into file header (before last blank line) and
/// the comment that belongs to that import. Other imports keep their full leading trivia.
private func classifyAndExtractFileHeader(_ importBlock: [ImportDeclSyntax])
  -> (fileHeader: String, classified: [ClassifiedImport])
{
  guard let first = importBlock.first else { return ("", []) }
  let firstLeading = first.leadingTrivia.description
  let (header, firstComment) = splitFileHeader(from: firstLeading)
  var result: [ClassifiedImport] = []
  result.append(ClassifiedImport(decl: first, leadingComment: firstComment))
  for decl in importBlock.dropFirst() {
    let comment = decl.leadingTrivia.description
    result.append(ClassifiedImport(decl: decl, leadingComment: comment))
  }
  return (header, result)
}

/// If leading trivia contains a blank line, file header is the prefix up to and including
/// the last blank line; the rest is the first import's comment. Otherwise no file header.
private func splitFileHeader(from leadingTrivia: String) -> (fileHeader: String, firstImportComment: String) {
  let needle = "\n\n"
  var searchStart = leadingTrivia.startIndex
  var lastBlank: Range<String.Index>?
  while searchStart < leadingTrivia.endIndex,
    let r = leadingTrivia.range(of: needle, range: searchStart..<leadingTrivia.endIndex)
  {
    lastBlank = r
    searchStart = r.upperBound
  }
  if let lastBlank {
    let headerEnd = lastBlank.upperBound
    return (
      String(leadingTrivia[..<headerEnd]),
      String(leadingTrivia[headerEnd...])
    )
  }
  return ("", leadingTrivia)
}

// MARK: - Group and sort

private func groupImports(_ classified: [ClassifiedImport])
  -> [ImportGroup: [ClassifiedImport]]
{
  var grouped: [ImportGroup: [ClassifiedImport]] = [:]
  for imp in classified {
    let g = importGroup(imp.decl)
    grouped[g, default: []].append(imp)
  }
  for g in ImportGroup.allCases {
    grouped[g]?.sort { $0.decl.path.trimmedDescription < $1.decl.path.trimmedDescription }
  }
  return grouped
}

// MARK: - Format output

private func formatImports(fileHeader: String, grouped: [ImportGroup: [ClassifiedImport]]) -> String {
  var sections: [String] = []
  if !fileHeader.isEmpty {
    sections.append(fileHeader)
  }
  for group in ImportGroup.allCases {
    guard let imports = grouped[group], !imports.isEmpty else { continue }
    let lines = imports.map { imp in
      let comment = imp.leadingComment.trimmingCharacters(in: .whitespacesAndNewlines)
      if comment.isEmpty {
        return imp.decl.trimmedDescription
      }
      return comment + "\n" + imp.decl.trimmedDescription
    }
    let block = lines.joined(separator: "\n")
    sections.append(block)
  }
  let joined = sections.joined(separator: "\n\n")
  return joined.isEmpty ? joined : joined + "\n"
}

/// Build the current text of the import block (with file header split) for comparison.
private func buildCurrentImportBlockText(fileHeader: String, imports: [ImportDeclSyntax]) -> String {
  var parts: [String] = []
  if !fileHeader.isEmpty { parts.append(fileHeader) }
  let lines = imports.enumerated().map { index, decl in
    let comment: String
    if index == 0 {
      let (_, firstComment) = splitFileHeader(from: decl.leadingTrivia.description)
      comment = firstComment
    } else {
      comment = decl.leadingTrivia.description
    }
    let c = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    if c.isEmpty { return decl.trimmedDescription }
    return c + "\n" + decl.trimmedDescription
  }
  parts.append(lines.joined(separator: "\n"))
  let result = parts.joined(separator: "\n\n")
  return result.isEmpty ? result : result + "\n"
}

// MARK: - Helpers

private func leadingImportBlock(in file: SourceFileSyntax) -> [ImportDeclSyntax] {
  var result: [ImportDeclSyntax] = []
  for item in file.statements {
    guard let importDecl = item.item.as(ImportDeclSyntax.self) else { break }
    result.append(importDecl)
  }
  return result
}

private func importBlockRange(_ importBlock: [ImportDeclSyntax]) -> Range<AbsolutePosition> {
  let first = importBlock.first!
  let last = importBlock.last!
  return first.position..<last.endPosition
}
