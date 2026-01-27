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
@_spi(SourceKitLSP) package import LanguageServerProtocol
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

package struct InlayHintResolveData: LSPAnyCodable {
  package let uri: DocumentURI
  package let position: Position
  package let version: Int

  package init(uri: DocumentURI, position: Position, version: Int) {
    self.uri = uri
    self.position = position
    self.version = version
  }

  package init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard case .string(let uriString) = dictionary["uri"],
      let uri = try? DocumentURI(string: uriString),
      case .int(let version) = dictionary["version"],
      let position = Position(fromLSPAny: dictionary["position"])
    else {
      return nil
    }
    self.uri = uri
    self.position = position
    self.version = version
  }

  package func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      "uri": .string(uri.stringValue),
      "position": position.encodeToLSPAny(),
      "version": .int(version),
    ])
  }
}

private class IfConfigCollector: SyntaxVisitor {
  private var ifConfigDecls: [IfConfigDeclSyntax] = []

  override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
    ifConfigDecls.append(node)

    return .visitChildren
  }

  static func collectIfConfigDecls(in tree: some SyntaxProtocol) -> [IfConfigDeclSyntax] {
    let visitor = IfConfigCollector(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return visitor.ifConfigDecls
  }
}

extension SwiftLanguageService {
  package func inlayHint(_ req: InlayHintRequest) async throws -> [InlayHint] {
    let uri = req.textDocument.uri
    let snapshot = try await self.latestSnapshot(for: uri)
    let version = snapshot.version

    let infos = try await variableTypeInfos(uri, req.range)
    let typeHints = infos
      .lazy
      .filter { !$0.hasExplicitType }
      .map { info -> InlayHint in
        let position = info.range.upperBound
        let variableStart = info.range.lowerBound
        let label = ": \(info.printedType)"
        let textEdits: [TextEdit]?
        if info.canBeFollowedByTypeAnnotation {
          textEdits = [TextEdit(range: position..<position, newText: label)]
        } else {
          textEdits = nil
        }
        let resolveData = InlayHintResolveData(uri: uri, position: variableStart, version: version)
        return InlayHint(
          position: position,
          label: .string(label),
          kind: .type,
          textEdits: textEdits,
          data: resolveData.encodeToLSPAny()
        )
      }

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let ifConfigDecls = IfConfigCollector.collectIfConfigDecls(in: syntaxTree)
    let ifConfigHints = ifConfigDecls.compactMap { (ifConfigDecl) -> InlayHint? in
      // Do not show inlay hints for if config clauses that have a `#elseif` of `#else` clause since it is unclear which
      // `#if`, `#elseif`, or `#else` clause the `#endif` now refers to.
      guard let condition = ifConfigDecl.clauses.only?.condition else {
        return nil
      }
      guard !ifConfigDecl.poundEndif.trailingTrivia.contains(where: { $0.isComment }) else {
        // If a comment already exists (eg. because the user inserted it), don't show an inlay hint.
        return nil
      }
      let hintPosition = snapshot.position(of: ifConfigDecl.poundEndif.endPositionBeforeTrailingTrivia)
      let label = " // \(condition.trimmedDescription)"
      return InlayHint(
        position: hintPosition,
        label: .string(label),
        kind: .type,  // For the lack of a better kind, pretend this comment is a type
        textEdits: [TextEdit(range: Range(hintPosition), newText: label)],
        tooltip: .string("Condition of this conditional compilation clause")
      )
    }

    // Generate trailing closure inlay hints
    let trailingClosureHints = await trailingClosureInlayHints(
      uri: uri,
      range: req.range,
      options: self.options
    )

    return Array(typeHints + ifConfigHints + trailingClosureHints)
  }
}
