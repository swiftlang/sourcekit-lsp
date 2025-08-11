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

// TODO: deprecate
//@available(*, deprecated, message: "Use PopularityIndex instead.")
package struct PopularityTable {
  /// Represents a list of symbols form a module, with a value for each symbol representing what % of references to this module were to that symbol.
  package struct ModuleSymbolReferenceTable {
    var symbolReferencePercentages: [String: Double]
    var notoriousSymbols: [String]
    package init(symbolReferencePercentages: [String: Double], notoriousSymbols: [String] = []) {
      self.symbolReferencePercentages = symbolReferencePercentages
      self.notoriousSymbols = notoriousSymbols
    }
  }

  /// package so `PopularityTable` can be serialized into an XPC object to be sent to the SourceKit plugin
  package private(set) var symbolPopularity: [String: Popularity] = [:]
  package private(set) var modulePopularity: [String: Popularity] = [:]

  /// Only to be used in the SourceKit plugin when deserializing a `PopularityTable` from an XPC object.
  package init(symbolPopularity: [String: Popularity], modulePopularity: [String: Popularity]) {
    self.symbolPopularity = symbolPopularity
    self.modulePopularity = modulePopularity
  }

  /// Initialize with popular symbol usage statistics, a list of recent completions, and module notoriety.
  /// - Parameters:
  ///   - moduleSymbolReferenceTables: The symbol reference statistics should include the popular symbols for each
  ///     module.
  ///   - recentCompletions: A list of recent completions, with repetitions, with the earliest completions at the head
  ///     of the list.
  ///   - popularModules: Symbols from these modules will get a slight bonus.
  ///   - notoriousModules: symbols from these modules will get a significant penalty.
  package init(
    moduleSymbolReferenceTables: [ModuleSymbolReferenceTable],
    recentCompletions: [String],
    popularModules: [String],
    notoriousModules: [String]
  ) {
    recordPopularSymbolsBonuses(modules: moduleSymbolReferenceTables)
    recordNotoriousSymbolsBonuses(modules: moduleSymbolReferenceTables)
    recordSymbolRecencyBonuses(recentCompletions: recentCompletions)
    recordPopularModules(popularModules: popularModules)
    recordNotoriousModules(notoriousModules: notoriousModules)
  }

  /// Takes value from 0...1
  private func scoreComponent(normalizedPopularity: Double) -> Double {
    let maxPopularityBonus = 1.10
    let minPopularityBonus = 1.02
    return (normalizedPopularity * (maxPopularityBonus - minPopularityBonus)) + minPopularityBonus
  }

  private mutating func recordPopularSymbolsBonuses(modules: [ModuleSymbolReferenceTable]) {
    for module in modules {
      if let maxReferencePercentage = module.symbolReferencePercentages.map(\.value).max() {
        for (symbol, referencePercentage) in module.symbolReferencePercentages {
          let normalizedScore = referencePercentage / maxReferencePercentage  // 0...1
          let flattenedScore = pow(normalizedScore, 0.25)  // Don't make it so much of a winner takes all
          symbolPopularity.record(
            scoreComponent: scoreComponent(normalizedPopularity: flattenedScore),
            for: symbol
          )
        }
      }
    }
  }

  /// Record recency so that repeated use also impacts score. Completing `NSString` 100 times, then completing
  /// `NSStream` once should not make `NSStream` the top result.
  private mutating func recordSymbolRecencyBonuses(recentCompletions: [String]) {
    var pointsPerFilterText: [String: Int] = [:]
    let count = recentCompletions.count
    var totalPoints = 0
    for (position, filterText) in recentCompletions.enumerated() {
      let points = count - position
      pointsPerFilterText[filterText, default: 0] += points
      totalPoints += points
    }
    for (filterText, points) in pointsPerFilterText {
      let bonus = scoreComponent(normalizedPopularity: Double(points) / Double(totalPoints))
      symbolPopularity.record(scoreComponent: bonus, for: filterText)
    }
  }

  internal mutating func recordPopularModules(popularModules: [String]) {
    let scoreComponent = scoreComponent(normalizedPopularity: 0.0)
    for module in popularModules {
      modulePopularity.record(scoreComponent: scoreComponent, for: module)
    }
  }

  internal mutating func recordNotoriousModules(notoriousModules: [String]) {
    for module in notoriousModules {
      modulePopularity.record(scoreComponent: Availability.deprecated.scoreComponent, for: module)
    }
  }

  internal mutating func record(notoriousSymbols: [String]) {
    for symbol in notoriousSymbols {
      symbolPopularity.record(scoreComponent: Availability.deprecated.scoreComponent, for: symbol)
    }
  }

  private mutating func recordNotoriousSymbolsBonuses(modules: [ModuleSymbolReferenceTable]) {
    for module in modules {
      record(notoriousSymbols: module.notoriousSymbols)
    }
  }

  private func popularity(symbol: String) -> Popularity {
    return symbolPopularity[symbol] ?? .none
  }

  private func popularity(module: String) -> Popularity {
    return modulePopularity[module] ?? .none
  }

  package func popularity(symbol: String?, module: String?) -> Popularity {
    let symbolPopularity = symbol.map { popularity(symbol: $0) } ?? .none
    let modulePopularity = module.map { popularity(module: $0) } ?? .none
    return Popularity(
      symbolComponent: symbolPopularity.scoreComponent,
      moduleComponent: modulePopularity.scoreComponent
    )
  }
}

extension [String: Popularity] {
  fileprivate mutating func record(scoreComponent: Double, for key: String) {
    let leastPopular = Popularity(scoreComponent: -Double.infinity)
    if self[key, default: leastPopular].scoreComponent < scoreComponent {
      self[key] = Popularity(scoreComponent: scoreComponent)
    }
  }
}

// TODO: deprecate
//@available(*, deprecated, message: "Use PopularityIndex instead.")
extension PopularityTable {
  package init(popularSymbols: [String] = [], recentSymbols: [String] = [], notoriousSymbols: [String] = []) {
    add(popularSymbols: popularSymbols)
    recordSymbolRecencyBonuses(recentCompletions: recentSymbols)
    record(notoriousSymbols: notoriousSymbols)
  }

  package mutating func add(popularSymbols: [String]) {
    for (index, symbol) in popularSymbols.enumerated() {
      let popularity = (1.0 - (Double(index) / Double(popularSymbols.count + 1)))  // 1.0...0.0
      let scoreComponent = scoreComponent(normalizedPopularity: popularity)
      symbolPopularity.record(scoreComponent: scoreComponent, for: symbol)
    }
  }
}

// TODO: deprecate
//@available(*, deprecated, message: "Use PopularityIndex instead.")
extension PopularityTable {
  @available(
    *,
    renamed: "ModuleSymbolReferenceTable",
    message: "Popularity is now for modules in addition to symbols. This was renamed to be more precise."
  )
  package typealias ModulePopularityTable = ModuleSymbolReferenceTable

  @available(*, deprecated, message: "Pass a module name with popularity(symbol:module:)")
  package func popularity(for symbol: String) -> Popularity {
    popularity(symbol: symbol, module: nil)
  }

  @available(*, deprecated, message: "Pass popularModules: and notoriousModules:")
  package init(modules: [ModuleSymbolReferenceTable], recentCompletions: [String]) {
    self.init(
      moduleSymbolReferenceTables: modules,
      recentCompletions: recentCompletions,
      popularModules: [],
      notoriousModules: []
    )
  }
}
