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

class PatternTests: XCTestCase {
  typealias ContentType = Candidate.ContentType
  func testMatches() throws {
    func test(pattern patternText: String, candidate candidateText: String, match expectedMatch: Bool) {
      let pattern = Pattern(text: patternText)
      let actualMatch = Candidate.withAccessToCandidate(for: candidateText, contentType: .codeCompletionSymbol) {
        candidate in
        pattern.matches(candidate: candidate)
      }
      XCTAssertEqual(actualMatch, expectedMatch)
    }
    test(pattern: "", candidate: "", match: true)
    test(pattern: "", candidate: "a", match: true)
    test(pattern: "a", candidate: "a", match: true)
    test(pattern: "a", candidate: "aa", match: true)
    test(pattern: "aa", candidate: "a", match: false)
    test(pattern: "b", candidate: "a", match: false)
    test(pattern: "b", candidate: "ba", match: true)
    test(pattern: "b", candidate: "ab", match: true)
    test(pattern: "ba", candidate: "a", match: false)
    test(pattern: "ba", candidate: "ba", match: true)
    test(pattern: "ab", candidate: "ba", match: false)
    test(pattern: "aaa", candidate: "aabb", match: false)
  }

  func withTokenization<R>(
    of text: String,
    contentType: Pattern.ContentType,
    body: (Pattern.UTF8Bytes, Pattern.Tokenization) throws -> R
  ) rethrows -> R {
    try UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      try text.withUncachedUTF8Bytes { mixedcaseBytes in
        var tokenization = Pattern.Tokenization.allocate(
          mixedcaseBytes: mixedcaseBytes,
          contentType: contentType,
          allocator: &allocator
        ); defer { tokenization.deallocate(allocator: &allocator) }
        return try body(mixedcaseBytes, tokenization)
      }
    }
  }

  func testTokenization() throws {
    func test(text escapedText: String) {
      let expectedTokens = escapedText.isEmpty ? [] : escapedText.components(separatedBy: "|")
      let actualTokens = withTokenization(of: expectedTokens.joined(), contentType: .codeCompletionSymbol) {
        (mixedcaseBytes, tokenization) -> [String] in
        XCTAssertLessThanOrEqual(tokenization.tokens.count, mixedcaseBytes.count)
        XCTAssertEqual(tokenization.byteTokenAddresses.count, mixedcaseBytes.count)
        XCTAssertEqual(tokenization.tokens.map(\.length).sum(), mixedcaseBytes.count)

        var previous: (tokenIndex: Int, indexInToken: Int)? = nil

        for cIdx in 0..<mixedcaseBytes.count {
          let tokenIndex = tokenization.byteTokenAddresses[cIdx].tokenIndex
          let indexInToken = tokenization.byteTokenAddresses[cIdx].indexInToken
          if let previous = previous {
            if tokenIndex == previous.tokenIndex {
              XCTAssertEqual(indexInToken, previous.indexInToken + 1)
            } else {
              XCTAssertEqual(tokenIndex, previous.tokenIndex + 1)
              XCTAssertEqual(indexInToken, 0)
            }
          } else {
            XCTAssertEqual(tokenIndex, 0)
            XCTAssertEqual(indexInToken, 0)
          }
          previous = (tokenIndex: tokenIndex, indexInToken: indexInToken)
        }
        var components: [String] = []
        var position = 0
        let bytes = Array(mixedcaseBytes)
        for token in tokenization.tokens {
          components.append(String(bytes: bytes[position..<(position + token.length)], encoding: .utf8)!)
          position += token.length
        }
        return components
      }
      XCTAssertEqual(actualTokens, expectedTokens)
    }

    test(text: "Mutable|Collection")
    test(text: "function|(|name|:|)")
    test(text: "function|(|_| |name|:|)")
    test(text: "function|(|_|name|:|)")
    test(text: "function|(|_|:|)")
    test(text: "function|(|)")
    test(text: "NS|Array")
    test(text: "")
    test(text: "-")
    test(text: "a|-")
    test(text: "-|a")
    test(text: "-|-")
    test(text: "a")
    test(text: "A")
    test(text: "a|A")
    test(text: "Aa")
    test(text: "AA")
    test(text: "aa")
    test(text: "AAA")
    test(text: "a|-|b")
    test(text: "123")
    test(text: "a123")
    test(text: "a123|A")
    test(text: "MY|Class")
    test(text: "NSURL")
    test(text: "NS|Open|GL|View")
    test(text: "AB|Blah|URL|Test|Control|Integration|.|h")
    test(text: "Git|.|swift")
    test(text: "a|.|h")
    test(text: "_|_|FILEBASENAME|_|_|.|swift")
    test(text: "_|_|FILEBASENAME|_|_|.|swift")
    test(text: "a|.|h")
    test(text: "Git|.|swift")
    test(text: "Git|.|h")
    test(text: ".|history")
    test(text: ".|history|.|log")
    test(text: "my|_|underscore|_|function")
    test(text: "H|Stack")

    test(text: "_|_|_")
    test(text: "_|_|a")
    test(text: "_|_|A")
    test(text: "_|a|_")
    test(text: "_|aa")
    test(text: "_|a|A")
    test(text: "_|A|_")
    test(text: "_|Aa")
    test(text: "_|AA")
    test(text: "a|_|_")
    test(text: "a|_|a")
    test(text: "a|_|A")
    test(text: "aa|_")
    test(text: "aaa")
    test(text: "aa|A")
    test(text: "a|A|_")
    test(text: "a|Aa")
    test(text: "a|AA")
    test(text: "A|_|_")
    test(text: "A|_|a")
    test(text: "A|_|A")
    test(text: "Aa|_")
    test(text: "Aaa")
    test(text: "Aa|A")
    test(text: "AA|_")
    test(text: "A|Aa")
    test(text: "AAA")
  }

  func testTokenizationBaseName() throws {
    func baseName(for text: String, contentType: Pattern.ContentType) throws -> String {
      try withTokenization(of: text, contentType: contentType) { mixedcaseBytes, tokenization in
        return try String(bytes: mixedcaseBytes[..<tokenization.baseNameLength], encoding: .utf8).unwrap(
          orThrow: "Invalid utf8 sequence"
        )
      }
    }
    func test(
      text: String,
      hasBaseName expectedBaseName: String,
      contentType: Pattern.ContentType = .codeCompletionSymbol
    ) {
      try! XCTAssertEqual(baseName(for: text, contentType: contentType), expectedBaseName)
    }
    test(text: "", hasBaseName: "")
    test(text: "a", hasBaseName: "a")
    test(text: "a()", hasBaseName: "a")
    test(text: "ab()", hasBaseName: "ab")
    test(text: "aB()", hasBaseName: "aB")
    test(text: "()", hasBaseName: "")
    test(text: "a_b", hasBaseName: "a_b")
    test(text: "File.h", hasBaseName: "File", contentType: .fileName)
    test(text: "File(Subtitle).h", hasBaseName: "File(Subtitle)", contentType: .fileName)
    test(text: "Type.NestedType.swift", hasBaseName: "Type.NestedType", contentType: .fileName)
  }

  func testHasNonUppercaseNonDelimiterBytesDetection() throws {
    func hasNonUppercaseNonDelimiterBytes(text: String) throws -> Bool {
      withTokenization(of: text, contentType: .codeCompletionSymbol) { mixedcaseBytes, tokenization in
        tokenization.hasNonUppercaseNonDelimiterBytes
      }
    }
    func test(text: String, expecting expectedAllUppercaseValues: Bool) {
      try! XCTAssertEqual(hasNonUppercaseNonDelimiterBytes(text: text), expectedAllUppercaseValues)
    }
    test(text: "", expecting: false)
    test(text: "A", expecting: false)
    test(text: "AB", expecting: false)
    test(text: "_AB", expecting: false)
    test(text: "A_B", expecting: false)
    test(text: "AB_", expecting: false)
    test(text: "__AB", expecting: false)
    test(text: "A__B", expecting: false)
    test(text: "AB__", expecting: false)

    test(text: "", expecting: false)
    test(text: "a", expecting: true)
    test(text: "ab", expecting: true)
    test(text: "_b", expecting: true)
    test(text: "a_b", expecting: true)
    test(text: "ab_", expecting: true)
    test(text: "__ab", expecting: true)
    test(text: "a__b", expecting: true)
    test(text: "ab__", expecting: true)
  }

  func testTokenizationIsUppercaseDetection() throws {
    func allUppercaseValues(text: String) throws -> [Bool] {
      withTokenization(of: text, contentType: .codeCompletionSymbol) { mixedcaseBytes, tokenization in
        tokenization.tokens.map(\.allUppercase)
      }
    }
    func test(text: String, expecting expectedAllUppercaseValues: [Bool]) {
      try! XCTAssertEqual(allUppercaseValues(text: text), expectedAllUppercaseValues)
    }
    test(text: "", expecting: [])
    test(text: "_", expecting: [false])
    test(text: "a", expecting: [false])
    test(text: "a_", expecting: [false, false])
    test(text: "ab_", expecting: [false, false])
    test(text: "abc_", expecting: [false, false])

    test(text: "", expecting: [])
    test(text: "_", expecting: [false])
    test(text: "A", expecting: [true])
    test(text: "A_", expecting: [true, false])
    test(text: "Ab_", expecting: [false, false])
    test(text: "aBc_", expecting: [false, false, false])
    test(text: "abC_", expecting: [false, true, false])

    test(text: "__", expecting: [false, false])
    test(text: "___", expecting: [false, false, false])
    test(text: "____", expecting: [false, false, false, false])
    test(text: "NSManagedObjectContext", expecting: [true, false, false, false])
    test(text: "NSOpenGLView", expecting: [true, false, true, false])
    test(text: "NSWindow.h", expecting: [true, false, false, false])
    test(text: "translatesAutoresizingMaskIntoConstraints", expecting: [false, false, false, false, false])
  }

  func testScoring() throws {
    test("NSW", precision: .thorough, prefers: "NSWindowController", over: "_n_s_w_")
    test("Text", precision: .thorough, prefers: "Text", over: "NSText")
    test("Text", precision: .thorough, prefers: "NSText", over: "QDTextUPP")
    test("Text", precision: .thorough, prefers: "TextField", over: "VM_LIB64_SHR_TEXT")
    test("Text", precision: .thorough, prefers: "TextField", over: "ABC_TEXT")
  }

  func testExhaustiveScoring() throws {
    func test(pattern: String, candidate: String) {
      let fastScore = score(patternText: pattern, candidateText: candidate, precision: .fast)
      let thoroughScore = score(patternText: pattern, candidateText: candidate, precision: .thorough)
      XCTAssertGreaterThan(thoroughScore, fastScore)
    }
    test(pattern: "aaa", candidate: "ababaa")
    test(pattern: "resetDownload", candidate: "resetDocumentDownload")
  }

  func testThoroughScoringBudget() throws {
    let pattern = Pattern(text: "123456789")
    let decoy = "aaaaaaaAaaaAa1a2a3a4a5a6a7a8a9"
    let fogOfWar = String(repeating: "_", count: 1 << 14)
    Candidate.withAccessToCandidate(for: decoy + fogOfWar + "12345678a9", contentType: .codeCompletionSymbol) {
      candidate in
      var ranges: [Pattern.UTF8ByteRange] = []
      _ = pattern.score(
        candidate: candidate.bytes,
        contentType: candidate.contentType,
        precision: .thorough,
        captureMatchingRanges: true,
        ranges: &ranges
      )
      // Budget should have kept us from finding that last match.
      XCTAssertEqual(ranges.count, 9)
    }
  }

  func test77869216() throws {
    test("Im", precision: .thorough, prefers: "ImageIO", over: "IMP")
    test("im", precision: .thorough, prefers: "IMP", over: "ImageIO")
    test("IM", precision: .thorough, prefers: "IMP", over: "ImageIO")
  }

  func testMatchingRanges() throws {
    func test(_ text: String, precision: Pattern.Precision? = nil, testLowercasePattern: Bool = true) throws {
      var text = text
      struct Case {
        var pattern: String
        var candidate: String
        var expectedMatchedRanges: [Range<Int>]
      }
      let testCase: Case = try text.withUTF8 { bytes in
        var bytes = bytes[...]
        var expectedMatchedRanges: [Range<Int>] = []
        var candidatePosition = 0
        var parsePosition = 0
        var candidate = Data()
        var pattern = Data()
        while let parseStart = try bytes.firstIndex(of: UTF8Byte("[")),
          let parseEnd = try bytes.firstIndex(of: UTF8Byte("]"))
        {
          let candidateStart = (parseStart - parsePosition) + candidatePosition
          let matchLength = (parseEnd - parseStart) - 1
          let skippedContentCharacters = parseStart - bytes.startIndex
          expectedMatchedRanges.append(candidateStart ..+ matchLength)
          candidate.append(contentsOf: bytes[..<parseStart])
          candidate.append(contentsOf: bytes[(parseStart + 1)..<parseEnd])
          pattern.append(contentsOf: bytes[parseStart..<parseEnd].dropFirst())
          bytes = bytes[(parseEnd + 1)...]
          candidatePosition += matchLength + skippedContentCharacters
          parsePosition = parseEnd + 1
        }
        candidate.append(contentsOf: bytes)
        let patternText = try String(data: pattern, encoding: .utf8).unwrap(
          orThrow: "Failed to create pattern text"
        )
        let candidateText = try String(data: candidate, encoding: .utf8).unwrap(
          orThrow: "Failed to create pattern text"
        )
        return Case(
          pattern: patternText,
          candidate: candidateText,
          expectedMatchedRanges: expectedMatchedRanges
        )
      }
      Candidate.withAccessToCandidate(for: testCase.candidate, contentType: .codeCompletionSymbol) {
        mixedcaseCandidate in
        let precisions = precision.map { [$0] } ?? [.fast, .thorough]
        let useLowerCaseVariants = testLowercasePattern ? [false, true] : [false]
        for precision in precisions {
          for useLowercasePattern in useLowerCaseVariants {
            let pattern = Pattern(
              text: useLowercasePattern ? testCase.pattern.lowercased() : testCase.pattern
            )
            var ranges: [Pattern.UTF8ByteRange] = []
            _ = pattern.score(
              candidate: mixedcaseCandidate.bytes,
              contentType: mixedcaseCandidate.contentType,
              precision: precision,
              captureMatchingRanges: true,
              ranges: &ranges
            )
            var actualMatchingBuffer: [UTF8Byte] = Array(mixedcaseCandidate.bytes)
            for range in ranges.reversed() {
              actualMatchingBuffer.insert(UTF8ByteValue("]")!, at: range.upperBound)
              actualMatchingBuffer.insert(UTF8ByteValue("[")!, at: range.lowerBound)
            }
            let actualMatching = String(bytes: actualMatchingBuffer, encoding: .utf8)!

            XCTAssertEqual(
              ranges,
              testCase.expectedMatchedRanges,
              "During \(precision) scoring, expected \"\(pattern.text)\" to match like:\n\(text)\nnot:\n\(actualMatching)"
            )
          }
        }
      }
    }

    try test("[aB]d[e]")
    try test("a[bc]")
    try test("N[E]W[S]")
    try test("[A]b")
    try test("[AB]NS[Window]Controller")
    try test("AB[NSWindow]Controller")
    try test("[ABNSWindow]Controller")
    try test("ABNS[WindowController]")
    try test("w i n d o w[Window]")
    try test("ABNS[WindowController]")
    try test("[resetDo]cumentDo[wnload]", precision: .fast)
    try test("[reset]Document[Download]", precision: .thorough)
    try test(
      "splitViewController(_ splitViewController: UISplitViewController, [separateSec]ondaryFrom primaryViewController: UIViewController) -> UIViewController?"
    )
    try test("wwwwwwwiiiiiitttttthhhhhhiiiiiinnnnnn[Within]")
    try test("[t]ranslates[A]utoresizing[M]ask[I]ntoConstraints")
    try test("[t]ranslates[A]utoresizing[M]ask[I]nto[C]onstraints")
    try test("[f]ileurl[URL]")
    try test(
      "[frame]([min]Width:idealWidth:maxWidth:minHeight:idealHeight:[maxH]eight:alignment:)",
      precision: .thorough
    )
    /// PR Feedback Question about the relative strength of case match vs run length
    try test(
      "[frame]([min]Width:idealWidth:[max]Width:min[H]eight:idealHeight:maxheight:alignment:)",
      precision: .thorough,
      testLowercasePattern: false
    )
    try test(
      "[frame](minWidth:idealWidth:maxWidth:minHeight:[idealHeight]:maxheight:alignment:)",
      precision: .thorough
    )
    try test(
      "init(ri_uuid:ri_user_time:ri_system_time:ri_pkg_idle_wkups:ri_interrupt_wkups:ri_pageins:ri_wired_size:ri_[re]sident_[size]:ri_phys_footprint:ri_proc_start_[ab]stime:ri_proc_exit_abstime:ri_child_user_time:ri_child_system_time:ri_child_pkg_idle_wkups:ri_child_interrupt_wkups:ri_child_pageins:ri_child_elapsed_abstime:)",
      precision: .thorough
    )
    // both .thorough and .fast should check for the exact match case, even if .thorough exhausts its budget
    try test("_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_a_[aaa]")
  }

  func testSearchStarts() {
    func test(_ pattern: String, _ candidate: String, _ starts: [Int]) {
      Candidate.withAccessToCandidate(for: candidate, contentType: .codeCompletionSymbol) { candidate in
        XCTAssertEqual(
          Pattern(text: pattern).test_searchStart(candidate: candidate, contentType: .codeCompletionSymbol),
          starts
        )
      }
    }
    test("", "", [])
    test("a", "", [])
    test("a", "a", [1])
    test("a", "aA", [1, 2])
    test("b", "aA", [2, 2])
    test("b", "bA", [2, 2])
    test("b", "aB", [1, 2])
    test("dowork", "doTheWork", [5, 5, 5, 5, 5, 9, 9, 9, 9])
    test("thework", "doTheWork", [2, 2, 5, 5, 5, 9, 9, 9, 9])
    test("dothe", "doTheWork", [2, 2, 9, 9, 9, 9, 9, 9, 9])
  }

  func testUnexpectedScoringCalls() {
    func score(_ patternText: String, _ candidateText: String, precision: Pattern.Precision) -> Double {
      Candidate.withAccessToCandidate(for: candidateText, contentType: .codeCompletionSymbol) { candidate in
        Pattern(text: patternText).score(candidate: candidate, precision: precision)
      }
    }
    for precision in [Pattern.Precision.fast, Pattern.Precision.thorough] {
      XCTAssertEqual(score("", "", precision: precision), 1.0)
      XCTAssertEqual(score("", "a", precision: precision), 1.0)
      XCTAssertEqual(score("", "aa", precision: precision), 1.0)
      XCTAssertEqual(score("a", "", precision: precision), 0.0)
      XCTAssertEqual(score("a", "b", precision: precision), 0.0)
      XCTAssertEqual(score("aa", "a", precision: precision), 0.0)
    }
  }

  func testExactMatchesScoreBetter() {
    test("ab", precision: .thorough, prefers: "ab", over: "abc")
    test("_observers", precision: .thorough, prefers: "_observers", over: "_asdfObservers")
    test("_observers", precision: .thorough, prefers: "_observers", over: "_Observersasdf")
    test("_observers", precision: .thorough, prefers: "_observers", over: "asdf_Observers")
    test("_observers", precision: .thorough, prefers: "_observers", over: "asdf_observers")
  }

  func test9225472() {
    test("hasDe", precision: .thorough, prefers: "hasDetachedOccurrences", over: "bHasDesktopMgr")
    test("hasDe", precision: .thorough, prefers: "hasDetachedOccurrences", over: "bHasDirectIO")
  }

  func testMatchAllCapsPrefix() {
    test("abcoverr", precision: .thorough, prefers: "ABCOverridingProperties", over: "indexOfViewForResizing")
    test(
      "abcoverr",
      precision: .thorough,
      prefers: "ABCOverridingProperties",
      over: "setIndexOfViewForResizing:"
    )
    test("abcoverr", precision: .thorough, prefers: "ABCOverridingProperties", over: "buildSettingOverrides")
  }

  func test88532962() {
    let propertyResult = SemanticScoredText(
      "textColor",
      SemanticClassification(
        availability: .available,
        completionKind: .variable,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .container,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .compatible
      ).score
    )
    let typeResult = SemanticScoredText(
      "Text",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .unrelated
      ).score
    )
    test(completion: propertyResult, alwaysBeats: [typeResult])
  }

  func test88530047() {
    let propertyResult = SemanticScoredText(
      "dataSource",
      SemanticClassification(
        availability: .available,
        completionKind: .variable,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .container,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      ).score
    )
    let typeResult = SemanticScoredText(
      "Data",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      ).score
    )
    test(completion: propertyResult, alwaysBeats: [typeResult])
  }

  func testPreferConsecutiveMatchesBetweenPatternAndCandidate() {
    test(
      "ABStorDocument",
      precision: .thorough,
      prefers: "ABStoryboardDocument",
      over: "ABPrintablePListForDocumentClasses"
    )
  }

  func test(completion expectedWinner: SemanticScoredText, alwaysBeats decoys: [SemanticScoredText]) {
    expectedWinner.text.enumeratePrefixes(includeLowercased: true) { partialPattern in
      for decoy in decoys {
        test(partialPattern, precision: .thorough, prefers: expectedWinner, over: decoy)
      }
    }
  }

  func test68718765() {
    let localVariable = SemanticScoredText(
      "localVariable",
      .partial(
        availability: .available,
        completionKind: .variable,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .local,
        structuralProximity: .sdk,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      )
    )
    let globalEnum = SemanticScoredText(
      "errSecCSBadLVArch",
      .partial(
        availability: .available,
        completionKind: .enumCase,
        flair: [],
        moduleProximity: .imported(distance: 3),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      )
    )
    test(completion: localVariable, alwaysBeats: [globalEnum])
  }

  func test88694877() {
    let classResult = SemanticScoredText(
      "NSLayoutConstraint",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      ).score
    )
    let headerGuardResult = SemanticScoredText(
      "NSLAYOUTCONSTRAINT_H",
      SemanticClassification(
        availability: .available,
        completionKind: .variable,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      ).score
    )
    test(completion: classResult, alwaysBeats: [headerGuardResult])
  }

  func test88694877_2() {
    test("fileName", precision: .thorough, prefers: "fileName", over: "filename")
  }

  func test77934625_1() {
    let popularity = PopularityIndex(referencePercentages: [
      "SwiftUI": [
        "View": 0.250,
        "VStack": 0.025,
        "HStack": 0.025,
        "Button": 0.025,
        "Text": 0.025,
        "Image": 0.025,
        "Label": 0.025,
      ]
    ])
    let view = SemanticScoredText(
      "View",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [.rareTypeAtCurrentPosition],
        moduleProximity: .imported(distance: 1),
        popularity: popularity.popularity(of: "SwiftUI.View"),
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      ).score
    )
    let vstack = SemanticScoredText(
      "VStack",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: popularity.popularity(of: "SwiftUI.VStack"),
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      ).score
    )
    test("V", precision: .thorough, prefers: vstack, over: view)
  }

  func test77934625_2() {
    let popularity = PopularityIndex(referencePercentages: [
      "Swift": [
        "Array": 0.250,
        "Int": 0.125,
        "Dictionary": 0.125,
        "Bool": 0.125,
        "Set": 0.125,
        "Collection": 0.125,
        "Sequence": 0.120,
        "Encoder": 0.005,
      ]
    ])
    let enumResult = SemanticScoredText(
      "enum",
      SemanticClassification(
        availability: .available,
        completionKind: .keyword,
        flair: [.commonKeywordAtCurrentPosition],
        moduleProximity: .inapplicable,
        popularity: .none,
        scopeProximity: .inapplicable,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      ).score
    )
    let extensionResult = SemanticScoredText(
      "extension",
      SemanticClassification(
        availability: .available,
        completionKind: .keyword,
        flair: [.commonKeywordAtCurrentPosition],
        moduleProximity: .inapplicable,
        popularity: .none,
        scopeProximity: .inapplicable,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      ).score
    )
    let encoderResult = SemanticScoredText(
      "Encoder",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [.expressionAtNonScriptOrMainFileScope],
        moduleProximity: .imported(distance: 1),
        popularity: popularity.popularity(of: "Swift.Encoder"),
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      ).score
    )
    test("e", precision: .thorough, prefers: enumResult, over: encoderResult)
    test("e", precision: .thorough, prefers: extensionResult, over: encoderResult)
  }

  func testPreferLessTokens() {
    let distantUnrelatedGlobal = SemanticClassification(
      availability: .available,
      completionKind: .variable,
      flair: [],
      moduleProximity: .imported(distance: 3),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .unrelated
    ).score
    let distantType = SemanticClassification(
      availability: .available,
      completionKind: .type,
      flair: [],
      moduleProximity: .imported(distance: 3),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let nearType = SemanticClassification(
      availability: .available,
      completionKind: .type,
      flair: [],
      moduleProximity: .imported(distance: 1),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let nearInheritedInstanceMethod = SemanticClassification(
      availability: .available,
      completionKind: .function,
      flair: [],
      moduleProximity: .imported(distance: 1),
      popularity: .none,
      scopeProximity: .inheritedContainer,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let nearInheritedUnrelatedInstanceMethod = SemanticClassification(
      availability: .available,
      completionKind: .function,
      flair: [],
      moduleProximity: .imported(distance: 1),
      popularity: .none,
      scopeProximity: .inheritedContainer,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .unrelated
    ).score
    let keyword = SemanticClassification(
      availability: .available,
      completionKind: .keyword,
      flair: [],
      moduleProximity: .inapplicable,
      popularity: .none,
      scopeProximity: .inapplicable,
      structuralProximity: .inapplicable,
      synchronicityCompatibility: .inapplicable,
      typeCompatibility: .inapplicable
    ).score
    let decoys = [
      SemanticScoredText("T_FMT", distantUnrelatedGlobal),
      SemanticScoredText("T_FMT_AMPM", distantUnrelatedGlobal),
      SemanticScoredText("TScriptingSizeResource", distantType),
      SemanticScoredText("TAB3", distantUnrelatedGlobal),
      SemanticScoredText("TAB2", distantUnrelatedGlobal),
      SemanticScoredText("TAB1", distantUnrelatedGlobal),
      SemanticScoredText("TAB0", distantUnrelatedGlobal),
      SemanticScoredText("TH_URG", distantUnrelatedGlobal),
      SemanticScoredText("TH_SYN", distantUnrelatedGlobal),
      SemanticScoredText("TH_RST", distantUnrelatedGlobal),
      SemanticScoredText("TH_FIN", distantUnrelatedGlobal),
      SemanticScoredText("TH_ECE", distantUnrelatedGlobal),
      SemanticScoredText("TH_CWR", distantUnrelatedGlobal),
      SemanticScoredText("TH_ACK", distantUnrelatedGlobal),
      SemanticScoredText("TS_LNCH", distantUnrelatedGlobal),
      SemanticScoredText("TS_BUSY", distantUnrelatedGlobal),
      SemanticScoredText("TS_BKSL", distantUnrelatedGlobal),
      SemanticScoredText("TR_ZFOD", distantUnrelatedGlobal),
      SemanticScoredText("TR_MALL", distantUnrelatedGlobal),
      SemanticScoredText("TextField", nearType),
      SemanticScoredText("TextEditor", nearType),
      SemanticScoredText("TextAlignment", nearType),
      SemanticScoredText("TextFieldStyle", nearType),
      SemanticScoredText("TextOutputStream", nearType),
      SemanticScoredText("TextEditingCommands", nearType),
      SemanticScoredText("TextRange", distantType),
      SemanticScoredText("TextFormattingCommands", nearType),
      SemanticScoredText("TextOutputStreamable", nearType),
      SemanticScoredText("TextRangePtr", distantType),
      SemanticScoredText("multilineTextAlignment(:)", nearInheritedInstanceMethod),
      SemanticScoredText("TextRangeArray", distantType),
      SemanticScoredText("TextRangeHandle", distantType),
      SemanticScoredText("accessibilityTextContentType(:)", nearInheritedUnrelatedInstanceMethod),
      SemanticScoredText("TextRangeArrayPtr", distantType),
      SemanticScoredText("TextBreakLocatorRef", distantType),
      SemanticScoredText("TextRangeArrayHandle", distantType),
      SemanticScoredText("TernaryPrecedence", keyword),
    ]
    let text = SemanticScoredText("Text", nearType)
    test(completion: text, alwaysBeats: decoys)
  }

  func testPenalizeGlobalVariables() {
    let distantEnumCase = SemanticClassification(
      availability: .available,
      completionKind: .enumCase,
      flair: [],
      moduleProximity: .imported(distance: 3),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let distantGlobal = SemanticClassification(
      availability: .available,
      completionKind: .variable,
      flair: [],
      moduleProximity: .imported(distance: 3),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let distantType = SemanticClassification(
      availability: .available,
      completionKind: .type,
      flair: [],
      moduleProximity: .imported(distance: 3),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let nearType = SemanticClassification(
      availability: .available,
      completionKind: .type,
      flair: [],
      moduleProximity: .imported(distance: 1),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let decoys = [
      SemanticScoredText("exUserBreak", distantEnumCase),
      SemanticScoredText("EX_OK", distantGlobal),
      SemanticScoredText("EX__MAX", distantGlobal),
      SemanticScoredText("EX_IOERR", distantGlobal),
      SemanticScoredText("eHD", distantEnumCase),
      SemanticScoredText("eIP", distantEnumCase),
      SemanticScoredText("eADB", distantEnumCase),
      SemanticScoredText("eBus", distantEnumCase),
      SemanticScoredText("eDVD", distantEnumCase),
      SemanticScoredText("eLCD", distantEnumCase),
      SemanticScoredText("ePPP", distantEnumCase),
      SemanticScoredText("eUSB", distantEnumCase),
      SemanticScoredText("eIrDA", distantEnumCase),
      SemanticScoredText("eSCSI", distantEnumCase),
      SemanticScoredText("extFSErr", distantEnumCase),
      SemanticScoredText("EXTA", distantGlobal),
      SemanticScoredText("extractErr", distantEnumCase),
      SemanticScoredText("extendedBlock", distantEnumCase),
      SemanticScoredText("extendedBlock", distantEnumCase),
      SemanticScoredText("extendedBlockLen", distantEnumCase),
      SemanticScoredText("extern_proc", distantType),
      SemanticScoredText("ExtendedGraphemeClusterType", nearType),
      SemanticScoredText("extentrecord", distantType),
      SemanticScoredText("extension_data_format", distantType),
    ]
    let keyword = SemanticClassification(
      availability: .available,
      completionKind: .keyword,
      flair: [],
      moduleProximity: .inapplicable,
      popularity: .none,
      scopeProximity: .inapplicable,
      structuralProximity: .inapplicable,
      synchronicityCompatibility: .inapplicable,
      typeCompatibility: .inapplicable
    ).score
    let extensionKeyword = SemanticScoredText("extension", keyword)
    test(completion: extensionKeyword, alwaysBeats: decoys)
  }

  func test74888915() {
    let string = SemanticScoredText(
      "String",
      .partial(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: .init(scoreComponent: 1.1),
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .inapplicable
      )
    )
    let decoys = [
      SemanticScoredText(
        "S_OK",
        .partial(
          availability: .available,
          completionKind: .variable,
          flair: [],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "s_zerofill",
        .partial(
          availability: .available,
          completionKind: .variable,
          flair: [],
          moduleProximity: .imported(distance: 3),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "ST_NOSUID",
        .partial(
          availability: .available,
          completionKind: .variable,
          flair: [],
          moduleProximity: .imported(distance: 3),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "ST_RDONLY",
        .partial(
          availability: .available,
          completionKind: .variable,
          flair: [],
          moduleProximity: .imported(distance: 3),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "strUserBreak",
        .partial(
          availability: .available,
          completionKind: .enumCase,
          flair: [],
          moduleProximity: .imported(distance: 3),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "strlen()",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [],
          moduleProximity: .imported(distance: 2),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "STClass",
        .partial(
          availability: .available,
          completionKind: .variable,
          flair: [],
          moduleProximity: .imported(distance: 3),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "STHeader",
        .partial(
          availability: .available,
          completionKind: .type,
          flair: [],
          moduleProximity: .imported(distance: 3),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .inapplicable,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "StrideTo",
        .partial(
          availability: .available,
          completionKind: .type,
          flair: [],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .inapplicable,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "StrideThrough",
        .partial(
          availability: .available,
          completionKind: .type,
          flair: [],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .inapplicable,
          typeCompatibility: .inapplicable
        )
      ),
    ]
    test(completion: string, alwaysBeats: decoys)
  }

  func test90527878() {
    let swiftUIText = SemanticScoredText(
      "Text",
      .partial(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .inapplicable,
        typeCompatibility: .compatible
      )
    )
    let decoys = [
      SemanticScoredText(
        "task(id:_)",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
      SemanticScoredText(
        "tint(_:)",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
      SemanticScoredText(
        "tabItem(_:)",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
      SemanticScoredText(
        "tracking(_:)",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
      SemanticScoredText(
        "textCase(_:)",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
      SemanticScoredText(
        "textSelection(_:)",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
      SemanticScoredText(
        "text()",
        .partial(
          availability: .available,
          completionKind: .function,
          flair: [.swiftUIModifierOnSelfWhileBuildingSelf],
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .container,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .compatible
        )
      ),
    ]
    test(completion: swiftUIText, alwaysBeats: decoys)
  }

  func testTextScoreOrdering() {
    typealias TextScore = Pattern.TextScore
    XCTAssertLessThan(TextScore(value: 0, falseStarts: 0), TextScore(value: 1, falseStarts: 0))
    XCTAssertLessThan(TextScore(value: 0, falseStarts: 1), TextScore(value: 0, falseStarts: 0))
    XCTAssertLessThan(TextScore(value: 1, falseStarts: 1), TextScore(value: 1, falseStarts: 0))
  }

  func testFalseStartCounts() {
    func falseStarts(
      pattern patternText: String,
      candidate: String,
      contentType: CandidateBatch.ContentType = .codeCompletionSymbol
    ) -> Int {
      candidate.withUncachedUTF8Bytes { candidateUTF8Bytes in
        UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
          Pattern(text: patternText).score(
            candidate: candidateUTF8Bytes,
            contentType: contentType,
            precision: .thorough,
            allocator: &allocator
          ).falseStarts
        }
      }
    }

    XCTAssertEqual(falseStarts(pattern: "per", candidate: "person"), 0)
    XCTAssertEqual(falseStarts(pattern: "per", candidate: "super"), 1)
    XCTAssertEqual(falseStarts(pattern: "per", candidate: "pear"), 2)
    XCTAssertEqual(falseStarts(pattern: "tamic", candidate: "translatesAutoresizingMaskIntoConstraints"), 0)
    XCTAssertEqual(falseStarts(pattern: "amic", candidate: "translatesAutoresizingMaskIntoConstraints"), 3)
    XCTAssertEqual(falseStarts(pattern: "args", candidate: "NS(all:red:go:slow:)"), 3)
    XCTAssertEqual(falseStarts(pattern: "segmentControl", candidate: "segmentedControl"), 1)
    XCTAssertEqual(falseStarts(pattern: "hsta", candidate: "ABC_FHSTAT"), 1)
    XCTAssertEqual(falseStarts(pattern: "HSta", candidate: "HStack"), 0)
    XCTAssertEqual(falseStarts(pattern: "HSta", candidate: "LazyHStack"), 0)
    XCTAssertEqual(falseStarts(pattern: "resetDownload", candidate: "resetDocumentDownload"), 0)
    XCTAssertEqual(falseStarts(pattern: "resetDown", candidate: "resetDocumentDownload"), 0)
    XCTAssertEqual(falseStarts(pattern: "moc", candidate: "NSManagedObjectContext"), 0)
    XCTAssertEqual(falseStarts(pattern: "nmoc", candidate: "NSManagedObjectContext"), 0)
    XCTAssertEqual(falseStarts(pattern: "nsmoc", candidate: "NSManagedObjectContext"), 0)

    // rdar://87776071 (Typing `reduce` suggested 5,000 character struct initializer)
    let tcpstatInitializer =
      "tcpstat(tcps_connattempt:tcps_accepts:tcps_connects:tcps_drops:tcps_conndrops:tcps_closed:tcps_segstimed:tcps_rttupdated:tcps_delack:tcps_timeoutdrop:tcps_rexmttimeo:tcps_persisttimeo:tcps_keeptimeo:tcps_keepprobe:tcps_keepdrops:tcps_sndtotal:tcps_sndpack:tcps_sndbyte:tcps_sndrexmitpack:tcps_sndrexmitbyte:tcps_sndacks:tcps_sndprobe:tcps_sndurg:tcps_sndwinup:tcps_sndctrl:tcps_rcvtotal:tcps_rcvpack:tcps_rcvbyte:tcps_rcvbadsum:tcps_rcvbadoff:tcps_rcvmemdrop:tcps_rcvshort:tcps_rcvduppack:tcps_rcvdupbyte:tcps_rcvpartduppack:tcps_rcvpartdupbyte:tcps_rcvoopack:tcps_rcvoobyte:tcps_rcvpackafterwin:tcps_rcvbyteafterwin:tcps_rcvafterclose:tcps_rcvwinprobe:tcps_rcvdupack:tcps_rcvacktoomuch:tcps_rcvackpack:tcps_rcvackbyte:tcps_rcvwinupd:tcps_pawsdrop:tcps_predack:tcps_preddat:tcps_pcbcachemiss:tcps_cachedrtt:tcps_cachedrttvar:tcps_cachedssthresh:tcps_usedrtt:tcps_usedrttvar:tcps_usedssthresh:tcps_persistdrop:tcps_badsyn:tcps_mturesent:tcps_listendrop:tcps_synchallenge:tcps_rstchallenge:tcps_minmssdrops:tcps_sndrexmitbad:tcps_badrst:tcps_sc_added:tcps_sc_retransmitted:tcps_sc_dupsyn:tcps_sc_dropped:tcps_sc_completed:tcps_sc_bucketoverflow:tcps_sc_cacheoverflow:tcps_sc_reset:tcps_sc_stale:tcps_sc_aborted:tcps_sc_badack:tcps_sc_unreach:tcps_sc_zonefail:tcps_sc_sendcookie:tcps_sc_recvcookie:tcps_hc_added:tcps_hc_bucketoverflow:tcps_sack_recovery_episode:tcps_sack_rexmits:tcps_sack_rexmit_bytes:tcps_sack_rcv_blocks:tcps_sack_send_blocks:tcps_sack_sboverflow:tcps_bg_rcvtotal:tcps_rxtfindrop:tcps_fcholdpacket:tcps_limited_txt:tcps_early_rexmt:tcps_sack_ackadv:tcps_rcv_swcsum:tcps_rcv_swcsum_bytes:tcps_rcv6_swcsum:tcps_rcv6_swcsum_bytes:tcps_snd_swcsum:tcps_snd_swcsum_bytes:tcps_snd6_swcsum:tcps_snd6_swcsum_bytes:tcps_unused_1:tcps_unused_2:tcps_unused_3:tcps_invalid_mpcap:tcps_invalid_joins:tcps_mpcap_fallback:tcps_join_fallback:tcps_estab_fallback:tcps_invalid_opt:tcps_mp_outofwin:tcps_mp_reducedwin:tcps_mp_badcsum:tcps_mp_oodata:tcps_mp_switches:tcps_mp_rcvtotal:tcps_mp_rcvbytes:tcps_mp_sndpacks:tcps_mp_sndbytes:tcps_join_rxmts:tcps_tailloss_rto:tcps_reordered_pkts:tcps_recovered_pkts:tcps_pto:tcps_rto_after_pto:tcps_tlp_recovery:tcps_tlp_recoverlastpkt:tcps_ecn_client_success:tcps_ecn_recv_ece:tcps_ecn_sent_ece:tcps_detect_reordering:tcps_delay_recovery:tcps_avoid_rxmt:tcps_unnecessary_rxmt:tcps_nostretchack:tcps_rescue_rxmt:tcps_pto_in_recovery:tcps_pmtudbh_reverted:tcps_dsack_disable:tcps_dsack_ackloss:tcps_dsack_badrexmt:tcps_dsack_sent:tcps_dsack_recvd:tcps_dsack_recvd_old:tcps_mp_sel_symtomsd:tcps_mp_sel_rtt:tcps_mp_sel_rto:tcps_mp_sel_peer:tcps_mp_num_probes:tcps_mp_verdowngrade:tcps_drop_after_sleep:tcps_probe_if:tcps_probe_if_conflict:tcps_ecn_client_setup:tcps_ecn_server_setup:tcps_ecn_server_success:tcps_ecn_ace_syn_not_ect:tcps_ecn_ace_syn_ect1:tcps_ecn_ace_syn_ect0:tcps_ecn_ace_syn_ce:tcps_ecn_lost_synack:tcps_ecn_lost_syn:tcps_ecn_not_supported:tcps_ecn_recv_ce:tcps_ecn_ace_recv_ce:tcps_ecn_conn_recv_ce:tcps_ecn_conn_recv_ece:tcps_ecn_conn_plnoce:tcps_ecn_conn_pl_ce:tcps_ecn_conn_nopl_ce:tcps_ecn_fallback_synloss:tcps_ecn_fallback_reorder:tcps_ecn_fallback_ce:tcps_tfo_syn_data_rcv:tcps_tfo_cookie_req_rcv:tcps_tfo_cookie_sent:tcps_tfo_cookie_invalid:tcps_tfo_cookie_req:tcps_tfo_cookie_rcv:tcps_tfo_syn_data_sent:tcps_tfo_syn_data_acked:tcps_tfo_syn_loss:tcps_tfo_blackhole:tcps_tfo_cookie_wrong:tcps_tfo_no_cookie_rcv:tcps_tfo_heuristics_disable:tcps_tfo_sndblackhole:tcps_mss_to_default:tcps_mss_to_medium:tcps_mss_to_low:tcps_ecn_fallback_droprst:tcps_ecn_fallback_droprxmt:tcps_ecn_fallback_synrst:tcps_mptcp_rcvmemdrop:tcps_mptcp_rcvduppack:tcps_mptcp_rcvpackafterwin:tcps_timer_drift_le_1_ms:tcps_timer_drift_le_10_ms:tcps_timer_drift_le_20_ms:tcps_timer_drift_le_50_ms:tcps_timer_drift_le_100_ms:tcps_timer_drift_le_200_ms:tcps_timer_drift_le_500_ms:tcps_timer_drift_le_1000_ms:tcps_timer_drift_gt_1000_ms:tcps_mptcp_handover_attempt:tcps_mptcp_interactive_attempt:tcps_mptcp_aggregate_attempt:tcps_mptcp_fp_handover_attempt:tcps_mptcp_fp_interactive_attempt:tcps_mptcp_fp_aggregate_attempt:tcps_mptcp_heuristic_fallback:tcps_mptcp_fp_heuristic_fallback:tcps_mptcp_handover_success_wifi:tcps_mptcp_handover_success_cell:tcps_mptcp_interactive_success:tcps_mptcp_aggregate_success:tcps_mptcp_fp_handover_success_wifi:tcps_mptcp_fp_handover_success_cell:tcps_mptcp_fp_interactive_success:tcps_mptcp_fp_aggregate_success:tcps_mptcp_handover_cell_from_wifi:tcps_mptcp_handover_wifi_from_cell:tcps_mptcp_interactive_cell_from_wifi:tcps_mptcp_handover_cell_bytes:tcps_mptcp_interactive_cell_bytes:tcps_mptcp_aggregate_cell_bytes:tcps_mptcp_handover_all_bytes:tcps_mptcp_interactive_all_bytes:tcps_mptcp_aggregate_all_bytes:tcps_mptcp_back_to_wifi:tcps_mptcp_wifi_proxy:tcps_mptcp_cell_proxy:tcps_ka_offload_drops:tcps_mptcp_triggered_cell:tcps_fin_timeout_drops:)"
    XCTAssertEqual(falseStarts(pattern: "reduce", candidate: tcpstatInitializer), 1)
    XCTAssertEqual(falseStarts(pattern: "tcpst", candidate: tcpstatInitializer), 0)
    XCTAssertEqual(falseStarts(pattern: "willDis", candidate: "tableView(:willDisplayCell:row:)"), 0)
    XCTAssertEqual(
      falseStarts(pattern: "toolTip", candidate: "outlineView?(toolTipFor:rect:tableColumn:item:mouseLocation:)"),
      0
    )
    XCTAssertEqual(
      falseStarts(
        pattern: "mouseLocation",
        candidate: "outlineView?(toolTipFor:rect:tableColumn:item:mouseLocation:)"
      ),
      0
    )

    XCTAssertEqual(falseStarts(pattern: "gvh", candidate: "SATGraphView.h", contentType: .fileName), 0)
    XCTAssertEqual(falseStarts(pattern: "sgv", candidate: "SATGraphView.h", contentType: .fileName), 0)
    XCTAssertEqual(falseStarts(pattern: "sgv", candidate: "SATGraphView.h", contentType: .fileName), 0)
    XCTAssertEqual(
      falseStarts(pattern: "skgv", candidate: "SATGraphView.h", contentType: .fileName),
      0
    )
    XCTAssertEqual(
      falseStarts(pattern: "sktgv", candidate: "SATGraphView.h", contentType: .fileName),
      0
    )
    XCTAssertEqual(
      falseStarts(pattern: "sgvh", candidate: "SATGraphView.h", contentType: .fileName),
      0
    )
    XCTAssertEqual(falseStarts(pattern: "gv", candidate: "SATGraphView.h", contentType: .fileName), 1)

    XCTAssertEqual(
      falseStarts(pattern: "idiodic", candidate: "IDAHO_IOMATIC_DECOY_ICE", contentType: .codeCompletionSymbol),
      3
    )

    // Good Matches

    for contentType in [
      ContentType.projectSymbol, ContentType.codeCompletionSymbol, ContentType.fileName,
    ] {
      let candidate = (contentType == .fileName) ? "NSOpenGLView.h" : "NSOpenGLView"
      XCTAssertEqual(falseStarts(pattern: "nsoglv", candidate: candidate, contentType: contentType), 0)
      XCTAssertEqual(falseStarts(pattern: "nsogv", candidate: candidate, contentType: contentType), 0)
      XCTAssertEqual(falseStarts(pattern: "noglv", candidate: candidate, contentType: contentType), 0)
      XCTAssertEqual(falseStarts(pattern: "oglv", candidate: candidate, contentType: contentType), 0)
      XCTAssertEqual(falseStarts(pattern: "glv", candidate: candidate, contentType: contentType), 0)
      XCTAssertEqual(falseStarts(pattern: "noglv", candidate: candidate, contentType: contentType), 0)
      // False starts
      XCTAssertEqual(falseStarts(pattern: "soglv", candidate: candidate, contentType: contentType), 2)
      XCTAssertEqual(falseStarts(pattern: "olv", candidate: candidate, contentType: contentType), 2)
      XCTAssertEqual(falseStarts(pattern: "nsov", candidate: candidate, contentType: contentType), 1)

    }
  }
}
