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
package import SourceKitLSP
import SwiftParser
public import SwiftSyntax
package import ToolchainRegistry

private enum PackageManifestFeatureKind: Sendable {
  case upcoming
  case experimental

  var supportedFeatureKind: SupportedSwiftFeature.Kind {
    switch self {
    case .upcoming:
      return .upcoming
    case .experimental:
      return .experimental
    }
  }

  var displayName: String {
    switch self {
    case .upcoming:
      return "upcoming"
    case .experimental:
      return "experimental"
    }
  }
}

private struct PackageManifestFeatureUse: Sendable {
  let kind: PackageManifestFeatureKind
  let name: String
  let contentRange: Range<AbsolutePosition>
}

package enum PackageManifestFeatureSupport {
  package static func diagnostics(
    in snapshot: DocumentSnapshot,
    syntaxTree: SourceFileSyntax,
    supportedFeatures: SupportedSwiftFeatures,
    swiftLanguageVersion: SwiftVersion?
  ) -> [Diagnostic] {
    guard isPackageManifest(snapshot.uri) else {
      return []
    }

    return featureUses(in: syntaxTree).compactMap { featureUse in
      let name = featureUse.name
      let kind = featureUse.kind.supportedFeatureKind
      let range =
        snapshot.position(
          of: featureUse.contentRange.lowerBound
        )..<snapshot.position(
          of: featureUse.contentRange.upperBound
        )

      if let feature = supportedFeatures.feature(named: name, kind: kind) {
        if featureUse.kind == .upcoming,
          let enabledIn = feature.enabledIn,
          let swiftLanguageVersion,
          enabledIn <= swiftLanguageVersion
        {
          return Diagnostic(
            range: range,
            severity: .warning,
            source: "SourceKit",
            message: "'\(name)' is already enabled in Swift \(swiftLanguageVersion)"
          )
        }
        return nil
      }

      let otherKind: PackageManifestFeatureKind = featureUse.kind == .upcoming ? .experimental : .upcoming
      if supportedFeatures.contains(name, kind: otherKind.supportedFeatureKind) {
        return Diagnostic(
          range: range,
          severity: .warning,
          source: "SourceKit",
          message:
            "'\(name)' is not a recognized \(featureUse.kind.displayName) feature; use enable\(otherKind.displayName.capitalized)Feature instead"
        )
      }

      let candidates = featureUse.kind == .upcoming ? supportedFeatures.upcoming : supportedFeatures.experimental
      let suggestion = closestMatch(to: name, in: candidates.map(\.name))
      let message: String
      if let suggestion {
        message =
          "'\(name)' is not a recognized \(featureUse.kind.displayName) feature; did you mean '\(suggestion)'?"
      } else {
        message = "'\(name)' is not a recognized \(featureUse.kind.displayName) feature"
      }
      return Diagnostic(range: range, severity: .warning, source: "SourceKit", message: message)
    }
  }

  package static func completion(
    in snapshot: DocumentSnapshot,
    syntaxTree: SourceFileSyntax,
    position: Position,
    supportedFeatures: SupportedSwiftFeatures
  ) -> CompletionList? {
    guard isPackageManifest(snapshot.uri) else {
      return nil
    }

    let absolutePosition = snapshot.absolutePosition(of: position)
    guard
      let featureUse = featureUses(in: syntaxTree).first(where: { featureUse in
        featureUse.contentRange.lowerBound <= absolutePosition && absolutePosition <= featureUse.contentRange.upperBound
      })
    else {
      return nil
    }

    let features = featureUse.kind == .upcoming ? supportedFeatures.upcoming : supportedFeatures.experimental
    let typedPrefix = String(
      snapshot.text[
        snapshot.indexOf(
          utf8Offset: featureUse.contentRange.lowerBound.utf8Offset
        )..<snapshot.indexOf(
          utf8Offset: absolutePosition.utf8Offset
        )
      ]
    )
    let replacementRange =
      snapshot.position(
        of: featureUse.contentRange.lowerBound
      )..<snapshot.position(
        of: featureUse.contentRange.upperBound
      )
    let items =
      features
      .filter { typedPrefix.isEmpty || $0.name.localizedCaseInsensitiveContains(typedPrefix) }
      .map { feature in
        CompletionItem(
          label: feature.name,
          kind: .value,
          detail: featureUse.kind.displayName.capitalized + " Swift feature",
          sortText: feature.name,
          filterText: feature.name,
          insertText: feature.name,
          insertTextFormat: .plain,
          textEdit: .textEdit(TextEdit(range: replacementRange, newText: feature.name))
        )
      }
    return CompletionList(isIncomplete: false, items: items)
  }

  private static func isPackageManifest(_ uri: DocumentURI) -> Bool {
    guard let fileURL = uri.fileURL else {
      return false
    }
    let name = fileURL.lastPathComponent
    return name == "Package.swift" || (name.hasPrefix("Package@swift-") && name.hasSuffix(".swift"))
  }

  private static func featureUses(in syntaxTree: SourceFileSyntax) -> [PackageManifestFeatureUse] {
    let visitor = PackageManifestFeatureUseVisitor(viewMode: .sourceAccurate)
    visitor.walk(syntaxTree)
    return visitor.featureUses
  }

  private static func closestMatch(to name: String, in candidates: [String]) -> String? {
    let scored = candidates.map { ($0, editDistance(name.lowercased(), $0.lowercased())) }.min { lhs, rhs in
      lhs.1 < rhs.1
    }
    guard let (candidate, distance) = scored else {
      return nil
    }
    let threshold = max(2, min(5, name.count / 3))
    return distance <= threshold ? candidate : nil
  }

  private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
    let lhs = Array(lhs)
    let rhs = Array(rhs)
    if lhs.isEmpty { return rhs.count }
    if rhs.isEmpty { return lhs.count }

    var previous = Array(0...rhs.count)
    var current = Array(repeating: 0, count: rhs.count + 1)
    for lhsIndex in 1...lhs.count {
      current[0] = lhsIndex
      for rhsIndex in 1...rhs.count {
        let substitutionCost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
        current[rhsIndex] = min(
          previous[rhsIndex] + 1,
          current[rhsIndex - 1] + 1,
          previous[rhsIndex - 1] + substitutionCost
        )
      }
      previous = current
    }
    return previous[rhs.count]
  }
}

private final class PackageManifestFeatureUseVisitor: SyntaxVisitor {
  var featureUses: [PackageManifestFeatureUse] = []

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
      return .visitChildren
    }

    let kind: PackageManifestFeatureKind
    switch memberAccess.declName.baseName.text {
    case "enableUpcomingFeature":
      kind = .upcoming
    case "enableExperimentalFeature":
      kind = .experimental
    default:
      return .visitChildren
    }

    guard let argument = node.arguments.first,
      argument.label == nil,
      let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
      stringLiteral.segments.count == 1,
      case .stringSegment(let segment)? = stringLiteral.segments.first,
      let name = stringLiteral.representedLiteralValue
    else {
      return .visitChildren
    }

    featureUses.append(
      PackageManifestFeatureUse(
        kind: kind,
        name: name,
        contentRange: segment.positionAfterSkippingLeadingTrivia..<segment.endPositionBeforeTrailingTrivia
      )
    )
    return .skipChildren
  }
}
