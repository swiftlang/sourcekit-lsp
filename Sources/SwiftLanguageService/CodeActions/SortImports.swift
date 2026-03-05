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
import SwiftSyntax

/// Code action that alphabetically sorts the leading block of import statements.
///
/// Matches the import order produced by swift-format. Only considers the contiguous
/// import block at the top of the file (stops at the first non-import statement).
///
/// ## Example
/// Before:
/// ```swift
/// import UIKit
/// import Foundation
/// import Combine
/// import SwiftUI
/// ```
/// After:
/// ```swift
/// import Combine
/// import Foundation
/// import SwiftUI
/// import UIKit
/// ```
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

    let sortedDecls = importBlock.sorted { lhs, rhs in
      lhs.path.trimmedDescription < rhs.path.trimmedDescription
    }
    let alreadySorted = zip(importBlock, sortedDecls).allSatisfy { $0.path.trimmedDescription == $1.path.trimmedDescription }
    if alreadySorted {
      return []
    }

    let firstImport = importBlock.first!
    let lastImport = importBlock.last!
    let rangeStart = firstImport.positionAfterSkippingLeadingTrivia
    let rangeEnd = lastImport.endPosition
    let editRange = scope.snapshot.position(of: rangeStart)..<scope.snapshot.position(of: rangeEnd)
    let newText = sortedDecls.map { $0.trimmedDescription }.joined(separator: "\n") + "\n"

    return [
      CodeAction(
        title: "Sort imports",
        kind: .sourceOrganizeImports,
        edit: WorkspaceEdit(
          changes: [
            scope.snapshot.uri: [TextEdit(range: editRange, newText: newText)]
          ]
        )
      )
    ]
  }
}

/// Returns the contiguous leading block of top-level import declarations.
private func leadingImportBlock(in file: SourceFileSyntax) -> [ImportDeclSyntax] {
  var result: [ImportDeclSyntax] = []
  for item in file.statements {
    guard let importDecl = item.item.as(ImportDeclSyntax.self) else {
      break
    }
    result.append(importDecl)
  }
  return result
}

/// Returns the absolute position range of the import block (from first import start to last import end).
private func importBlockRange(_ importBlock: [ImportDeclSyntax]) -> Range<AbsolutePosition> {
  let first = importBlock.first!
  let last = importBlock.last!
  return first.positionAfterSkippingLeadingTrivia..<last.endPosition
}
