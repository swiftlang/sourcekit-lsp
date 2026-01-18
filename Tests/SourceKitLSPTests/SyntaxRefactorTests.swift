//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKLogging
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import SwiftLanguageService
import SwiftParser
import SwiftRefactor
import SwiftSyntax
import XCTest

fileprivate extension Range where Bound == AbsolutePosition {
  init(_ position: AbsolutePosition) {
    self = position..<position
  }
}

final class SyntaxRefactorTests: SourceKitLSPTestCase {
  func testAddDocumentationRefactor() throws {
    try assertRefactor(
      """
        1️⃣func 2️⃣refactor(syntax: DeclSyntax, in context: Void) -> DeclSyntax? { }
      """,
      context: (),
      provider: AddDocumentation.self,
      expected: { positions in
        [
          SourceEdit(
            range: Range(positions["1️⃣"]!),
            replacement: """
              /// A description
                /// - Parameters:
                ///   - syntax:
                ///   - context:
                ///
                /// - Returns:
                \("")
              """
          )
        ]
      }
    )
  }

  func testAddDocumentationRefactorSingleParameter() throws {
    try assertRefactor(
      """
        1️⃣func 2️⃣refactor(syntax: DeclSyntax) { }
      """,
      context: (),
      provider: AddDocumentation.self,
      expected: { positions in
        [
          SourceEdit(
            range: Range(positions["1️⃣"]!),
            replacement: """
              /// A description
                /// - Parameter syntax:
                \("")
              """
          )
        ]
      }
    )
  }

  func testConvertJSONToCodableStructClosure() throws {
    try assertRefactor(
      """
      1️⃣{
         3️⃣"name": "Produce",
         "shelves": [
             {
                 "name": "Discount Produce",
                 "product": {
                     "name": "Banana",
                     "points": 200,
                     "description": "A banana that's perfectly ripe."
                 }
             }
         ]
      }2️⃣
      """,
      context: (),
      provider: ConvertJSONToCodableStruct.self,
      expected: { positions in
        [
          SourceEdit(
            range: positions["1️⃣"]!..<positions["2️⃣"]!,
            replacement: """
              struct JSONValue: Codable {
                  var name: String
                  var shelves: [Shelves]

                  struct Shelves: Codable {
                      var name: String
                      var product: Product

                      struct Product: Codable {
                          var description: String
                          var name: String
                          var points: Double
                      }
                  }
              }
              """
          )
        ]
      },
      checkMarkers: ["1️⃣", "3️⃣"]
    )
  }

  func testConvertJSONToCodableStructLiteral() throws {
    try assertRefactor(
      #"""
      1️⃣"""
        3️⃣{
           "name": "Produce",
           "shelves": [
               {
                   "name": "Discount Produce",
                   "product": {
                       "name": "Banana",
                       "points": 200,
                       "description": "A banana that's perfectly ripe."
                   }
               }
           ]
        }
        """2️⃣
      """#,
      context: (),
      provider: ConvertJSONToCodableStruct.self,
      expected: { positions in
        [
          SourceEdit(
            range: Range(positions["2️⃣"]!),
            replacement: """

              struct JSONValue: Codable {
                  var name: String
                  var shelves: [Shelves]

                  struct Shelves: Codable {
                      var name: String
                      var product: Product

                      struct Product: Codable {
                          var description: String
                          var name: String
                          var points: Double
                      }
                  }
              }
              """
          )
        ]
      },
      checkMarkers: ["1️⃣", "3️⃣"]
    )
  }

  func testConvertJSONToCodableStructClosureMerging() throws {
    try assertRefactor(
      """
      1️⃣{
         3️⃣"name": "Store",
         "shelves": [
             {
                 "name": "Discount Produce",
                 "product": {
                     "name": "Banana",
                     "points": 200,
                     "description": "A banana that's perfectly ripe.",
                     "healthy": "true",
                     "delicious": "true",
                     "categories": [ "fruit", "yellow" ]
                 }
             },
             {
                 "name": "Meat",
                 "product": {
                     "name": "steak",
                     "points": 200,
                     "healthy": "false",
                     "delicious": "true",
                     "categories": [ ]
                 }
             },
             {
                 "name": "Cereal aisle",
                 "product": {
                     "name": "Sugarydoos",
                     "points": 0.5,
                     "healthy": "false",
                     "delicious": "maybe",
                     "description": "More sugar than you can imagine."
                 }
             }
         ]
      }2️⃣
      """,
      context: (),
      provider: ConvertJSONToCodableStruct.self,
      expected: { positions in
        [
          SourceEdit(
            range: positions["1️⃣"]!..<positions["2️⃣"]!,
            replacement: """
              struct JSONValue: Codable {
                  var name: String
                  var shelves: [Shelves]

                  struct Shelves: Codable {
                      var name: String
                      var product: Product

                      struct Product: Codable {
                          var categories: [String]
                          var delicious: String
                          var description: String?
                          var healthy: Bool
                          var name: String
                          var points: Double
                      }
                  }
              }
              """
          )
        ]
      },
      checkMarkers: ["1️⃣", "3️⃣"]
    )
  }

  func testConvertJSONToCodableStructIndentation() throws {
    try assertRefactor(
      """
      func test() {
          1️⃣{
              3️⃣"a": 1
          }2️⃣
      }
      """,
      context: (),
      provider: ConvertJSONToCodableStruct.self,
      expected: { positions in
        [
          SourceEdit(
            range: positions["1️⃣"]!..<positions["2️⃣"]!,
            replacement: """
              struct JSONValue: Codable {
                      var a: Double
                  }
              """
          )
        ]
      },
      checkMarkers: ["1️⃣", "3️⃣"]
    )
  }

  func testJSONIndentedWith4SpacesButFileWith2Spaces() throws {
    try assertRefactor(
      """
      func dummy1() {
        print("a")
        print("b")
      }

      func dummy2() {
        print("c")
        print("d")
      }

      func test() {
        if true {
          1️⃣{
              3️⃣"a": 1
          }2️⃣
        }
      }
      """,
      context: (),
      provider: ConvertJSONToCodableStruct.self,
      expected: { positions in
        [
          SourceEdit(
            range: positions["1️⃣"]!..<positions["2️⃣"]!,
            replacement: """
              struct JSONValue: Codable {
                    var a: Double
                  }
              """
          )
        ]
      },
      checkMarkers: ["1️⃣", "3️⃣"]
    )
  }

}

func assertRefactor<R: EditRefactoringProvider>(
  _ input: String,
  context: R.Context,
  provider: R.Type,
  expected: [SourceEdit],
  checkMarkers: [String]? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  try assertRefactor(
    input,
    context: context,
    provider: provider,
    expected: { _ in expected },
    checkMarkers: checkMarkers,
    file: file,
    line: line
  )
}

func assertRefactor<R: EditRefactoringProvider>(
  _ input: String,
  context: R.Context,
  provider: R.Type,
  expected: (_ positions: [String: AbsolutePosition]) -> [SourceEdit],
  checkMarkers: [String]? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let (markers, textWithoutMarkers) = extractMarkers(input)

  var parser = Parser(textWithoutMarkers)
  let sourceFile = SourceFileSyntax.parse(from: &parser)

  let markersToCheck: [(String, AbsolutePosition)]
  if let checkMarkers {
    markersToCheck = checkMarkers.map { marker in
      guard let location = markers[marker] else {
        fatalError("Could not find marker \(marker) in input: \(marker)")
      }
      return (marker, location)
    }
  } else if markers.isEmpty {
    markersToCheck = [("1️⃣", AbsolutePosition(utf8Offset: 0))]
  } else {
    markersToCheck = markers.sorted { $0.key < $1.key }
  }

  for (marker, location) in markersToCheck {
    guard let token = sourceFile.token(at: location) else {
      XCTFail("Could not find token at location \(marker)")
      continue
    }

    let input: R.Input
    if let parentMatch = token.parent?.as(R.Input.self) {
      input = parentMatch
    } else {
      XCTFail("token at \(marker) did not match expected input: \(token)")
      continue
    }

    let positions = markers.reduce(into: [String: AbsolutePosition]()) { result, marker in
      result[marker.key] = marker.value
    }

    try assertRefactor(
      input,
      context: context,
      provider: provider,
      expected: expected(positions),
      at: marker,
      file: file,
      line: line
    )
  }
}

// Borrowed from the swift-syntax library's SwiftRefactor tests.

func assertRefactor<R: EditRefactoringProvider>(
  _ input: R.Input,
  context: R.Context,
  provider: R.Type,
  expected: [SourceEdit],
  at marker: String,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let edits = try? R.textRefactor(syntax: input, in: context)
  guard let edits, !edits.isEmpty else {
    if !expected.isEmpty {
      XCTFail(
        """
        Refactoring at \(marker) produced empty result, expected:
        \(expected)
        """,
        file: file,
        line: line
      )
    }
    return
  }

  if edits.count != expected.count {
    XCTFail(
      """
      Refactoring at \(marker) produced incorrect number of edits, expected \(expected.count) not \(edits.count).

      Actual:
      \(edits.map({ $0.debugDescription }).joined(separator: "\n"))

      Expected:
      \(expected.map({ $0.debugDescription }).joined(separator: "\n"))

      """,
      file: file,
      line: line
    )
    return
  }

  for (actualEdit, expectedEdit) in zip(edits, expected) {
    XCTAssertEqual(
      actualEdit,
      expectedEdit,
      "Incorrect edit, expected \(expectedEdit.debugDescription) but actual was \(actualEdit.debugDescription)",
      file: file,
      line: line
    )
    assertStringsEqualWithDiff(
      actualEdit.replacement,
      expectedEdit.replacement,
      file: file,
      line: line
    )
  }
}

/// Asserts that the two strings are equal, providing Unix `diff`-style output if they are not.
///
/// - Parameters:
///   - actual: The actual string.
///   - expected: The expected string.
///   - message: An optional description of the failure.
///   - additionalInfo: Additional information about the failed test case that will be printed after the diff
///   - file: The file in which failure occurred. Defaults to the file name of the test case in
///     which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this
///     function was called.
private func assertStringsEqualWithDiff(
  _ actual: String,
  _ expected: String,
  _ message: String = "",
  additionalInfo: @autoclosure () -> String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  if actual == expected {
    return
  }
  failStringsEqualWithDiff(
    actual,
    expected,
    message,
    additionalInfo: additionalInfo(),
    file: file,
    line: line
  )
}

/// `XCTFail` with `diff`-style output.
private func failStringsEqualWithDiff(
  _ actual: String,
  _ expected: String,
  _ message: String = "",
  additionalInfo: @autoclosure () -> String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let stringComparison: String

  // Use `CollectionDifference` on supported platforms to get `diff`-like line-based output. On
  // older platforms, fall back to simple string comparison.
  if #available(macOS 10.15, *) {
    let actualLines = actual.components(separatedBy: .newlines)
    let expectedLines = expected.components(separatedBy: .newlines)

    let difference = actualLines.difference(from: expectedLines)

    var result = ""

    var insertions = [Int: String]()
    var removals = [Int: String]()

    for change in difference {
      switch change {
      case .insert(let offset, let element, _):
        insertions[offset] = element
      case .remove(let offset, let element, _):
        removals[offset] = element
      }
    }

    var expectedLine = 0
    var actualLine = 0

    while expectedLine < expectedLines.count || actualLine < actualLines.count {
      if let removal = removals[expectedLine] {
        result += "–\(removal)\n"
        expectedLine += 1
      } else if let insertion = insertions[actualLine] {
        result += "+\(insertion)\n"
        actualLine += 1
      } else {
        result += " \(expectedLines[expectedLine])\n"
        expectedLine += 1
        actualLine += 1
      }
    }

    stringComparison = result
  } else {
    // Fall back to simple message on platforms that don't support CollectionDifference.
    stringComparison = """
      Expected:
      \(expected)

      Actual:
      \(actual)
      """
  }

  var fullMessage = """
    \(message.isEmpty ? "Actual output does not match the expected" : message)
    \(stringComparison)
    """
  if let additional = additionalInfo() {
    fullMessage = """
      \(fullMessage)
      \(additional)
      """
  }
  XCTFail(fullMessage, file: file, line: line)
}
