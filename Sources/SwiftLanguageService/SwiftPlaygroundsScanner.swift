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

internal import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SourceKitLSP
import SwiftParser
import SwiftSyntax

// MARK: - SwiftPlaygroundsScanner

final class SwiftPlaygroundsScanner: SyntaxVisitor {
  /// The base ID to use to generate IDs for any playgrounds found in this file.
  private let baseID: String

  /// The snapshot of the document for which we are getting playgrounds.
  private let snapshot: DocumentSnapshot

  /// Accumulating the result in here.
  private var result: [TextDocumentPlayground] = []

  /// Keep track of if "Playgrounds" has been imported
  private var isPlaygroundImported: Bool = false

  private init(baseID: String, snapshot: DocumentSnapshot) {
    self.baseID = baseID
    self.snapshot = snapshot
    super.init(viewMode: .sourceAccurate)
  }

  /// Designated entry point for `SwiftPlaygroundsScanner`.
  static func findDocumentPlaygrounds(
    for snapshot: DocumentSnapshot,
    workspace: Workspace,
    syntaxTreeManager: SyntaxTreeManager,
  ) async -> [TextDocumentPlayground] {
    guard snapshot.text.contains("#Playground") else {
      return []
    }

    guard let canonicalTarget = await workspace.buildServerManager.canonicalTarget(for: snapshot.uri),
      let moduleName = await workspace.buildServerManager.moduleName(for: snapshot.uri, in: canonicalTarget),
      let baseName = snapshot.uri.fileURL?.lastPathComponent
    else {
      return []
    }

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

    let visitor = SwiftPlaygroundsScanner(baseID: "\(moduleName)/\(baseName)", snapshot: snapshot)
    visitor.walk(syntaxTree)
    return visitor.isPlaygroundImported ? visitor.result : []
  }

  /// Add a playground location with the given parameters to the `result` array.
  private func record(
    id: String,
    label: String?,
    range: Range<AbsolutePosition>
  ) {
    let positionRange = snapshot.absolutePositionRange(of: range)

    result.append(
      TextDocumentPlayground(
        id: id,
        label: label,
        range: positionRange,
      )
    )
  }

  override func visit(_ node: ImportPathComponentSyntax) -> SyntaxVisitorContinueKind {
    if node.name.text == "Playgrounds" {
      isPlaygroundImported = true
    }
    return .skipChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
    guard node.macroName.text == "Playground" else {
      return .skipChildren
    }

    let startPosition = snapshot.sourcekitdPosition(of: snapshot.position(of: node.positionAfterSkippingLeadingTrivia))
    let stringLiteral = node.arguments.first?.expression.as(StringLiteralExprSyntax.self)
    let playgroundLabel = stringLiteral?.representedLiteralValue
    let playgroundID = "\(baseID):\(startPosition.line):\(startPosition.utf8Column)"

    record(
      id: playgroundID,
      label: playgroundLabel,
      range: node.trimmedRange
    )

    return .skipChildren
  }
}
