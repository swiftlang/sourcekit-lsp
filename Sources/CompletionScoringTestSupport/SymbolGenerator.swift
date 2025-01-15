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

import CompletionScoring
import Foundation

package struct SymbolGenerator: Sendable {
  package static let shared = Self()

  struct TermTable {
    struct Entry: Codable {
      var word: String
      var count: Int
    }
    private var replicatedTerms: [String]

    init() throws {
      let entries = try JSONDecoder().decode(
        [Entry].self,
        from: loadTestResource(name: "CommonFunctionTerms", withExtension: "json")
      )
      let repeatedWords: [[String]] = entries.map { entry in
        var word = entry.word
        // Make the first letter lowercase if the word isn't something like 'URL'.
        if word.count > 1 {
          let first = entry.word.startIndex
          let second = entry.word.index(after: first)
          if word[first].isUppercase && !word[second].isUppercase {
            let head = word[first].lowercased()
            let tail = word.dropFirst(1)
            word = head + tail
          }
        }
        return Array(repeating: word, count: entry.count)
      }
      replicatedTerms = Array(repeatedWords.joined())
    }

    func randomTerm(using randomness: inout RepeatableRandomNumberGenerator) -> String {
      replicatedTerms.randomElement(using: &randomness)!
    }
  }

  let termTable = try! TermTable()
  let segmentCountWeights = WeightedChoices([
    (0.5, 1),
    (0.375, 2),
    (0.125, 3),
  ])

  package func randomSegment(
    using randomness: inout RepeatableRandomNumberGenerator,
    capitalizeFirstTerm: Bool
  ) -> String {
    let count = segmentCountWeights.select(using: &randomness)
    return (0..<count).map { index in
      let term = termTable.randomTerm(using: &randomness)
      let capitalize = index > 0 || capitalizeFirstTerm
      return capitalize ? term.capitalized : term
    }.joined()
  }

  package func randomType(using randomness: inout RepeatableRandomNumberGenerator) -> String {
    randomSegment(using: &randomness, capitalizeFirstTerm: true)
  }

  let argumentCountWeights = WeightedChoices([
    (0.333, 0),
    (0.333, 1),
    (0.250, 2),
    (0.083, 3),
  ])

  package struct Function {
    var baseName: String
    var arguments: [Argument]

    package var filterText: String {
      let argPattern: String
      if arguments.hasContent {
        argPattern = arguments.map { argument in
          (argument.label ?? "") + ":"
        }.joined()
      } else {
        argPattern = ""
      }
      return baseName + "(" + argPattern + ")"
    }

    package var displayText: String {
      let argPattern: String
      if arguments.hasContent {
        argPattern = arguments.map { argument in
          (argument.label ?? "_") + ": " + argument.type
        }.joined(separator: ", ")
      } else {
        argPattern = ""
      }
      return baseName + "(" + argPattern + ")"
    }
  }

  struct Argument {
    var label: String?
    var type: String
  }

  let argumentLabeledWeights = WeightedChoices([
    (31 / 32.0, true),
    (01 / 32.0, false),
  ])

  func randomArgument(using randomness: inout RepeatableRandomNumberGenerator) -> Argument {
    let labeled = argumentLabeledWeights.select(using: &randomness)
    let label = labeled ? randomSegment(using: &randomness, capitalizeFirstTerm: false) : nil
    return Argument(label: label, type: randomType(using: &randomness))
  }

  package func randomFunction(using randomness: inout RepeatableRandomNumberGenerator) -> Function {
    let argCount = argumentCountWeights.select(using: &randomness)
    return Function(
      baseName: randomSegment(using: &randomness, capitalizeFirstTerm: false),
      arguments: Array(count: argCount) {
        randomArgument(using: &randomness)
      }
    )
  }

  let initializerCounts = WeightedChoices<Int>([
    (32 / 64.0, 1),
    (16 / 64.0, 2),
    (8 / 64.0, 3),
    (4 / 64.0, 4),
    (2 / 64.0, 5),
    (1 / 64.0, 6),
    (1 / 64.0, 0),
  ])

  let initializerArgumentCounts = WeightedChoices<Int>([
    (512 / 1024.0, 1),
    (256 / 1024.0, 2),
    (128 / 1024.0, 3),
    (64 / 1024.0, 4),
    (58 / 1024.0, 0),
    (4 / 1024.0, 16),
    (2 / 1024.0, 32),
  ])

  package func randomInitializers(
    typeName: String,
    using randomness: inout RepeatableRandomNumberGenerator
  ) -> [Function] {
    let initializerCount = initializerCounts.select(using: &randomness)
    return Array(count: initializerCount) {
      let argumentCount = initializerArgumentCounts.select(using: &randomness)
      let arguments: [Argument] = Array(count: argumentCount) {
        randomArgument(using: &randomness)
      }
      return Function(baseName: typeName, arguments: arguments)
    }
  }

  let capitalizedPatternWeights = WeightedChoices([
    (7 / 8.0, false),
    (1 / 8.0, true),
  ])

  package func randomPatternText(
    lengthRange: Range<Int>,
    using randomness: inout RepeatableRandomNumberGenerator
  ) -> String {
    var text = ""
    while text.count < lengthRange.upperBound {
      text = randomSegment(
        using: &randomness,
        capitalizeFirstTerm: capitalizedPatternWeights.select(using: &randomness)
      )
    }
    let length = lengthRange.randomElement(using: &randomness) ?? 0
    return String(text.prefix(length))
  }

  func randomAPIs(
    functionCount: Int,
    typeCount: Int,
    using randomness: inout RepeatableRandomNumberGenerator
  ) -> [String] {
    let functions = (0..<functionCount).map { _ in randomFunction(using: &randomness) }
    let types = (0..<typeCount).map { _ in randomType(using: &randomness) }
    return functions.map(\.filterText) + types
  }
}
