//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxCodeActions
import XCTest

final class OpaqueParameterToGenericTests: XCTestCase {
  func testRefactoringFunc() throws {
    let baseline: DeclSyntax = """
      func f(
        x: some P,
        y: [some Hashable & Codable: some Any]
      ) -> some Equatable { }
      """

    let expected: DeclSyntax = """
      func f<T1: P, T2: Hashable & Codable, T3>(
        x: T1,
        y: [T2: T3]
      ) -> some Equatable { }
      """

    try assertRefactor(baseline, context: (), provider: OpaqueParameterToGeneric.self, expected: expected)
  }

  func testRefactoringInit() throws {
    let baseline: DeclSyntax = """
      init<A>(
        x: (some P<A>),
        y: [some Hashable & Codable: some Any]
      ) { }
      """

    let expected: DeclSyntax = """
      init<A, T1: P<A>, T2: Hashable & Codable, T3>(
        x: T1,
        y: [T2: T3]
      ) { }
      """

    try assertRefactor(baseline, context: (), provider: OpaqueParameterToGeneric.self, expected: expected)
  }

  func testRefactoringSubscript() throws {
    let baseline: DeclSyntax = """
      subscript(index: some Hashable) -> String
      """

    let expected: DeclSyntax = """
      subscript<T1: Hashable>(index: T1) -> String
      """

    try assertRefactor(baseline, context: (), provider: OpaqueParameterToGeneric.self, expected: expected)
  }
}
