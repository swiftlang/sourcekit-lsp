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
import SwiftExtensions

package struct RepeatableRandomNumberGenerator: RandomNumberGenerator {
  private let seed: [UInt64]
  private static let startIndex = (0, 1, 2, 3)
  private var nextIndex = Self.startIndex

  package init() {
    self.seed = try! PropertyListDecoder().decode(
      [UInt64].self,
      from: loadTestResource(name: "RandomSeed", withExtension: "plist")
    )
  }

  @discardableResult
  func increment(value: inout Int, range: Range<Int>) -> Bool {
    value += 1
    let wrapped = (value == range.upperBound)
    if wrapped {
      value = range.lowerBound
    }
    return wrapped
  }

  mutating func advance() {
    // This iterates through "K choose N" or "seed.count choose 4" unique combinations of 4 seed indexes. Given 1024 values in seed, that produces 45,545,029,376 unique combination of the values.
    if increment(value: &nextIndex.3, range: (nextIndex.2 + 1)..<(seed.count - 0)) {
      if increment(value: &nextIndex.2, range: (nextIndex.1 + 1)..<(seed.count - 1)) {
        if increment(value: &nextIndex.1, range: (nextIndex.0 + 1)..<(seed.count - 2)) {
          if increment(value: &nextIndex.0, range: 0..<(seed.count - 3)) {
            nextIndex = Self.startIndex
            return
          }
          nextIndex.1 = (nextIndex.0 + 1)
        }
        nextIndex.2 = (nextIndex.1 + 1)
      }
      nextIndex.3 = (nextIndex.2 + 1)
    }
  }

  package mutating func next() -> UInt64 {
    let result = seed[nextIndex.0] ^ seed[nextIndex.1] ^ seed[nextIndex.2] ^ seed[nextIndex.3]
    advance()
    return result
  }

  static func generateSeed() {
    let numbers: [UInt64] = (0..<1024).map { _ in
      let lo = UInt64.random(in: 0...UInt64.max)
      let hi = UInt64.random(in: 0...UInt64.max)
      return (hi << 32) | lo
    }
    let header =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <array>
      """
    let body = numbers.map { number in "    <integer>\(number)</integer>" }
    let footer =
      """
      </array>
      </plist>
      """

    print(([header] + body + [footer]).joined(separator: "\n"))
  }

  package mutating func randomLowercaseASCIIString(lengthRange: ClosedRange<Int>) -> String {
    let length = lengthRange.randomElement(using: &self)
    let utf8Bytes = (0..<length).map { _ in
      UTF8Byte.lowercaseAZ.randomElement(using: &self)
    }
    return String(bytes: utf8Bytes, encoding: .utf8).unwrap(orFail: "ASCII strings are always valid UTF8 sequences")
  }

  package mutating func randomLowercaseASCIIStrings(
    countRange: ClosedRange<Int>,
    lengthRange: ClosedRange<Int>
  ) -> [String] {
    let count = countRange.randomElement(using: &self)
    var strings: [String] = []
    for _ in (0..<count) {
      strings.append(randomLowercaseASCIIString(lengthRange: lengthRange))
    }
    return strings
  }
}

/// The bundle of the currently executing test.
private let testBundle: Bundle = {
  #if os(macOS)
  if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
    return bundle
  }
  fatalError("couldn't find the test bundle")
  #else
  return Bundle.main
  #endif
}()

/// The path to the built products directory, ie. `.build/debug/arm64-apple-macosx` or the platform-specific equivalent.
private let productsDirectory: URL = {
  #if os(macOS)
  return testBundle.bundleURL.deletingLastPathComponent()
  #else
  return testBundle.bundleURL
  #endif
}()

/// The path to the INPUTS directory of shared test projects.
private let skTestSupportInputsDirectory: URL = {
  #if os(macOS)
  var resources =
    productsDirectory
    .appending(components: "SourceKitLSP_CompletionScoringTestSupport.bundle", "Contents", "Resources")
  if !FileManager.default.fileExists(at: resources) {
    // Xcode and command-line swiftpm differ about the path.
    resources.deleteLastPathComponent()
    resources.deleteLastPathComponent()
  }
  #else
  let resources =
    productsDirectory
    .appending(component: "SourceKitLSP_CompletionScoringTestSupport.resources")
  #endif
  guard FileManager.default.fileExists(at: resources) else {
    fatalError("missing resources \(resources)")
  }
  return resources.appending(component: "INPUTS", directoryHint: .isDirectory).standardizedFileURL
}()

func loadTestResource(name: String, withExtension ext: String) throws -> Data {
  let file =
    skTestSupportInputsDirectory
    .appending(component: "\(name).\(ext)")
  return try Data(contentsOf: file)
}

extension ClosedRange {
  func randomElement<Generator: RandomNumberGenerator>(using randomness: inout Generator) -> Element {
    return randomElement(using: &randomness)!  // Closed ranges always have a value
  }
}
