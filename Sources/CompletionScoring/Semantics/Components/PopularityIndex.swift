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

/// A `PopularityIndex` is constructed from symbol reference frequencies and uses that data to bestow
/// `Popularity` bonuses on completions.
package struct PopularityIndex {

  /// The namespace of a symbol.
  ///
  /// Examples
  ///   * `Swift.Array.append(:)` would be `Scope(container: "Array", module: "Swift")`
  ///   * `Swift.Array` would be `Scope(container: nil, module: "Swift")`.
  ///
  /// This library imposes no constraints on formatting `container`. It's entirely up to the client to
  /// decide how precise to be, and how to spell values. They could use `[String]`, `Array<String>`
  /// or `Array`. It only matters that they refer to types consistently. They're also free to model
  /// inner types with strings like `List.Node`.
  package struct Scope: Hashable {
    package var container: String?
    package var module: String

    package init(container: String?, module: String) {
      self.module = module
      self.container = container
    }
  }

  /// A name within a scope.
  ///
  /// Examples
  ///   * `Swift.Array.append(:)` would be:
  ///       * `Symbol(name: "append(:)", scope: Scope(container: "Array", module: "Swift"))`
  ///   * `Swift.Array` would be:
  ///       * `Symbol(name: "Array", scope: Scope(container: nil, module: "Swift"))`
  ///
  /// This library imposes no constraints on formatting `name`. It's entirely up to the client to use
  /// consistent values. For example, they could independently track overloads by including types
  /// in function names, or they could combine all related methods by tracking only function base
  /// names.
  package struct Symbol: Hashable {
    package var name: String
    package var scope: Scope

    package init(name: String, scope: Scope) {
      self.name = name
      self.scope = scope
    }
  }

  package private(set) var symbolPopularity: [Symbol: PopularityScoreComponent] = [:]
  package private(set) var modulePopularity: [String: PopularityScoreComponent] = [:]

  private var knownScopes = Set<Scope>()

  /// Clients can use this to find a relevant `Scope`.
  /// To contruct a `Symbol` to pass to `popularity(of:)`.
  package func isKnownScope(_ scope: Scope) -> Bool {
    return knownScopes.contains(scope)
  }

  /// - Parameters:
  ///     - `symbolReferencePercentages`: Symbol reference percentages per scope.
  ///         For example, if the data that produced the symbol reference percentags had 1 call to `Array.append(:)`,
  ///         3 calls to `Array.count`, and 1 call to `String.append(:)` the table would be:
  ///         ```
  ///         [
  ///             "Swift.Array" : [
  ///                 "append(:)" : 0.25,
  ///                 "count" : 0.75
  ///             ],
  ///             "Swift.String" : [
  ///                 "append(:)" : 1.0
  ///             ]
  ///         ]
  ///         ```
  ///     - `notoriousSymbols`: Symbols from this list will get a significant penalty.
  ///     - `popularModules`: Symbols from these modules will get a slight bonus.
  ///     - `notoriousModules`: symbols from these modules will get a significant penalty.
  package init(
    symbolReferencePercentages: [Scope: [String: Double]],
    notoriousSymbols: [Symbol],
    popularModules: [String],
    notoriousModules: [String]
  ) {
    knownScopes = Set(symbolReferencePercentages.keys)

    raisePopularities(symbolReferencePercentages: symbolReferencePercentages)
    raisePopularities(popularModules: popularModules)

    // Even if data shows that it's popular, if we manually penalized it, always do that.
    lowerPopularities(notoriousModules: notoriousModules)
    lowerPopularities(notoriousSymbols: notoriousSymbols)
  }

  fileprivate init() {}

  private mutating func raisePopularities(symbolReferencePercentages: [Scope: [String: Double]]) {
    for (scope, namedReferencePercentages) in symbolReferencePercentages {
      if let maxReferencePercentage = namedReferencePercentages.lazy.map(\.value).max() {
        for (completion, referencePercentage) in namedReferencePercentages {
          let symbol = Symbol(name: completion, scope: scope)
          let normalizedScore = referencePercentage / maxReferencePercentage  // 0...1
          let flattenedScore = pow(normalizedScore, 0.25)  // Don't make it so much of a winner takes all
          symbolPopularity.raise(
            symbol,
            toAtLeast: Popularity.scoreComponent(probability: flattenedScore, category: .index)
          )
        }
      }
    }
  }

  private mutating func lowerPopularities(notoriousSymbols: [Symbol]) {
    symbolPopularity.lower(notoriousSymbols, toAtMost: Availability.deprecated.scoreComponent)
  }

  private mutating func lowerPopularities(notoriousModules: [String]) {
    modulePopularity.lower(notoriousModules, toAtMost: Availability.deprecated.scoreComponent)
  }

  private mutating func raisePopularities(popularModules: [String]) {
    modulePopularity.raise(popularModules, toAtLeast: Popularity.scoreComponent(probability: 0.0, category: .index))
  }

  package func popularity(of symbol: Symbol) -> Popularity {
    let symbolPopularity = symbolPopularity[symbol] ?? .none
    let modulePopularity = modulePopularity[symbol.scope.module] ?? .none
    return Popularity(symbolComponent: symbolPopularity.value, moduleComponent: modulePopularity.value)
  }
}

fileprivate extension Dictionary where Value == PopularityScoreComponent {
  mutating func raise(_ key: Key, toAtLeast minimum: Double) {
    let leastPopular = PopularityScoreComponent(value: -Double.infinity)
    if self[key, default: leastPopular].value < minimum {
      self[key] = PopularityScoreComponent(value: minimum)
    }
  }

  mutating func lower(_ key: Key, toAtMost maximum: Double) {
    let mostPopular = PopularityScoreComponent(value: Double.infinity)
    if self[key, default: mostPopular].value > maximum {
      self[key] = PopularityScoreComponent(value: maximum)
    }
  }

  mutating func raise(_ keys: [Key], toAtLeast minimum: Double) {
    for key in keys {
      raise(key, toAtLeast: minimum)
    }
  }

  mutating func lower(_ keys: [Key], toAtMost maximum: Double) {
    for key in keys {
      lower(key, toAtMost: maximum)
    }
  }
}

/// Implement coding with BinaryCodable without singing up for package conformance
extension PopularityIndex {
  package enum SerializationVersion: Int {
    case initial
  }

  private struct SerializableSymbol: Hashable, BinaryCodable {
    var symbol: Symbol

    init(symbol: Symbol) {
      self.symbol = symbol
    }

    init(_ decoder: inout BinaryDecoder) throws {
      let name = try String(&decoder)
      let container = try String?(&decoder)
      let module = try String(&decoder)
      symbol = Symbol(name: name, scope: Scope(container: container, module: module))
    }

    func encode(_ encoder: inout BinaryEncoder) {
      encoder.write(symbol.name)
      encoder.write(symbol.scope.container)
      encoder.write(symbol.scope.module)
    }
  }

  package func serialize(version: SerializationVersion) -> [UInt8] {
    BinaryEncoder.encode(contentVersion: version.rawValue) { encoder in
      encoder.write(symbolPopularity.mapKeys(overwritingDuplicates: .affirmative, SerializableSymbol.init))
      encoder.write(modulePopularity)
    }
  }

  package static func deserialize(data serialization: [UInt8]) throws -> Self {
    try BinaryDecoder.decode(bytes: serialization) { decoder in
      switch SerializationVersion(rawValue: decoder.contentVersion) {
      case .initial:
        var index = Self()
        index.symbolPopularity = try [SerializableSymbol: PopularityScoreComponent](&decoder).mapKeys(
          overwritingDuplicates: .affirmative,
          \.symbol
        )
        index.modulePopularity = try [String: PopularityScoreComponent](&decoder)
        return index
      case .none:
        throw GenericError("Unknown \(String(describing: self)) serialization format")
      }
    }
  }
}
