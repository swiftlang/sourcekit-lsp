//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import XCTest

struct FoldingRangeSpec {
  let startMarker: String
  let endMarker: String
  let kind: FoldingRangeKind?

  /// The test file in which this ``FoldingRangeSpec`` was created
  let originatorFile: StaticString
  /// The line in which this ``FoldingRangeSpec`` was created
  let originatorLine: UInt

  init(
    from startMarker: String,
    to endMarker: String,
    kind: FoldingRangeKind? = nil,
    originatorFile: StaticString = #file,
    originatorLine: UInt = #line
  ) {
    self.startMarker = startMarker
    self.endMarker = endMarker
    self.kind = kind
    self.originatorFile = originatorFile
    self.originatorLine = originatorLine
  }
}

func assertFoldingRanges(
  markedSource: String,
  expectedRanges: [FoldingRangeSpec],
  rangeLimit: Int? = nil,
  lineFoldingOnly: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let capabilities = ClientCapabilities(
    textDocument: TextDocumentClientCapabilities(
      foldingRange: TextDocumentClientCapabilities.FoldingRange(
        rangeLimit: rangeLimit,
        lineFoldingOnly: lineFoldingOnly
      )
    )
  )
  let testClient = try await TestSourceKitLSPClient(capabilities: capabilities)
  let uri = DocumentURI(for: .swift)
  let positions = testClient.openDocument(markedSource, uri: uri)
  let foldingRanges = try unwrap(await testClient.send(FoldingRangeRequest(textDocument: TextDocumentIdentifier(uri))))
  if foldingRanges.count != expectedRanges.count {
    XCTFail(
      """
      Expected \(expectedRanges.count) ranges but got \(foldingRanges.count)

      \(foldingRanges)
      """,
      file: file,
      line: line
    )
    return
  }
  for (expected, actual) in zip(expectedRanges, foldingRanges) {
    let startPosition = positions[expected.startMarker]
    let endPosition = positions[expected.endMarker]
    let expectedRange = FoldingRange(
      startLine: startPosition.line,
      startUTF16Index: lineFoldingOnly ? nil : startPosition.utf16index,
      endLine: endPosition.line,
      endUTF16Index: lineFoldingOnly ? nil : endPosition.utf16index,
      kind: expected.kind,
      collapsedText: nil
    )
    XCTAssertEqual(actual, expectedRange, file: expected.originatorFile, line: expected.originatorLine)
  }
}

final class FoldingRangeTests: XCTestCase {
  func testNoRanges() async throws {
    try await assertFoldingRanges(markedSource: "", expectedRanges: [])
  }

  func testLineFolding() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣func foo() {
        2️⃣
        }
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣")
      ],
      lineFoldingOnly: true
    )
  }

  func testLineFoldingOfFunctionWithMultiLineParameters() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣func foo(
        2️⃣  param: Int
        3️⃣) {
          print(param)
        4️⃣
        }
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣"),
      ],
      lineFoldingOnly: true
    )
  }

  func testLineFoldingOfComment() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣// abc
        // def
        2️⃣// ghi

        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣", kind: .comment)
      ],
      lineFoldingOnly: true
    )
  }

  func testLineFoldingOfCommentAtEndOfFile() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣// abc
        // def
        2️⃣// ghi
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣", kind: .comment)
      ],
      lineFoldingOnly: true
    )
  }

  func testLineFoldingDoesntReportSingleLine() async throws {
    try await assertFoldingRanges(
      markedSource: """
        guard a > 0 else { 1️⃣return 2️⃣}
        """
      ,
      expectedRanges: [],
      lineFoldingOnly: true
    )
  }

  func testRangeLimit() async throws {
    let input = """
      func one() -> 1 {1️⃣
        return 1
      2️⃣}

      func two() -> Int {3️⃣
        return 2
      4️⃣}

      func three() -> Int {5️⃣
        return 3
      6️⃣}
      """

    try await assertFoldingRanges(markedSource: input, expectedRanges: [], rangeLimit: -100)
    try await assertFoldingRanges(markedSource: input, expectedRanges: [], rangeLimit: 0)
    try await assertFoldingRanges(
      markedSource: input,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣")
      ],
      rangeLimit: 1
    )
    try await assertFoldingRanges(
      markedSource: input,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣"),
      ],
      rangeLimit: 2
    )

    let allRanges = [
      FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
      FoldingRangeSpec(from: "3️⃣", to: "4️⃣"),
      FoldingRangeSpec(from: "5️⃣", to: "6️⃣"),
    ]
    try await assertFoldingRanges(markedSource: input, expectedRanges: allRanges, rangeLimit: 100)
    try await assertFoldingRanges(markedSource: input, expectedRanges: allRanges, rangeLimit: nil)

  }

  func testMultilineDocBlockComment() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣/**
        DC2

        - Parameter param: DC2

        - Throws: DC2
        DC2
        DC2

        - Returns: DC2
        */2️⃣
        """
      ,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣", kind: .comment)
      ]
    )
  }

  func testTwoDifferentCommentStyles() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣//c1
        //c22️⃣
        3️⃣/*
         c3
        */4️⃣
        """
      ,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣", kind: .comment),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣", kind: .comment),
      ]
    )
  }

  func testMultilineDocLineComment() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣/// Do some fancy stuff
        ///
        /// This does very fancy stuff. Use it when building a great app.2️⃣
        """
      ,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣", kind: .comment)
      ]
    )
  }

  func testConsecutiveLineCommentsSeparatedByEmptyLine() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣// Some comment
        // And some more test 2️⃣

        3️⃣// And another comment separated by newlines4️⃣
        func foo() {}
        """
      ,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣", kind: .comment),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣", kind: .comment),
      ]
    )
  }

  func testFoldGuardBody() async throws {
    try await assertFoldingRanges(
      markedSource: """
        guard a > 0 else {1️⃣ return 2️⃣}
        """
      ,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣")
      ]
    )
  }

  func testDontReportDuplicateRangesRanges() async throws {
    // In this file the range of the call to `print` and the range of the argument are the same.
    // Test that we only report the folding range once.
    try await assertFoldingRanges(
      markedSource: """
        func foo() {1️⃣
          print(2️⃣"hello world"3️⃣)
        4️⃣}
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "4️⃣"),
        FoldingRangeSpec(from: "2️⃣", to: "3️⃣"),
      ]
    )
  }

  func testFoldCollections() async throws {
    try await assertFoldingRanges(
      markedSource: """
        let x = [1️⃣1, 2, 32️⃣]
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣")
      ]
    )

    try await assertFoldingRanges(
      markedSource: """
        let x = [1️⃣
          1: "one",
          2: "two",
          3: "three"
        2️⃣]
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣")
      ]
    )
  }

  func testFoldSwitchCase() async throws {
    try await assertFoldingRanges(
      markedSource: """
        switch foo {1️⃣
        case 1:2️⃣
          break 3️⃣
        default:4️⃣
          let x = 1
          print(5️⃣x6️⃣)7️⃣
        8️⃣}
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "8️⃣"),
        FoldingRangeSpec(from: "2️⃣", to: "3️⃣"),
        FoldingRangeSpec(from: "4️⃣", to: "7️⃣"),
        FoldingRangeSpec(from: "5️⃣", to: "6️⃣"),
      ]
    )
  }

  func testFoldArgumentLabelsOnMultipleLines() async throws {
    try await assertFoldingRanges(
      markedSource: """
        print(1️⃣
          "x"
        2️⃣)
        """,
      expectedRanges: [FoldingRangeSpec(from: "1️⃣", to: "2️⃣")]
    )
  }

  func testFoldCallWithTrailingClosure() async throws {
    try await assertFoldingRanges(
      markedSource: """
        doSomething(1️⃣normalArg: 12️⃣) {3️⃣
          _ = $0
        4️⃣}
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣"),
      ]
    )
  }

  func testFoldCallWithMultipleTrailingClosures() async throws {
    try await assertFoldingRanges(
      markedSource: """
        doSomething(1️⃣normalArg: 12️⃣) {3️⃣
          _ = $0
        4️⃣}
        additionalTrailing: {5️⃣
          _ = $0
        6️⃣}
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣"),
        FoldingRangeSpec(from: "5️⃣", to: "6️⃣"),
      ]
    )
  }

  func testFoldArgumentsOfFunction() async throws {
    try await assertFoldingRanges(
      markedSource: """
        func foo(1️⃣
          arg1: Int,
          arg2: Int
        2️⃣)
        """,
      expectedRanges: [FoldingRangeSpec(from: "1️⃣", to: "2️⃣")]
    )
  }

  func testFoldArgumentsForConditionalIfCompileDirectives() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣#if DEBUG
            let foo = "x"
        2️⃣#endif
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣")
      ]
    )
  }

  func testFoldArgumentsForConditionalElseIfCompileDirectives() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣#if DEBUG
          let foo = "x"
        2️⃣#elseif TEST
          let foo = "y"
        3️⃣#else
          let foo = "z"
        4️⃣#endif
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
        FoldingRangeSpec(from: "2️⃣", to: "3️⃣"),
        FoldingRangeSpec(from: "3️⃣", to: "4️⃣"),
      ]
    )
  }

  func testFoldArgumentsForConditionalElseCompileDirectives() async throws {
    try await assertFoldingRanges(
      markedSource: """
        1️⃣#if DEBUG
          let foo = "x"
        2️⃣#else
          let foo = "y"
        3️⃣#endif
        """,
      expectedRanges: [
        FoldingRangeSpec(from: "1️⃣", to: "2️⃣"),
        FoldingRangeSpec(from: "2️⃣", to: "3️⃣"),
      ]
    )
  }
}
