//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import XCTest

class CompletionScoringTests: XCTestCase {
  func testSelfEvidentPriorities() {
    func assertGreaterThan(_ lhs: SemanticClassification, _ rhs: SemanticClassification) {
      XCTAssertGreaterThan(lhs.score, rhs.score)
    }

    func assertGreaterThanOrEqual(_ lhs: SemanticClassification, _ rhs: SemanticClassification) {
      XCTAssertGreaterThanOrEqual(lhs.score, rhs.score)
    }

    assertGreaterThan(
      .partial(completionKind: .variable, scopeProximity: .local),
      .partial(completionKind: .variable, scopeProximity: .argument)
    )
    assertGreaterThan(
      .partial(completionKind: .variable, scopeProximity: .argument),
      .partial(completionKind: .variable, scopeProximity: .container)
    )
    assertGreaterThan(
      .partial(completionKind: .variable, scopeProximity: .container),
      .partial(completionKind: .variable, scopeProximity: .inheritedContainer)
    )
    assertGreaterThan(
      .partial(completionKind: .variable, scopeProximity: .inheritedContainer),
      .partial(completionKind: .variable, scopeProximity: .global)
    )

    assertGreaterThan(
      .partial(completionKind: .enumCase, scopeProximity: .container),
      .partial(completionKind: .variable, scopeProximity: .container)
    )
    assertGreaterThan(
      .partial(completionKind: .variable, scopeProximity: .container),
      .partial(completionKind: .function, scopeProximity: .container)
    )

    assertGreaterThan(
      .partial(completionKind: .function, flair: [.chainedCallToSuper], scopeProximity: .inheritedContainer),
      .partial(completionKind: .function, scopeProximity: .inheritedContainer)
    )

    assertGreaterThan(
      .partial(completionKind: .variable, scopeProximity: .container),
      .partial(completionKind: .variable, flair: [.chainedMember], scopeProximity: .container)
    )

    assertGreaterThan(
      .partial(completionKind: .function, moduleProximity: .imported(distance: 0)),
      .partial(completionKind: .function, moduleProximity: .imported(distance: 1))
    )

    assertGreaterThan(
      .partial(completionKind: .function, moduleProximity: .imported(distance: 1)),
      .partial(completionKind: .function, moduleProximity: .importable)
    )

    assertGreaterThan(
      .partial(completionKind: .function, structuralProximity: .project(fileSystemHops: 0)),
      .partial(completionKind: .function, structuralProximity: .project(fileSystemHops: 1))
    )

    assertGreaterThan(
      .partial(completionKind: .function, synchronicityCompatibility: .compatible),
      .partial(completionKind: .function, synchronicityCompatibility: .convertible)
    )

    assertGreaterThan(
      .partial(completionKind: .function, synchronicityCompatibility: .convertible),
      .partial(completionKind: .function, synchronicityCompatibility: .incompatible)
    )

    assertGreaterThan(
      .partial(completionKind: .function, typeCompatibility: .compatible),
      .partial(completionKind: .function, typeCompatibility: .unrelated)
    )

    assertGreaterThanOrEqual(
      .partial(availability: .available, completionKind: .function),
      .partial(availability: .deprecated, completionKind: .function)
    )

    assertGreaterThanOrEqual(
      .partial(availability: .deprecated, completionKind: .function),
      .partial(availability: .unavailable, completionKind: .function)
    )

    assertGreaterThan(
      .partial(completionKind: .function, scopeProximity: .global),
      .partial(completionKind: .initializer, scopeProximity: .global)
    )

    assertGreaterThan(
      .partial(completionKind: .argumentLabels, scopeProximity: .global),
      .partial(completionKind: .function, scopeProximity: .container)
    )

    assertGreaterThan(
      .partial(completionKind: .type),
      .partial(completionKind: .module)
    )

    assertGreaterThan(
      .partial(completionKind: .template),
      .partial(completionKind: .variable)
    )
  }

  func testSymbolNotoriety() {
    let stream: PopularityIndex.Symbol = "Foundation.NSStream"
    let string: PopularityIndex.Symbol = "Foundation.NSString"
    PopularityIndex(notoriousSymbols: [string]).expect(stream, >, string)
    PopularityIndex(notoriousSymbols: [stream]).expect(string, >, stream)
  }

  func testTypeReferencePercentages() {
    let stream: PopularityIndex.Symbol = "Foundation.NSStream"
    let string: PopularityIndex.Symbol = "Foundation.NSString"
    PopularityIndex(flatReferencePercentages: [string: 0.25]).expect(string, >, stream)
    PopularityIndex(flatReferencePercentages: [stream: 0.25]).expect(stream, >, string)
  }

  func testModuleCombinesWithReferenceFrequency() {
    let fopen: PopularityIndex.Symbol = "POSIX.fopen"
    let array: PopularityIndex.Symbol = "Swift.Array"
    PopularityIndex(flatReferencePercentages: [fopen: 0.501, array: 0.500], notoriousModules: ["POSIX"]).expect(
      array,
      >,
      fopen
    )
    PopularityIndex(flatReferencePercentages: [fopen: 0.501, array: 0.500], popularModules: ["Swift"]).expect(
      array,
      >,
      fopen
    )
  }

  func testMethodReferencePercentages() {
    let index = PopularityIndex(referencePercentages: [
      "Swift.Array": [
        "count": 0.75,
        "isEmpty": 0.25,
      ],
      "Swift.String": [
        "isEmpty": 0.75,
        "count": 0.25,
      ],
    ])
    index.expect("Swift.Array.count", >, "Swift.String.count")
    index.expect("Swift.String.isEmpty", >, "Swift.Array.isEmpty")
  }

  func testModulePopularity() {
    let index = PopularityIndex(popularModules: ["Swift"], notoriousModules: ["POSIX"])
    index.expect("Mine.Type", >, "POSIX.Type")
    index.expect("Mine.Type", <, "Swift.Type")
    index.expect("Mine.Type", ==, "Yours.Type")
  }

  func testPopularitySerialization() {
    let original = PopularityIndex(
      referencePercentages: [
        "Swift.Array": [
          "count": 0.75,
          "isEmpty": 0.25,
        ],
        "Swift.String": [
          "isEmpty": 0.75,
          "count": 0.25,
        ],
      ],
      popularModules: ["Swift"],
      notoriousModules: ["POSIX"]
    )
    XCTAssertNoThrow(
      try {
        let copy = try PopularityIndex.deserialize(data: original.serialize(version: .initial))
        copy.expect("Swift.Array.count", >, "Swift.array.isEmpty")
        copy.expect("Swift.String.isEmpty", >, "Swift.array.count")
        copy.expect("Swift.Unremarkable", >, "POSIX.Unremarkable")
        XCTAssertEqual(original.symbolPopularity, copy.symbolPopularity)
        XCTAssertEqual(original.modulePopularity, copy.modulePopularity)
      }()
    )
  }
}

extension PopularityIndex {
  func expect(_ lhs: Symbol, _ comparison: (Double, Double) -> Bool, _ rhs: Symbol) {
    XCTAssert(comparison(popularity(of: lhs).scoreComponent, popularity(of: rhs).scoreComponent))
  }
}

extension PopularityIndex.Scope {
  public init(stringLiteral value: StringLiteralType) {
    self.init(string: value)
  }

  public init(string value: StringLiteralType) {
    let splits = value.split(separator: ".").map(String.init)
    if splits.count == 1 {
      self.init(container: nil, module: splits[0])
    } else if splits.count == 2 {
      self.init(container: splits[1], module: splits[0])
    } else {
      preconditionFailure("Invalid scope \(value)")
    }
  }
}

extension PopularityIndex.Scope: ExpressibleByStringLiteral {}

extension PopularityIndex.Symbol {
  public init(stringLiteral value: StringLiteralType) {
    self.init(string: value)
  }

  public init(string value: StringLiteralType) {
    let splits = value.split(separator: ".").map(String.init)
    if splits.count == 2 {
      self.init(name: splits[1], scope: .init(container: nil, module: splits[0]))
    } else if splits.count == 3 {
      self.init(name: splits[2], scope: .init(container: splits[1], module: splits[0]))
    } else {
      preconditionFailure("Invalid symbol name \(value)")
    }
  }
}
extension PopularityIndex.Symbol: ExpressibleByStringLiteral {}

extension PopularityIndex {
  init(
    referencePercentages: [Scope: [String: Double]] = [:],
    notoriousSymbols: [Symbol] = [],
    popularModules: [String] = [],
    notoriousModules: [String] = []
  ) {
    self.init(
      symbolReferencePercentages: referencePercentages,
      notoriousSymbols: notoriousSymbols,
      popularModules: popularModules,
      notoriousModules: notoriousModules
    )
  }

  init(
    flatReferencePercentages: [Symbol: Double],
    notoriousSymbols: [Symbol] = [],
    popularModules: [String] = [],
    notoriousModules: [String] = []
  ) {
    var symbolReferencePercentages: [Scope: [String: Double]] = [:]
    for (symbol, percentage) in flatReferencePercentages {
      symbolReferencePercentages[symbol.scope, default: [:]][symbol.name] = percentage
    }
    self.init(
      symbolReferencePercentages: symbolReferencePercentages,
      notoriousSymbols: notoriousSymbols,
      popularModules: popularModules,
      notoriousModules: notoriousModules
    )
  }
}
