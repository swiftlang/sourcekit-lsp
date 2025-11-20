//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

package struct SemanticClassification: Equatable {
  package var completionKind: CompletionKind
  package var popularity: Popularity
  package var moduleProximity: ModuleProximity
  package var scopeProximity: ScopeProximity
  package var structuralProximity: StructuralProximity
  package var typeCompatibility: TypeCompatibility
  package var synchronicityCompatibility: SynchronicityCompatibility
  package var availability: Availability
  package var flair: Flair

  /// - Note: There is no natural order to these arguments, so they're alphabetical.
  package init(
    availability: Availability,
    completionKind: CompletionKind,
    flair: Flair,
    moduleProximity: ModuleProximity,
    popularity: Popularity,
    scopeProximity: ScopeProximity,
    structuralProximity: StructuralProximity,
    synchronicityCompatibility: SynchronicityCompatibility,
    typeCompatibility: TypeCompatibility
  ) {
    self.availability = availability
    self.completionKind = completionKind
    self.flair = flair
    self.moduleProximity = moduleProximity
    self.popularity = popularity
    self.scopeProximity = scopeProximity
    self.structuralProximity = structuralProximity
    self.synchronicityCompatibility = synchronicityCompatibility
    self.typeCompatibility = typeCompatibility
  }

  package var score: Double {
    let score =
      availability.scoreComponent
      * completionKind.scoreComponent
      * flair.scoreComponent
      * moduleProximity.scoreComponent
      * popularity.scoreComponent
      * scopeProximity.scoreComponent
      * structuralProximity.scoreComponent
      * synchronicityCompatibility.scoreComponent
      * typeCompatibility.scoreComponent
      * globalVariablesPenalty

    return score
  }

  private var globalVariablesPenalty: Double {
    // Global types and functions are fine, global variables and c enum cases in the global space are not.
    if (scopeProximity == .global) && ((completionKind == .variable) || (completionKind == .enumCase)) {
      return 0.75
    }
    return 1.0
  }

  package struct ComponentDebugDescription {
    package let name: String
    package let instance: String
    package let scoreComponent: Double
  }

  private var scoreComponents: [any CompletionScoreComponent] {
    return [
      availability,
      completionKind,
      flair,
      RawCompletionScoreComponent(
        name: "symbolPopularity",
        instance: "\(popularity.symbolComponent)",
        scoreComponent: popularity.symbolComponent
      ),
      RawCompletionScoreComponent(
        name: "modulePopularity",
        instance: "\(popularity.moduleComponent)",
        scoreComponent: popularity.moduleComponent
      ),
      moduleProximity,
      scopeProximity,
      structuralProximity,
      synchronicityCompatibility,
      typeCompatibility,
      RawCompletionScoreComponent(
        name: "globalVariablesPenalty",
        instance: "\(globalVariablesPenalty != 1.0)",
        scoreComponent: globalVariablesPenalty
      ),
    ]
  }

  package var componentsDebugDescription: [ComponentDebugDescription] {
    return scoreComponents.map { $0.componentDebugDescription }
  }
}

extension SemanticClassification: BinaryCodable {
  package init(_ decoder: inout BinaryDecoder) throws {
    availability = try Availability(&decoder)
    completionKind = try CompletionKind(&decoder)
    flair = try Flair(&decoder)
    moduleProximity = try ModuleProximity(&decoder)
    popularity = try Popularity(&decoder)
    scopeProximity = try ScopeProximity(&decoder)
    structuralProximity = try StructuralProximity(&decoder)
    synchronicityCompatibility = try SynchronicityCompatibility(&decoder)
    typeCompatibility = try TypeCompatibility(&decoder)
  }

  package func encode(_ encoder: inout BinaryEncoder) {
    encoder.write(availability)
    encoder.write(completionKind)
    encoder.write(flair)
    encoder.write(moduleProximity)
    encoder.write(popularity)
    encoder.write(scopeProximity)
    encoder.write(structuralProximity)
    encoder.write(synchronicityCompatibility)
    encoder.write(typeCompatibility)
  }
}

/// Published serialization methods
extension SemanticClassification {
  package func byteRepresentation() -> [UInt8] {
    binaryCodedRepresentation(contentVersion: 0)
  }

  package init(byteRepresentation: [UInt8]) throws {
    try self.init(binaryCodedRepresentation: byteRepresentation)
  }

  package static func byteRepresentation(classifications: [Self]) -> [UInt8] {
    classifications.binaryCodedRepresentation(contentVersion: 0)
  }

  package static func classifications(byteRepresentations: [UInt8]) throws -> [Self] {
    try [Self].init(binaryCodedRepresentation: byteRepresentations)
  }
}

/// Used for debugging.
private protocol CompletionScoreComponent {
  var name: String { get }

  var instance: String { get }

  /// Return a value in 0...2.
  ///
  /// Think of values between 0 and 1 as penalties, 1 as neutral, and values from 1 and 2 as bonuses.
  var scoreComponent: Double { get }
}

extension CompletionScoreComponent {
  var componentDebugDescription: SemanticClassification.ComponentDebugDescription {
    return .init(name: name, instance: instance, scoreComponent: scoreComponent)
  }
}

/// Used for components that don't have a dedicated model.
private struct RawCompletionScoreComponent: CompletionScoreComponent {
  let name: String
  let instance: String
  let scoreComponent: Double
}

internal let unknownScore = 0.750
internal let inapplicableScore = 1.000
internal let unspecifiedScore = 1.000

private let localVariableScore = CompletionKind.variable.scoreComponent * ScopeProximity.local.scoreComponent
private let globalTypeScore = CompletionKind.type.scoreComponent * ScopeProximity.global.scoreComponent
internal let localVariableToGlobalTypeScoreRatio = localVariableScore / globalTypeScore

extension CompletionKind: CompletionScoreComponent {
  fileprivate var name: String { "CompletionKind" }
  fileprivate var instance: String { "\(self)" }
  fileprivate var scoreComponent: Double {
    switch self {
    case .keyword: return 1.000
    case .enumCase: return 1.100
    case .variable: return 1.075
    case .initializer: return 1.020
    case .argumentLabels: return 2.000
    case .function: return 1.025
    case .type: return 1.025
    case .template: return 1.100
    case .module: return 0.925
    case .other: return 1.000

    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}

extension Flair: CompletionScoreComponent {
  fileprivate var name: String { "Flair" }
  fileprivate var instance: String { "\(self.debugDescription)" }
  internal var scoreComponent: Double {
    var total = 1.0
    if self.contains(.oldExpressionSpecific_pleaseAddSpecificCaseToThisEnum) {
      total *= 1.5
    }
    if self.contains(.chainedCallToSuper) {
      total *= 1.5
    }
    if self.contains(.chainedMember) {
      total *= 0.3
    }
    if self.contains(.swiftUIModifierOnSelfWhileBuildingSelf) {
      total *= 0.3
    }
    if self.contains(.swiftUIUnlikelyViewMember) {
      total *= 0.125
    }
    if self.contains(.commonKeywordAtCurrentPosition) {
      total *= 1.25
    }
    if self.contains(.rareKeywordAtCurrentPosition) {
      total *= 0.75
    }
    if self.contains(.rareTypeAtCurrentPosition) {
      total *= 0.75
    }
    if self.contains(.expressionAtNonScriptOrMainFileScope) {
      total *= 0.125
    }
    if self.contains(.rareMemberWithCommonName) {
      total *= 0.75
    }
    if self.contains(._situationallyLikely) {
      total *= 1.25
    }
    if self.contains(._situationallyUnlikely) {
      total *= 0.75
    }
    if self.contains(._situationallyInvalid) {
      total *= 0.125
    }
    return total
  }
}

extension ModuleProximity: CompletionScoreComponent {
  fileprivate var name: String { "ModuleProximity" }
  fileprivate var instance: String { "\(self)" }
  fileprivate var scoreComponent: Double {
    switch self {
    case .imported(0): return 1.0500
    case .imported(1): return 1.0250
    case .imported(_): return 1.0125
    case .importable: return 0.5000
    case .invalid: return 0.2500

    case .inapplicable: return inapplicableScore
    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}

extension ScopeProximity: CompletionScoreComponent {
  fileprivate var name: String { "ScopeProximity" }
  fileprivate var instance: String { "\(self)" }
  fileprivate var scoreComponent: Double {
    switch self {
    case .local: return 1.500
    case .argument: return 1.450
    case .container: return 1.350
    case .inheritedContainer: return 1.325
    case .outerContainer: return 1.325
    case .global: return 0.950

    case .inapplicable: return inapplicableScore
    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}

extension StructuralProximity: CompletionScoreComponent {
  fileprivate var name: String { "StructuralProximity" }
  fileprivate var instance: String { "\(self)" }
  fileprivate var scoreComponent: Double {
    switch self {
    case .project(fileSystemHops: 0): return 1.010
    case .project(fileSystemHops: 1): return 1.005
    case .project(fileSystemHops: _): return 1.000
    case .sdk: return 0.995

    case .inapplicable: return inapplicableScore
    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}

extension SynchronicityCompatibility: CompletionScoreComponent {
  fileprivate var name: String { "SynchronicityCompatibility" }
  fileprivate var instance: String { "\(self)" }
  fileprivate var scoreComponent: Double {
    switch self {
    case .compatible: return 1.00
    case .convertible: return 0.90
    case .incompatible: return 0.50

    case .inapplicable: return inapplicableScore
    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}

extension TypeCompatibility: CompletionScoreComponent {
  fileprivate var name: String { "TypeCompatibility" }
  fileprivate var instance: String { "\(self)" }
  fileprivate var scoreComponent: Double {
    switch self {
    case .compatible: return 1.300
    case .unrelated: return 0.900
    case .invalid: return 0.300

    case .inapplicable: return inapplicableScore
    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}

extension Availability: CompletionScoreComponent {
  fileprivate var name: String { "Availability" }
  fileprivate var instance: String { "\(self)" }
  internal var scoreComponent: Double {
    switch self {
    case .available: return 1.00
    case .unavailable: return 0.40
    case .softDeprecated,
      .deprecated:
      return 0.50

    case .inapplicable: return inapplicableScore
    case .unspecified: return unspecifiedScore
    case .unknown: return unknownScore
    }
  }
}
