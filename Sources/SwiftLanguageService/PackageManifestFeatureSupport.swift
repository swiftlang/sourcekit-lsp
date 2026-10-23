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

/// Represents the category of a Swift feature being enabled in a package manifest.
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
  /// Produces diagnostics for Swift feature names used in package manifests.
  /// The supported feature list comes directly from the toolchain, allowing
  /// diagnostics to reflect the features understood by the active compiler.
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

      // The feature is supported by the other API, so suggest using the
      // corresponding enableUpcomingFeature/enableExperimentalFeature call.
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

    // Use the text between the beginning of the string content and the cursor
    // as the completion filter, while keeping the replacement range limited to
    // the string contents so that the surrounding quotes are preserved.
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

  /// Finds the closest matching string from a list of candidates
  private static func closestMatch(to name: String, in candidates: [String]) -> String? {
    let target = name.lowercased()
    var bestCandidate: String?
    var bestDistance = Int.max

    // Only suggest candidates within a small edit distance.
    let threshold = 2

    for candidate in candidates {
      let distance = mismatchCount(target, candidate.lowercased(), limit: threshold)
      if distance <= threshold, distance < bestDistance {
        bestDistance = distance
        bestCandidate = candidate
      }
    }
    return bestCandidate
  }

  private static func mismatchCount(_ lhs: String, _ rhs: String, limit: Int) -> Int {
    let lhsChars = Array(lhs)
    let rhsChars = Array(rhs)

    if abs(lhsChars.count - rhsChars.count) > limit {
      return Int.max
    }

    var differences = 0
    var i = 0
    var j = 0

    while i < lhsChars.count && j < rhsChars.count {
      if lhsChars[i] == rhsChars[j] {
        i += 1
        j += 1
      } else {
        differences += 1
        if differences > limit { return Int.max }

        let canSkipLhs = i + 1 < lhsChars.count && lhsChars[i + 1] == rhsChars[j]
        let canSkipRhs = j + 1 < rhsChars.count && lhsChars[i] == rhsChars[j + 1]

        if canSkipLhs && canSkipRhs {
          i += 1
          j += 1
        } else if canSkipLhs {
          i += 1
        } else if canSkipRhs {
          j += 1
        } else {
          i += 1
          j += 1
        }
      }
    }

    differences += (lhsChars.count - i) + (rhsChars.count - j)
    return differences > limit ? Int.max : differences
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
