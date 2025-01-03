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
import Foundation
import XCTest

class BinaryCodingTests: XCTestCase {
  func roundTrip<V: BinaryCodable>(_ encoded: V) throws -> V {
    try V(binaryCodedRepresentation: encoded.binaryCodedRepresentation(contentVersion: 0))
  }

  func testRoundTripping(_ encoded: some BinaryCodable & Equatable) {
    XCTAssertNoThrow(
      try {
        let decoded = try roundTrip(encoded)
        XCTAssertEqual(encoded, decoded)
      }()
    )
  }

  func testRoundTrippingAll(_ encodedValues: [some BinaryCodable & Equatable]) {
    for encodedValue in encodedValues {
      testRoundTripping(encodedValue)
    }
  }

  func testIntegers() {
    func test<I: FiniteInteger>(_ type: I.Type) {
      testRoundTrippingAll([I.min, I(exactly: -1), I.zero, I(exactly: 1), I.max])
    }

    test(Int.self)
    test(Int8.self)
    test(Int16.self)
    test(Int32.self)
    test(Int64.self)
    test(UInt.self)
    test(UInt8.self)
    test(UInt16.self)
    test(UInt32.self)
    test(UInt64.self)
  }

  func testFloats() {
    func test<F: BinaryFloatingPoint & BinaryCodable>(_ type: F.Type) {
      let values = [
        F.zero, F.leastNonzeroMagnitude, F.leastNormalMagnitude, F(1), F.greatestFiniteMagnitude, F.infinity,
      ]
      for value in values {
        testRoundTripping(value)
        testRoundTripping(-value)
      }
      let decodedNan = try? roundTrip(F.nan)
      XCTAssert(decodedNan?.isNaN == true)
    }
    test(Float.self)
    test(Double.self)
  }

  func testBools() {
    testRoundTrippingAll([false, true])
  }

  func testStrings() {
    testRoundTripping("a")
    testRoundTrippingAll(["", "a", "é", " ", "\n", "aa"])
    testRoundTrippingAll(["🤷", "🤷🏻", "🤷🏼", "🤷🏽", "🤷🏾", "🤷🏿", "🤷‍♀️", "🤷🏻‍♀️", "🤷🏼‍♀️", "🤷🏽‍♀️", "🤷🏾‍♀️", "🤷🏿‍♀️", "🤷‍♂️", "🤷🏻‍♂️", "🤷🏼‍♂️", "🤷🏽‍♂️", "🤷🏾‍♂️", "🤷🏿‍♂️"])
  }

  func testArrays() {
    testRoundTrippingAll([[], [0], [0, 1]])
  }

  func testDictionaries() {
    testRoundTrippingAll([[:], [0: false], [0: false, 1: true]])
  }

  func testSemanticClassificationComponents() {
    testRoundTrippingAll([.keyword] as [CompletionKind])
    testRoundTrippingAll(
      [
        .keyword, .enumCase, .variable, .function, .initializer, .argumentLabels, .type, .other, .unknown,
        .unspecified,
      ] as [CompletionKind]
    )
    testRoundTrippingAll([.chainedMember, .commonKeywordAtCurrentPosition] as [Flair])
    testRoundTrippingAll(
      [
        .imported(distance: 0), .imported(distance: 1), .importable, .inapplicable, .unknown, .invalid,
        .unspecified,
      ] as [ModuleProximity]
    )
    testRoundTrippingAll([.none, .unspecified] as [Popularity])
    testRoundTrippingAll(
      [
        .local, .argument, .container, .inheritedContainer, .outerContainer, .global, .inapplicable, .unknown,
        .unspecified,
      ] as [ScopeProximity]
    )
    testRoundTrippingAll(
      [.project(fileSystemHops: nil), .project(fileSystemHops: 1), .sdk, .inapplicable, .unknown, .unspecified]
        as [StructuralProximity]
    )
    testRoundTrippingAll(
      [.compatible, .convertible, .incompatible, .inapplicable, .unknown, .unspecified]
        as [SynchronicityCompatibility]
    )
    testRoundTrippingAll(
      [.compatible, .unrelated, .invalid, .inapplicable, .unknown, .unspecified] as [TypeCompatibility]
    )
    testRoundTrippingAll(
      [.available, .softDeprecated, .deprecated, .unknown, .inapplicable, .unspecified] as [Availability]
    )
    testRoundTripping(
      SemanticClassification(
        availability: .softDeprecated,
        completionKind: .function,
        flair: .chainedCallToSuper,
        moduleProximity: .importable,
        popularity: .unspecified,
        scopeProximity: .container,
        structuralProximity: .sdk,
        synchronicityCompatibility: .convertible,
        typeCompatibility: .compatible
      )
    )
    testRoundTripping(
      SemanticClassification(
        availability: .deprecated,
        completionKind: .type,
        flair: .chainedMember,
        moduleProximity: .imported(distance: 2),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .project(fileSystemHops: 4),
        synchronicityCompatibility: .compatible,
        typeCompatibility: .unrelated
      )
    )
  }
}

protocol FiniteInteger: BinaryInteger, BinaryCodable {
  static var min: Self { get }
  static var max: Self { get }
  static var zero: Self { get }
}

extension Int: FiniteInteger {}
extension Int8: FiniteInteger {}
extension Int16: FiniteInteger {}
extension Int32: FiniteInteger {}
extension Int64: FiniteInteger {}
extension UInt: FiniteInteger {}
extension UInt8: FiniteInteger {}
extension UInt16: FiniteInteger {}
extension UInt32: FiniteInteger {}
extension UInt64: FiniteInteger {}
