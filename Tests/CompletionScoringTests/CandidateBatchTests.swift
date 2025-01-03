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
import CompletionScoringTestSupport
import XCTest

typealias Pattern = CompletionScoring.Pattern

class CandidateBatchTests: XCTestCase {
  func testEnumerate() throws {
    let strings = [
      "abc",
      "foo(bar:baz:)?",
      "",
      "ASomewhatLongStringAtLeastLongEnoughToNotBeASmolStringInSwift",
    ]

    let batch = CandidateBatch(symbols: strings)
    var index = 0
    batch.enumerate { candidate in
      XCTAssertEqual(strings[index], String(bytes: candidate.bytes, encoding: .utf8)!)
      index += 1
    }
    index = 0
    batch.enumerate { candidateIndex, candidate in
      XCTAssertEqual(candidateIndex, index)
      XCTAssertEqual(strings[index], String(bytes: candidate.bytes, encoding: .utf8)!)
      index += 1
    }
    XCTAssertEqual(index, strings.count)
  }

  func testCount() throws {
    XCTAssertEqual(CandidateBatch(symbols: []).count, 0)
    XCTAssertEqual(CandidateBatch(symbols: [""]).count, 1)
    XCTAssertEqual(CandidateBatch(symbols: ["", ""]).count, 2)
  }

  func testStringAt() throws {
    XCTAssertEqual(CandidateBatch(symbols: []).count, 0)
    XCTAssertEqual(CandidateBatch(symbols: [""])[stringAt: 0], "")
    XCTAssertEqual(CandidateBatch(symbols: ["A"])[stringAt: 0], "A")
    XCTAssertEqual(CandidateBatch(symbols: ["", "A"])[stringAt: 0], "")
    XCTAssertEqual(CandidateBatch(symbols: ["", "A"])[stringAt: 1], "A")
  }

  func testAppending() throws {
    var randomness = RepeatableRandomNumberGenerator()
    var strings: [String] = []
    var batch = CandidateBatch(byteCapacity: 1)  // We want to thoroughly test growing, so start very small.
    for _ in 0..<2500 {
      let string = randomness.randomLowercaseASCIIString(lengthRange: 0...11)
      strings.append(string)
      batch.append(string, contentType: .codeCompletionSymbol)
      XCTAssertEqual(strings.first, batch[stringAt: 0])
      XCTAssertEqual(strings.last, batch[stringAt: batch.count - 1])
    }
    batch.enumerate { index, candidate in
      XCTAssertEqual(strings[index], String(bytes: candidate.bytes, encoding: .utf8)!)
    }
  }

  func testCopyOnWrite() throws {
    let initialStrings = ["ABC"]
    var original = CandidateBatch(symbols: initialStrings)
    var copy = original
    XCTAssertEqual(copy.strings, initialStrings)
    XCTAssertEqual(original.strings, initialStrings)

    original.append("123", contentType: .codeCompletionSymbol)
    XCTAssertEqual(copy.strings, initialStrings)
    XCTAssertEqual(original.strings, initialStrings + ["123"])

    copy.append("EFG", contentType: .codeCompletionSymbol)
    XCTAssertEqual(copy.strings, initialStrings + ["EFG"])
    XCTAssertEqual(original.strings, initialStrings + ["123"])
  }

  // This test tries to find some breakdown with copy-on-write by racing two threads against each other.
  // One thread does a read while the other days a write.
  func testConcurrentMutation() {
    @Sendable func validate(_ candidate: Candidate) {
      let count = candidate.bytes.count
      for byte in candidate.bytes {
        XCTAssertEqual(Int(byte), count)
      }
    }
    @Sendable func read(local: CandidateBatch) {
      local.withUnsafeStorage { storage in
        if let candidateIndex = storage.indices.randomElement() {
          validate(storage.candidate(at: candidateIndex))
        }
      }
    }
    for _ in 0..<100 {  // Inner loop goes N^2 with copy on write, this makes it only go linearly slower.
      // `nonisolated(unsafe)` is fine because there is only one operation to `shared` before a
      // `DispatchGroup.wait` and thus we can't have concurrent accesses.
      nonisolated(unsafe) var shared = CandidateBatch()
      let queue = DispatchQueue(label: "", attributes: .concurrent)
      let strings = UTF8Byte.uppercaseAZ.map { letter in
        Array(repeating: String(format: "%c", letter), count: Int(letter)).joined()
      }
      // Try reading the shared value while writing into a copy.
      for _ in 0..<100 {
        // Having both operated directly on the `shared` captured through the closure would definitely be
        // illegal, and would crash, just like it does for Swift.Array
        let captured = shared
        let group = DispatchGroup()
        queue.async(group: group) {
          read(local: captured)
        }
        queue.async(group: group) {
          shared.append(strings.randomElement()!, contentType: .codeCompletionSymbol)
        }
        group.wait()
      }
      // Try reading a copy while writing into the shared value.
      for _ in 0..<100 {
        let group = DispatchGroup()
        queue.async(group: group) {
          read(local: shared)
        }
        // `nonisolated(unsafe)` is fine because there is only one operation to `capture` before a
        // `DispatchGroup.wait` and thus we can't have concurrent accesses.
        nonisolated(unsafe) var captured = shared
        queue.async(group: group) {
          captured.append(strings.randomElement()!, contentType: .codeCompletionSymbol)
        }
        group.wait()
      }
    }
  }

  private func randomBatch(
    count: Int,
    maxStringLength: Int,
    using randomness: inout RepeatableRandomNumberGenerator
  ) -> CandidateBatch {
    CandidateBatch(
      symbols: (0..<count).map { candidateIndex in
        randomness.randomLowercaseASCIIString(lengthRange: 0...maxStringLength)
      }
    )
  }

  func testBestMatchesExhaustively() throws {
    #if DEBUG
    let batchCount = 7
    let candidates = 131
    #else
    let batchCount = 37
    let candidates = 1327
    #endif

    var randomness = RepeatableRandomNumberGenerator()
    let batches = (0..<batchCount).map { _ in
      randomBatch(count: candidates, maxStringLength: 128, using: &randomness)
    }
    let selector = ScoredMatchSelector(batches: batches)
    for _ in 0..<(100) {
      let patternText = randomness.randomLowercaseASCIIString(lengthRange: (4...15))
      let pattern = Pattern(text: patternText)
      do {  // Plural
        let serialResults = pattern.seariallyScoreMatches(across: batches, precision: .fast)
        let concurrentResults = pattern.scoredMatches(across: batches, precision: .fast).sorted { lhs, rhs in
          return (lhs.batchIndex <? rhs.batchIndex)
            ?? (lhs.candidateIndex < rhs.candidateIndex)
        }
        XCTAssertEqual(serialResults, concurrentResults)
      }
      do {  // Singular
        let serialResults = pattern.seariallyScoreMatches(in: batches[1], precision: .fast)
        let concurrentResults = pattern.scoredMatches(in: batches[1], precision: .fast).sorted { lhs, rhs in
          return lhs.candidateIndex < rhs.candidateIndex
        }
        XCTAssertEqual(serialResults, concurrentResults)
      }
      do {  // Shared Workload
        let sharedWorkloadResults = selector.scoredMatches(pattern: pattern, precision: .fast)
        let serialResults = pattern.seariallyScoreMatches(across: batches, precision: .fast)
        XCTAssertEqual(sharedWorkloadResults, serialResults)
      }
    }
  }

  func testScoredMatches() throws {
    let batch = CandidateBatch(symbols: [
      "a",
      "aabb",
      "aa",
      "aaa",
      "bb",
      "b",
    ])
    func match(pattern: String) -> [String] {
      let matches = Pattern(text: pattern).scoredMatches(in: batch, precision: .fast).sorted { lhs, rhs in
        lhs.textScore > rhs.textScore
      }
      return matches.map { match in
        batch[stringAt: match.candidateIndex]
      }
    }

    XCTAssertEqual(match(pattern: "a"), ["a", "aa", "aaa", "aabb"])
    XCTAssertEqual(match(pattern: "aa"), ["aa", "aaa", "aabb"])
    XCTAssertEqual(match(pattern: "aaa"), ["aaa"])

    XCTAssertEqual(match(pattern: "b"), ["b", "bb", "aabb"])
    XCTAssertEqual(match(pattern: "bb"), ["bb", "aabb"])

    XCTAssertEqual(match(pattern: "ab"), ["aabb"])
  }

  func testFilter() {
    let batch = CandidateBatch(symbols: [
      "a",
      "aabb",
      "aa",
      "aaa",
      "bb",
      "b",
    ])
    let filtered = batch.filter { candidateIndex, candidate in
      candidate.bytes.count == 2
    }
    XCTAssertEqual(filtered.strings, ["aa", "bb"])
  }

  private func bestMatches(
    _ filterText: String,
    _ matches: [SemanticScoredText],
    maximumNumberOfItemsForExpensiveSelection: Int = MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection
  ) -> [String] {
    let pattern = Pattern(text: filterText)
    let batch = CandidateBatch(candidates: matches)
    let batchMatches = pattern.scoredMatches(across: [batch], precision: .fast)
    let fastMatches = batchMatches.map { batchMatch in
      MatchCollator.Match(
        batchIndex: batchMatch.batchIndex,
        candidateIndex: batchMatch.candidateIndex,
        groupID: matches[batchMatch.candidateIndex].groupID,
        score: CompletionScore(
          textComponent: batchMatch.textScore,
          semanticComponent: matches[batchMatch.candidateIndex].semanticScore
        )
      )
    }
    let bestMatches = MatchCollator.selectBestMatches(
      for: pattern,
      from: fastMatches,
      in: [batch],
      influencingTokenizedIdentifiers: [],
      orderingTiesBy: { _, _ in false },
      maximumNumberOfItemsForExpensiveSelection: maximumNumberOfItemsForExpensiveSelection
    )
    return bestMatches.map { bestMatch in
      matches[bestMatch.candidateIndex].text
    }
  }

  fileprivate func bestMatches(_ filterText: String, _ candidates: [String]) -> [String] {
    bestMatches(
      filterText,
      candidates.map { candidate in
        SemanticScoredText(candidate)
      }
    )
  }

  func testEarlySemanticCutoff() {
    for isMainDotSwift in [true, false] {
      let typeFlair: Flair = isMainDotSwift ? [] : .expressionAtNonScriptOrMainFileScope
      let best = bestMatches(
        "s",
        [
          SemanticScoredText(
            "struct",
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
          ),
          SemanticScoredText(
            "String",
            SemanticClassification(
              availability: .available,
              completionKind: .type,
              flair: [typeFlair],
              moduleProximity: .imported(distance: 0),
              popularity: .none,
              scopeProximity: .global,
              structuralProximity: .inapplicable,
              synchronicityCompatibility: .inapplicable,
              typeCompatibility: .inapplicable
            ).score
          ),
          SemanticScoredText(
            "sint8",
            SemanticClassification(
              availability: .available,
              completionKind: .type,
              flair: [typeFlair],
              moduleProximity: .imported(distance: 2),
              popularity: .none,
              scopeProximity: .global,
              structuralProximity: .inapplicable,
              synchronicityCompatibility: .inapplicable,
              typeCompatibility: .inapplicable
            ).score
          ),
        ]
      )
      if isMainDotSwift {
        XCTAssertEqual(best, ["struct", "String", "sint8"])
      } else {
        XCTAssertEqual(best, ["struct"])
      }
    }
  }

  func testEmptyPatterns() {
    withEachPermutation("az", "ay") { first, second in
      XCTAssertEqual(bestMatches("", [first, second]), ["ay", "az"])
    }

    withEachPermutation(SemanticScoredText("foo", 2.0), SemanticScoredText("bar", 1.0)) { first, second in
      XCTAssertEqual(bestMatches("", [first, second]), ["foo", "bar"])
    }

    withEachPermutation(SemanticScoredText("foo", 1.0), SemanticScoredText("bar", 2.0)) { first, second in
      XCTAssertEqual(bestMatches("", [first, second]), ["bar", "foo"])
    }
  }

  func testBestMatchesTieOrder() {
    withEachPermutation("az", "ay") { first, second in
      XCTAssertEqual(bestMatches("a", [first, second]), ["ay", "az"])
    }
  }

  func testBestMatches() {
    XCTAssertEqual(bestMatches("a", ["a"]), ["a"])
    XCTAssertEqual(bestMatches("b", ["a"]), [])

    XCTAssertEqual(bestMatches("a", ["a", "bab"]), ["a"])
    XCTAssertEqual(bestMatches("a", ["bab", "a"]), ["a"])

    XCTAssertEqual(bestMatches("a", ["a", "c"]), ["a"])
    XCTAssertEqual(bestMatches("a", ["a", "c"]), ["a"])

    XCTAssertEqual(bestMatches("aa", ["aa", "baa", "aab", "aba", "cAa"]), ["aa", "aab", "cAa"])

    XCTAssertEqual(
      bestMatches("resetDownload", ["resetDocumentDownload", "resetZzzDownload", "zrzezszeztzDzozwznzlzozazdz"]),
      ["resetZzzDownload", "resetDocumentDownload"]
    )

    XCTAssertEqual(bestMatches("method", ["methodA", "mexthxodB"]), ["methodA"])
    XCTAssertEqual(
      bestMatches(
        "method",
        [
          "methodA",
          "methodBSuffixed",
          "prefixedMethodB",
          "prefixedMethodBSuffixed",
          "bigFunction(arg1:arg2:arg3:methodB:arg5:arg6:)",
        ]
      ),
      [
        "methodA",
        "methodBSuffixed",
        "prefixedMethodB",
        "prefixedMethodBSuffixed",
        "bigFunction(arg1:arg2:arg3:methodB:arg5:arg6:)",
      ]
    )

    XCTAssertEqual(
      bestMatches(
        "toolTi",
        [
          "toolTip",
          "removeToolTip(_:)",
          "addToolTip(_:)",
        ]
      ),
      [
        "toolTip",
        "addToolTip(_:)",
        "removeToolTip(_:)",
      ]
    )
    XCTAssertEqual(
      bestMatches(
        "UINavigationBar",
        [
          SemanticScoredText(1.0, "UINavigationBar", contentType: .projectSymbol),
          SemanticScoredText(1.0, "UINavigationBar.m", contentType: .fileName),
          SemanticScoredText(1.0, "UINavigationBarBackButtonView", contentType: .projectSymbol),
        ]
      ),
      [
        "UINavigationBar",
        "UINavigationBar.m",
        "UINavigationBarBackButtonView",
      ]
    )
  }

  func testCuttingOfMnemonicMatches() {
    let badCandidate = "mutableArrayValue(forKey:)"
    let goodCandidates = [
      "makeKey()",
      "makeMain()",
      "makeFirstResponder(:)",
      "makeTouchbar()",
      "makeBaseWritingDirectionNatural()",
      "makeTextWritingDirectionNatural(:)",
    ]
    let results = bestMatches("mak", goodCandidates + [badCandidate])
    XCTAssertFalse(results.contains(badCandidate))
    XCTAssertEqual(results.count, goodCandidates.count)
  }

  func testDontSuggestArgumentOnlyMatches() {
    let badSemanticScore = SemanticClassification.allSymbolsClassification.score
    let awefulMatches = [
      SemanticScoredText(
        "frameSize(forContentSize:horizontalScrollerClass:verticalScrollerClass:borderType:controlSize:scrollerStyle:)",
        badSemanticScore
      ),
      SemanticScoredText(
        "contentSize(forFrameSize:horizontalScrollerClass:verticalScrollerClass:borderType:controlSize:scrollerStyle:)",
        badSemanticScore
      ),
      SemanticScoredText(
        "init(ri_uuid:ri_user_time:ri_system_time:ri_pkg_idle_wkups:ri_interrupt_wkups:ri_pageins:ri_wired_size:ri_resident_size:ri_phys_footprint:ri_proc_start_abstime:ri_proc_exit_abstime:ri_child_user_time:, ri_child_system_time:ri_child_pkg_idle_wkups:ri_child_interrupt_wkups:ri_child_pageins:ri_child_elapsed_abstime:)",
        badSemanticScore
      ),
      SemanticScoredText(
        "init(cmd:cmdsize:rebase_off:rebase_size:bind_off:bind_size:weak_bind_off:weak_bind_size:lazy_bind_off:lazy_bind_size:export_off:export_size:)",
        badSemanticScore
      ),
      SemanticScoredText("init(nTracks:nSizes:sizeTableOffset:trakTable:)", badSemanticScore),
      SemanticScoredText(
        "init(alertBody:alertLocalizationKey:alertLocalizationArgs:title:titleLocalizationKey:titleLocalizationArgs:subtitle:subtitleLocalizationKey:subtitleLocalizationArgs:alertActionLocalizationKey:alertLaunchImage:soundName:desiredKeys:shouldBadge:shouldSendContentAvailable:shouldSendMutableContent:category:collapseIDKey:)",
        badSemanticScore
      ),
    ]
    XCTAssertEqual(bestMatches("resizeable", awefulMatches), [])
  }

  func testPrioritizeUserSymbolsOverSDK() {
    let projectMethod = SemanticClassification.partial(
      completionKind: .function,
      moduleProximity: .imported(distance: 0),
      scopeProximity: .global
    ).score
    let frameworkMethod = SemanticClassification.partial(
      completionKind: .function,
      moduleProximity: .imported(distance: 1),
      scopeProximity: .global
    ).score
    let frameworkType = SemanticClassification.partial(
      completionKind: .type,
      moduleProximity: .imported(distance: 1),
      scopeProximity: .global
    ).score
    test(
      "canceldownload",
      precision: .thorough,
      prefers: SemanticScoredText(projectMethod, "cancelDownload"),
      over: SemanticScoredText(frameworkMethod, "canCancelDownload")
    )
    test(
      "canceldownload",
      precision: .thorough,
      prefers: SemanticScoredText(projectMethod, "cancelDownload"),
      over: SemanticScoredText(frameworkMethod, "canCancelDownload(_:)")
    )
    test(
      "canceldownload",
      precision: .thorough,
      prefers: SemanticScoredText(projectMethod, "cancelDownload"),
      over: SemanticScoredText(frameworkMethod, "setCanCancelDownload(_:)")
    )
    test(
      "canceldownload",
      precision: .thorough,
      prefers: SemanticScoredText(projectMethod, "cancelDownload"),
      over: SemanticScoredText(frameworkMethod, "setCancelDownloadURL(_:)")
    )
    test(
      "canceldownload",
      precision: .thorough,
      prefers: SemanticScoredText(projectMethod, "cancelDownload"),
      over: SemanticScoredText(frameworkType, "SSXPCMessageCancelDownloads")
    )
    test(
      "canceldownload",
      precision: .thorough,
      prefers: SemanticScoredText(projectMethod, "cancelDownload"),
      over: SemanticScoredText(frameworkType, "__Reply__CancelDownloadingIconForDisplayIdentrifier_t")
    )
  }

  func test33239581() {
    let method = SemanticScoredText("testMessagesApp", .partial(completionKind: .function))
    let type = SemanticScoredText(
      "XCBuildStepSpecification_CopyMessagesApplicationStub",
      .partial(completionKind: .type)
    )
    test("testMessagesApp", precision: .thorough, prefers: method, over: type)
  }

  func test48642189() {
    let method = SemanticScoredText("bestPlaybackRect", .partial(completionKind: .function))
    let enumCase = SemanticScoredText("ISBasePlayerStatusReadyForPlayback", .partial(completionKind: .enumCase))
    test("bestplaybac", precision: .thorough, prefers: method, over: enumCase)
  }

  func test24554861_allowMatchingFileExtensionDuringFileNameAcronymMatch() {
    XCTAssertEqual(
      bestMatches(
        "SFD.cpp",
        [
          SemanticScoredText(1.0, "SymbolFileDWARF.cpp", contentType: .fileName),
          SemanticScoredText(1.0, "MassFileDrop.cpp", contentType: .fileName),
        ]
      ),
      ["SymbolFileDWARF.cpp"]
    )
  }

  func test80916856_managedObjectContext() {
    let expected = SemanticScoredText(
      "NSManagedObjectContext",
      .partial(
        completionKind: .function,
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .inapplicable,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      )
    )
    let decoys = [
      SemanticScoredText(
        "MNT_LOCAL",
        .partial(
          completionKind: .variable,
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "MM_NOCON",
        .partial(
          completionKind: .variable,
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
    ]
    XCTAssertEqual(bestMatches("moc", decoys + [expected]).first, expected.text)
  }

  func test80916856_translatesAutoresizingMaskIntoConstraints() {
    let expected = SemanticScoredText(
      "translatesAutoresizingMaskIntoConstraints",
      .partial(
        completionKind: .function,
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .compatible,
        typeCompatibility: .inapplicable
      )
    )
    let decoys = [
      SemanticScoredText(
        "MTLDynamicLibrary",
        .partial(
          completionKind: .type,
          moduleProximity: .imported(distance: 2),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
      SemanticScoredText(
        "NSDataWritingAtomic",
        .partial(
          completionKind: .enumCase,
          moduleProximity: .imported(distance: 1),
          popularity: .none,
          scopeProximity: .global,
          structuralProximity: .sdk,
          synchronicityCompatibility: .compatible,
          typeCompatibility: .inapplicable
        )
      ),
    ]
    XCTAssertEqual(bestMatches("tamic", decoys + [expected]).first, expected.text)
    // The repeating pattern at the front exhausts the .thorough scoring search. Even when that happens, we need to
    // still find the anchored first character of each leading token match, since it's a special case of fast
    // matching.
    test(
      "tamic",
      precision: .thorough,
      prefers: "ttttttttttaaaaaaaaaammmmmmmmmmiiiiiiiiiiccccccccccAutoresizingMaskIntoConstraints",
      over: "NSDataWritingAtomic"
    )

  }

  func test30956224() {
    let type = SemanticScoredText("RunContextManager", .partial(completionKind: .type))
    let method = SemanticScoredText("runContextManager", .partial(completionKind: .function))

    test("RunContext", precision: .thorough, prefers: type, over: method)
    test("runContext", precision: .thorough, prefers: method, over: type)
  }

  func test31615625() {
    let classFromProject = SemanticScoredText(
      "SwiftUnarchiver",
      .partial(completionKind: .type, moduleProximity: .imported(distance: 0))
    )

    let enumFromProject = SemanticScoredText(
      "UnarchivingError",
      .partial(completionKind: .enumCase, moduleProximity: .imported(distance: 1))
    )
    let classFromSDK = SemanticScoredText(
      "NSUnarchiver",
      .partial(completionKind: .type, moduleProximity: .imported(distance: 1))
    )
    let typedefFromSDK = SemanticScoredText(
      "KeyedUnarchiver",
      .partial(completionKind: .type, moduleProximity: .imported(distance: 1))
    )

    test("Unarchiver", precision: .thorough, prefers: classFromProject, over: enumFromProject)
    test("Unarchiver", precision: .thorough, prefers: classFromProject, over: classFromSDK)
    test("Unarchiver", precision: .thorough, prefers: classFromProject, over: typedefFromSDK)
  }

  func test76104403() throws {
    let button = SemanticScoredText(
      "Button",
      .partial(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .sdk,
        synchronicityCompatibility: .unknown,
        typeCompatibility: .inapplicable
      )
    )
    let menuButtonStyle = SemanticScoredText(
      "menuButtonStyle()",
      .partial(
        availability: .available,
        completionKind: .function,
        flair: [],
        moduleProximity: .imported(distance: 1),
        popularity: .none,
        scopeProximity: .inheritedContainer,
        structuralProximity: .sdk,
        synchronicityCompatibility: .unknown,
        typeCompatibility: .compatible
      )
    )
    let fullPrefix = "Button"
    for prefixLength in 1...fullPrefix.count {
      let prefix = String(fullPrefix.prefix(prefixLength))
      test(prefix, precision: .thorough, prefers: button, over: menuButtonStyle)
    }
  }

  func test75842586() {
    let goodMatch = SemanticScoredText(
      "methodOnString()",
      .partial(
        completionKind: .function,
        flair: [],
        moduleProximity: .imported(distance: 0),
        scopeProximity: .global
      )
    )
    let badMatch = SemanticScoredText(
      "methodOnText()",
      .partial(
        availability: .unknown,
        completionKind: .function,
        flair: [],
        moduleProximity: .unknown,
        popularity: .none,
        scopeProximity: .unknown,
        structuralProximity: .unknown,
        synchronicityCompatibility: .unknown,
        typeCompatibility: .unknown
      )
    )
    XCTAssertEqual(bestMatches("method", [goodMatch, badMatch]), [goodMatch.text])
  }

  func testBestMatchesSemanticCutoffs() {
    let typicalScore = SemanticClassification(
      availability: .available,
      completionKind: .function,
      flair: [],
      moduleProximity: .same,
      popularity: .none,
      scopeProximity: .inheritedContainer,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .unrelated
    ).score
    let badScore = SemanticClassification(
      availability: .unknown,
      completionKind: .function,
      flair: [],
      moduleProximity: .unknown,
      popularity: .unspecified,
      scopeProximity: .unknown,
      structuralProximity: .unknown,
      synchronicityCompatibility: .unknown,
      typeCompatibility: .unknown
    ).score
    XCTAssertEqual(
      bestMatches(
        "method",
        [
          SemanticScoredText("methodA", typicalScore),
          SemanticScoredText("methodB", badScore),
        ]
      ),
      ["methodA"]
    )
    XCTAssertEqual(
      bestMatches(
        "method",
        [
          SemanticScoredText("mexthxodA", typicalScore),
          SemanticScoredText("methodB", badScore),
        ]
      ),
      ["methodB"]
    )
  }

  func test75074752() {
    XCTAssertEqual(
      bestMatches(
        "superduper",
        [
          "CMAudioSampleBufferCreateWithPacketDescriptions(allocator:dataBuffer:dataReady:makeDataReadyCallback:refcon:formatDescription:sampleCount:presentationTimeStamp:packetDescriptions:sampleBufferOut:)"
        ]
      ),
      []
    )
    XCTAssertEqual(
      bestMatches(
        "zhskdyd",
        [
          "init(calendar:timeZone:era:year:month:day:hour:minute:second:nanosecond:weekday:weekdayOrdinal:quarter:weekOfMonth:weekOfYear:yearForWeekOfYear:)"
        ]
      ),
      []
    )
    XCTAssertEqual(
      bestMatches(
        "CMAudioSample",
        [
          "semanticScore(completionKind:deprecationStatus:flair:moduleProximity:popularity:scopeProximity:structuralProximity:synchronicityCompatibility:typeCompatibility:)"
        ]
      ),
      []
    )
  }

  func test76074456() throws {
    let greatTextMatches = [
      SemanticScoredText(0.15, "frame"),
      SemanticScoredText(0.15, "frameIdle"),
      SemanticScoredText(0.15, "frameRate"),
      SemanticScoredText(0.15, "frameBlank"),
      SemanticScoredText(0.15, "frameCount"),
      SemanticScoredText(0.15, "frameLength"),
      SemanticScoredText(0.15, "FrameStyle"),
      SemanticScoredText(0.15, "frameComplete"),
      SemanticScoredText(0.15, "frameInterval"),
      SemanticScoredText(0.15, "frameRotation"),
      SemanticScoredText(0.15, "frameDescriptor"),
      SemanticScoredText(0.15, "frame(ofColumn:)"),
      SemanticScoredText(0.15, "frameAutosaveName"),
      SemanticScoredText(0.15, "frameForItem(at:)"),
      SemanticScoredText(0.15, "frameCenterRotation"),
      SemanticScoredText(0.15, "frame(ofRow:inColumn:)"),
      SemanticScoredText(0.15, "frame(withWidth:using:)"),
      SemanticScoredText(0.15, "frame(forAlignmentRect:)"),
      SemanticScoredText(0.15, "frame(ofInsideOfColumn:)"),
      SemanticScoredText(0.15, "frameDidChangeNotification"),
    ]
    let greatSemanticMatch = SemanticScoredText(1.45, "text(inFrames:)")
    XCTAssertEqual(
      bestMatches("frame", greatTextMatches + [greatSemanticMatch], maximumNumberOfItemsForExpensiveSelection: 5)
        .first,
      greatSemanticMatch.text
    )
  }

  func testMatchCollatorUsesThoroughScoringWithOneCharacterPatternIfThereAreFewMatches_100039832() {
    let pattern = Pattern(text: "h")
    // During fast matching, these will both match like "widt[h]:...", but during the thorough match one will match
    // like "width:[h]eight:alignment:". We want to ensure that's happening even though the filter text isn't as
    // long as `MatchCollator.minimumPatternLengthToAlwaysRescoreWithThoroughPrecision`.
    let batch = CandidateBatch(symbols: [
      "width:alignment:",
      "width:height:alignment:",
    ])
    let matches = batch.indices.map { index in
      MatchCollator.Match(
        batchIndex: 0,
        candidateIndex: index,
        groupID: nil,
        score: .init(textComponent: 1.0, semanticComponent: 1.0)
      )
    }
    let selection = MatchCollator.selectBestMatches(
      matches,
      from: [batch],
      for: pattern,
      influencingTokenizedIdentifiers: [],
      orderingTiesBy: { _, _ in false },
      maximumNumberOfItemsForExpensiveSelection: MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection
    )
    let bestMatches = selection.matches.map { match in
      batch[stringAt: match.candidateIndex]
    }
    XCTAssertEqual(bestMatches.first, "width:height:alignment:")
    XCTAssertEqual(selection.precision, .thorough)
  }

  func testBestMatchesBoundaries() {
    for patternLength in 0..<(MatchCollator.minimumPatternLengthToAlwaysRescoreWithThoroughPrecision + 1) {
      let patternText = String(repeating: "a", count: patternLength)
      let differingCandidates = (0..<(MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection * 2)).map {
        length in
        patternText + String(repeating: "a", count: length)
      }
      let justTooFewIdenticalCandidates = Array(
        repeating: patternText,
        count: MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection - 1
      )
      let justEnoughIdenticalCandidates = Array(
        repeating: patternText,
        count: MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection
      )
      let justTooManyIdenticalCandidates = Array(
        repeating: patternText,
        count: MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection + 1
      )
      for candidates in [
        justTooFewIdenticalCandidates, justEnoughIdenticalCandidates, justTooManyIdenticalCandidates,
        differingCandidates,
      ] {
        let matches = bestMatches(patternText, candidates)
        if patternLength < MatchCollator.minimumPatternLengthToAlwaysRescoreWithThoroughPrecision {
          XCTAssertEqual(matches, candidates)
        } else {
          let expectedMax = MatchCollator.defaultMaximumNumberOfItemsForExpensiveSelection
          XCTAssert(
            matches == Array(candidates.prefix(expectedMax)),
            "Expected \(expectedMax) matches, but got:\n    - \(matches.joined(separator: "\n    - "))"
          )
        }
      }
    }
  }

  private struct CompletionExample {
    var patternUTF8Length: Int
    var textScore: Double
    var pattern: String
    var candidate: String
    init(pattern: String, candidate: String) {
      self.pattern = pattern
      self.candidate = candidate
      self.patternUTF8Length = pattern.utf8.count
      self.textScore = self.candidate.withUTF8 { candidateUTF8Bytes in
        Pattern(text: pattern).score(
          candidate: candidateUTF8Bytes,
          contentType: .codeCompletionSymbol,
          precision: .thorough
        )
      }
    }
  }

  private var badCompletionExamples: [CompletionExample] = {
    return [
      ("po", "exponent"),
      ("on", "exponent"),
      ("ne", "exponent"),
      ("nf", "infinity"),
      ("fi", "infinity"),
      ("ni", "infinity"),
      ("ghi", "rightMouseUp(with:)"),
      ("oef", "logReferenceTree()"),
      ("oef", "makeBaseWritingDirectionLeftToRight()"),
      ("cron", "scrollRectToVisible(,animated:)"),
      ("ptop", "newScriptingObject(of:,forValueForKey:,withContentsValue:,properties:)"),
      ("ptoc", "init(format:,options:,locale:)"),
      ("abcde", "outlineTableColumnIndex"),
      ("aeiou", "classForUserDefinedRuntimeAttributesPlaceholder()"),
      ("croner", "descriptionForAssertionMessage"),
      ("cornerz", "init(recordZonesToSave:,recordZoneIDsToDelete:)"),
      ("holferf", "shouldBufferInAnticipationOfPlayback"),
      (
        "ounasdaa",
        "init(chunkSampleCount:,chunkHasUniformSampleSizes:,chunkHasUniformSampleDurations:,chunkHasUniformFormatDescriptions:)"
      ),
      ("ounasdaal", "init(nickname:,number:,accountType:,organizationName:,balance:,secondaryBalance:)"),
      ("ounasdaar", "init(time:,type:,isDurationBoundary:,isMarkerBoundary:,isSelectedTimeRangeBoundary:)"),
      (
        "ounasduari",
        "init(chunkSampleCount:,chunkHasUniformSampleSizes:,chunkHasUniformSampleDurations:,chunkHasUniformFormatDescriptions:)"
      ),
    ].map(CompletionExample.init)
  }()

  /// A longer match has a higher score, so matching "a" against "aaa" might score 1, and then matching "aa" against
  /// "aaa" might score as 2. Because of this, the cutoff is a function of the length.
  private func generateBestRejectedTextScoreByPatternLength() -> [Double] {
    let maxPatternUTF8Length = badCompletionExamples.map(\.patternUTF8Length).max() ?? 0
    var bestRejectedTextScoreByPatternLength: [Double] = Array(repeating: 0, count: maxPatternUTF8Length + 1)

    for badCompletionExample in badCompletionExamples {
      bestRejectedTextScoreByPatternLength[badCompletionExample.patternUTF8Length] = max(
        bestRejectedTextScoreByPatternLength[badCompletionExample.patternUTF8Length],
        badCompletionExample.textScore
      )
    }

    // If we computed a cutoff of 1.5 for a 4 character pattern, and then our worst example for a 5 character
    // pattern was 1.1, then, use the 1.5 value since longer matches have longer scores.
    for (previousIndex, nextIndex) in zip(
      bestRejectedTextScoreByPatternLength.indices,
      bestRejectedTextScoreByPatternLength.indices.dropFirst()
    ) {
      bestRejectedTextScoreByPatternLength[nextIndex] = max(
        bestRejectedTextScoreByPatternLength[nextIndex],
        bestRejectedTextScoreByPatternLength[previousIndex]
      )
    }

    return bestRejectedTextScoreByPatternLength
  }

  func testMinimumTextCutoff() {
    for awfulCompletionExample in badCompletionExamples {
      let matches = self.bestMatches(awfulCompletionExample.pattern, [awfulCompletionExample.candidate])
      XCTAssertEqual(matches, [])
    }
    if MatchCollator.bestRejectedTextScoreByPatternLength != generateBestRejectedTextScoreByPatternLength() {
      let literals = generateBestRejectedTextScoreByPatternLength().map { cutoff in
        "        \(cutoff),\n"
      }.joined()
      let code =
        "    internal static let bestRejectedTextScoreByPatternLength: [Double] = [\n" + literals + "    ]\n"
      XCTFail("Update MatchCollator.bestRejectedTextScoreByPatternLength to:\n" + code)
    }
  }

  func testBorderlineCompletionsThatShouldPassMinimumTextCutoff() {
    for leadingDecoy in [
      "", "zzz", "zzzZzzzzz", "zzzZzzzzzZzzzzzzzzzzz", "zzzZzzzzzZzzzzzzzzzzzZzzzzzzzzzzzzzzzzzzzzzzz",
    ] {
      for trailingDecoy in [
        "", "Zzz", "ZzzZzzzzz", "ZzzZzzzzzZzzzzzzzzzzz", "ZzzZzzzzzZzzzzzzzzzzzZzzzzzzzzzzzzzzzzzzzzzzz",
      ] {
        func test(_ pattern: String, matches candidate: String) {
          let casedCandidate = leadingDecoy.isEmpty ? candidate : candidate.capitalized
          let disguised = leadingDecoy + casedCandidate + trailingDecoy
          let matches = bestMatches(pattern, [disguised])
          XCTAssertEqual(matches, [disguised])
        }
        test("order", matches: "border")
        test("load", matches: "download")
        test("not", matches: "cannot")
        test("our", matches: "your")
        test("ous", matches: "supercalifragilisticexpialidocious")
        test("frag", matches: "supercalifragilisticexpialidocious")
      }
    }
  }

  func testDecentMatchesAreNotCompletelyExcludedGivenGreatMatches() {
    func test(_ filter: String, _ candidates: [String]) {
      let matches = bestMatches(filter, candidates)
      XCTAssertEqual(Set(matches), Set(candidates))
    }
    test("GKPlayer", ["GKPlayer", "GKLocalPlayer"])
    test(
      "MTLShar",
      ["MTLSharedEventHandle", "MTLSharedEventListener", "MTLSharedTextureHandle", "MTLStorageModeShared"]
    )
  }

  func testExclusionOfMiddleOfWordCompactMatches() {
    XCTAssertEqual(bestMatches("HSta", ["HStack", "ABC_FHSTAT"]), ["HStack"])
    XCTAssertEqual(bestMatches("HSta", ["HStack", "errSecCSHostProtocolStateError"]), ["HStack"])
  }

  func testTypeNameOverLocalWithCaseMatch_88653597() {
    let localVariable = SemanticScoredText(
      "imageCache",
      SemanticClassification(
        availability: .available,
        completionKind: .variable,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .local,
        structuralProximity: .project(fileSystemHops: 0),
        synchronicityCompatibility: .compatible,
        typeCompatibility: .compatible
      )
    )
    let typeName = SemanticScoredText(
      "ImageCache",
      SemanticClassification(
        availability: .available,
        completionKind: .type,
        flair: [],
        moduleProximity: .imported(distance: 0),
        popularity: .none,
        scopeProximity: .global,
        structuralProximity: .project(fileSystemHops: 0),
        synchronicityCompatibility: .compatible,
        typeCompatibility: .compatible
      )
    )
    for prefixLength in 1...typeName.text.count {
      let prefix = String(typeName.text.prefix(prefixLength))
      XCTAssertEqual(bestMatches(prefix, [localVariable, typeName]), [typeName.text, localVariable.text])
    }
  }

  func test75845907() {
    let patternText = "separateSecondary"
    patternText.enumeratePrefixes(includeLowercased: true) { patternText in
      let results = bestMatches(
        patternText,
        [
          "separateSecondaryViewController(for:)",
          "splitViewController(:separateSecondaryFrom:)",
        ]
      )
      XCTAssertEqual(
        results.count,
        2,
        "The contiguous pattern \"\(patternText)\" should still show both results."
      )
    }
  }

  func testOrderingOverloads() {
    struct Completion {
      var filterText: String
      var displayText: String
    }
    let completions: [Completion] = [
      .init(filterText: "theFunction(argument:)", displayText: "theFunction(argument: Int)"),
      .init(filterText: "theFunction(argument:)", displayText: "theFunction(argument: String)"),
      .init(filterText: "theFunction(argument:)", displayText: "theFunction(argument: Double)"),
      .init(filterText: "theFunction(argument:)", displayText: "theFunction(argument: Bool)"),
      .init(filterText: "theFunction(argument:)", displayText: "theFunction(argument: UInt)"),
    ]
    let pattern = Pattern(text: "the")
    let batch = CandidateBatch(symbols: completions.map(\.filterText))
    let textScoredMatches = pattern.scoredMatches(across: [batch], precision: .fast)
    let matches: [MatchCollator.Match] = textScoredMatches.map { match in
      MatchCollator.Match(
        batchIndex: match.batchIndex,
        candidateIndex: match.candidateIndex,
        groupID: nil,
        score: CompletionScore(textComponent: match.textScore, semanticComponent: 1.0)
      )
    }
    let bestMatches = MatchCollator.selectBestMatches(
      for: pattern,
      from: matches,
      in: [batch],
      influencingTokenizedIdentifiers: []
    ) { lhs, rhs in
      let lhsDisplayText = completions[lhs.candidateIndex].displayText
      let rhsDisplayText = completions[rhs.candidateIndex].displayText
      return lhsDisplayText < rhsDisplayText
    }
    let bestMatchesDisplayText = bestMatches.map { bestMatch in
      completions[bestMatch.candidateIndex].displayText
    }
    XCTAssertEqual(
      bestMatchesDisplayText,
      [
        "theFunction(argument: Bool)",
        "theFunction(argument: Double)",
        "theFunction(argument: Int)",
        "theFunction(argument: String)",
        "theFunction(argument: UInt)",
      ]
    )
  }

  func testDeprecatedGroupMembersComeLater() {
    // Notice that the semantically worse results are textually better matches - they're shorter, and sort
    // lexicographically earlier.
    let type = "TextField"
    let initializer = "TextField(:text:prompt:)"
    let softDeprecatedInitializer = "TextField(:text:)"
    let deprecatedInitializer = "TextField()"
    let items = [
      SemanticScoredText(type, SemanticClassification.partial(completionKind: .type).score, groupID: 1),
      SemanticScoredText(
        initializer,
        SemanticClassification.partial(completionKind: .initializer).score,
        groupID: 1
      ),
      SemanticScoredText(
        softDeprecatedInitializer,
        SemanticClassification.partial(availability: .softDeprecated, completionKind: .initializer).score,
        groupID: 1
      ),
      SemanticScoredText(
        deprecatedInitializer,
        SemanticClassification.partial(availability: .deprecated, completionKind: .initializer).score,
        groupID: 1
      ),
    ]
    XCTAssertEqual(
      bestMatches("TextField", items),
      [type, initializer, deprecatedInitializer, softDeprecatedInitializer]
    )
  }

  func testOverlappingAndSparseGroupIDs() {
    func scoreAsTiesAndSelectAll(
      pattern: Pattern,
      overlappingGroupID: Int,
      from batchesOfScoredText: [[SemanticScoredText]]
    ) -> [String] {
      typealias Match = MatchCollator.Match
      let batches = batchesOfScoredText.map { batchOfScoredText in
        CandidateBatch(candidates: batchOfScoredText)
      }
      var matches: [Match] = []
      for (batchIndex, batch) in batchesOfScoredText.enumerated() {
        for (candidateIndex, semanticScoredText) in batch.enumerated() {
          let score = CompletionScore(textComponent: 1, semanticComponent: semanticScoredText.semanticScore)
          matches.append(
            Match(
              batchIndex: batchIndex,
              candidateIndex: candidateIndex,
              groupID: overlappingGroupID,
              score: score
            )
          )
        }
      }
      let bestMatches = MatchCollator.selectBestMatches(
        for: pattern,
        from: matches,
        in: batches,
        influencingTokenizedIdentifiers: [],
        orderingTiesBy: { _, _ in false }
      )
      return bestMatches.map { match in
        batches[match.batchIndex][stringAt: match.candidateIndex]
      }
    }

    for groupID in [0, 1, -1, Int.max, Int.min] {
      for reverseBatches in [false, true] {
        for reverseA in [false, true] {
          for reverseB in [false, true] {
            for aSemanticScore in [1.0, 2.0] {
              for bSemanticScore in [1.0, 2.0] {
                let aText = ["pA", "pA()", "pA(a:)"]
                let bText = ["pB", "pB()", "pB(b:)"]
                let aScoredText = aText.map { SemanticScoredText($0, aSemanticScore) }
                let bScoredResults = bText.map { SemanticScoredText($0, bSemanticScore) }
                let results = scoreAsTiesAndSelectAll(
                  pattern: Pattern(text: "p"),
                  overlappingGroupID: groupID,
                  from: [
                    aScoredText.conditionallyReversed(reverseA),
                    bScoredResults.conditionallyReversed(reverseB),
                  ].conditionallyReversed(reverseBatches)
                )
                let expectedOrder = aSemanticScore >= bSemanticScore ? aText + bText : bText + aText
                XCTAssertEqual(results, expectedOrder)
              }
            }
          }
        }
      }
    }
  }

  func testGrouping() {
    let okTypeScore = SemanticClassification(
      availability: .available,
      completionKind: .type,
      flair: [],
      moduleProximity: .imported(distance: 0),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score
    let okInitializerScore = SemanticClassification(
      availability: .available,
      completionKind: .initializer,
      flair: [],
      moduleProximity: .imported(distance: 0),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .inapplicable
    ).score

    let greatTypeScore = SemanticClassification(
      availability: .available,
      completionKind: .type,
      flair: [],
      moduleProximity: .same,
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .project(fileSystemHops: 0),
      synchronicityCompatibility: .compatible,
      typeCompatibility: .compatible
    ).score
    let greatInitializerScore = SemanticClassification(
      availability: .available,
      completionKind: .initializer,
      flair: [],
      moduleProximity: .same,
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .project(fileSystemHops: 0),
      synchronicityCompatibility: .compatible,
      typeCompatibility: .compatible
    ).score

    let greatLocalScore = SemanticClassification(
      availability: .available,
      completionKind: .variable,
      flair: [],
      moduleProximity: .same,
      popularity: .none,
      scopeProximity: .local,
      structuralProximity: .project(fileSystemHops: 0),
      synchronicityCompatibility: .compatible,
      typeCompatibility: .compatible
    ).score
    let poorGlobalScore = SemanticClassification(
      availability: .available,
      completionKind: .initializer,
      flair: [],
      moduleProximity: .imported(distance: 1),
      popularity: .none,
      scopeProximity: .global,
      structuralProximity: .sdk,
      synchronicityCompatibility: .compatible,
      typeCompatibility: .compatible
    ).score

    let results = bestMatches(
      "tex",
      [
        SemanticScoredText("text", greatLocalScore),
        SemanticScoredText("initializeTextSubsystem()", poorGlobalScore),
        SemanticScoredText("Text", okTypeScore, groupID: 0),
        SemanticScoredText("TextualAnalyzer", okTypeScore, groupID: 2),
        SemanticScoredText("TextField", greatTypeScore, groupID: 1),
        SemanticScoredText("Text(string:)", okInitializerScore, groupID: 0),
        SemanticScoredText("Text(string:encoding:conicalize:validate:)", okInitializerScore, groupID: 0),
        SemanticScoredText("TextField()", greatInitializerScore, groupID: 1),
        SemanticScoredText("TextField(text:)", greatInitializerScore, groupID: 1),
        SemanticScoredText(
          "TextField(text:alignment:wrapping:maximumNumberOfLines:font:)",
          okInitializerScore,
          groupID: 1
        ),
        SemanticScoredText("TextualAnalyzer()", okInitializerScore, groupID: 2),
      ]
    )
    XCTAssertEqual(
      results,
      [
        "text",

        "TextField",
        "TextField()",
        "TextField(text:)",
        "TextField(text:alignment:wrapping:maximumNumberOfLines:font:)",

        "Text",
        "Text(string:)",
        "Text(string:encoding:conicalize:validate:)",

        "TextualAnalyzer",
        "TextualAnalyzer()",

        "initializeTextSubsystem()",
      ]
    )

  }

  func testGroupingWithEqualGroupScores() {
    for (foodID, footID) in [(0, 1), (1, 0)] {
      let candidates = [
        SemanticScoredText("food", groupID: foodID),
        SemanticScoredText("foot", groupID: footID),
        SemanticScoredText("food()", groupID: foodID),
        SemanticScoredText("foot()", groupID: footID),
      ]
      let expectedOrder = [
        "food",
        "food()",
        "foot",
        "foot()",
      ]
      let prefix = "foo"
      XCTAssertEqual(bestMatches(prefix, candidates), expectedOrder)
      XCTAssertEqual(bestMatches(prefix, candidates.reversed()), expectedOrder)  // Verify initial order doesn't matter
    }
  }

  func testBulkLoading() {
    typealias UTF8Bytes = Pattern.UTF8Bytes
    let typeStrings = [
      "",
      "a",
      "Word",
    ]
    let typeUTF8Buffers = typeStrings.map { typeString in
      typeString.allocateCopyOfUTF8Buffer()
    };
    defer {
      for typeUTF8Buffer in typeUTF8Buffers {
        typeUTF8Buffer.deallocate()
      }
    }

    let bulkStringLoaded = CandidateBatch(candidates: typeStrings, contentType: .unknown)
    let bulkByteLoaded = CandidateBatch(candidates: typeUTF8Buffers, contentType: .unknown)
    let singeBytesLoaded = {  // To get unused variables if we forget to compare one.
      var batch = CandidateBatch()
      for typeUTF8Buffer in typeUTF8Buffers {
        batch.append(typeUTF8Buffer, contentType: .unknown)
      }
      return batch
    }()

    let singeStringLoaded = {
      var batch = CandidateBatch()
      for typeString in typeStrings {
        batch.append(typeString, contentType: .unknown)
      }
      return batch
    }()

    let baseline = bulkStringLoaded
    XCTAssertEqual(baseline, bulkStringLoaded)
    XCTAssertEqual(baseline, bulkByteLoaded)
    XCTAssertEqual(baseline, singeBytesLoaded)
    XCTAssertEqual(baseline, singeStringLoaded)
  }
}

fileprivate extension CandidateBatch {
  var strings: [String] {
    (0..<count).map { index in
      self[stringAt: index]
    }
  }

  func mapMatches<T>(pattern: Pattern, precision: Pattern.Precision, expression: (Int, Double) -> T) -> [T] {
    var resutls: [T] = []
    enumerate { candidateIndex, candidate in
      if pattern.matches(candidate: candidate) {
        resutls.append(expression(candidateIndex, pattern.score(candidate: candidate, precision: precision)))
      }
    }
    return resutls
  }
}

fileprivate extension Pattern {
  func seariallyScoreMatches(in batch: CandidateBatch, precision: Precision) -> [CandidateBatchMatch] {
    let resutls = batch.mapMatches(pattern: self, precision: precision) { index, score in
      CandidateBatchMatch(candidateIndex: index, textScore: score)
    }
    return resutls
  }

  func seariallyScoreMatches(across batches: [CandidateBatch], precision: Precision) -> [CandidateBatchesMatch] {
    var combinedResults: [CandidateBatchesMatch] = []
    for (batchIndex, batch) in batches.enumerated() {
      let batchResults = batch.mapMatches(pattern: self, precision: precision) { candidateIndex, score in
        CandidateBatchesMatch(batchIndex: batchIndex, candidateIndex: candidateIndex, textScore: score)
      }
      combinedResults.append(contentsOf: batchResults)
    }
    return combinedResults
  }
}

extension Array {
  func conditionallyReversed(_ condition: Bool) -> Array {
    condition ? reversed() : self
  }
}

extension SemanticClassification {
  static let allSymbolsClassification = Self(
    availability: .unknown,
    completionKind: .unknown,
    flair: [],
    moduleProximity: .unknown,
    popularity: .none,
    scopeProximity: .unknown,
    structuralProximity: .unknown,
    synchronicityCompatibility: .unknown,
    typeCompatibility: .unknown
  )
}
