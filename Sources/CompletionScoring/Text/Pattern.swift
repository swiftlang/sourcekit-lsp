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

/// The pattern that the user has typed and which should be used to cull and score results.
package final class Pattern: Sendable {
  package typealias ContentType = Candidate.ContentType
  package typealias UTF8Bytes = UnsafeBufferPointer<UInt8>
  package typealias UTF8ByteRange = Range<Int>
  package enum Precision {
    case fast
    case thorough
  }

  package let text: String

  /// These all have pattern in the name to avoid confusion with their candidate counterparts in functions operating on both.
  // `nonisolated(unsafe)` is fine because the underlying buffer is never modified.
  private nonisolated(unsafe) let patternMixedcaseBytes: UTF8Bytes
  private nonisolated(unsafe) let patternLowercaseBytes: UTF8Bytes
  private let patternRejectionFilter: RejectionFilter
  /// For each byte in `text`, a rejection filter that contains all the characters occurring after or at that offset.
  ///
  /// This way when we have already matched the first 4 bytes, we can check which characters occur from byte 5 onwards
  /// and check that they appear in the candidate's remaining text.
  private let patternSuccessiveRejectionFilters: [RejectionFilter]
  private let patternHasMixedcase: Bool
  internal var patternUTF8Length: Int { patternMixedcaseBytes.count }

  package init(text: String) {
    self.text = text
    let mixedcaseBytes = Array(text.utf8)
    let lowercaseBytes = mixedcaseBytes.map(\.lowercasedUTF8Byte)
    self.patternMixedcaseBytes = UnsafeBufferPointer.allocate(copyOf: mixedcaseBytes)
    self.patternLowercaseBytes = UnsafeBufferPointer.allocate(copyOf: lowercaseBytes)
    self.patternRejectionFilter = .init(lowercaseBytes: lowercaseBytes)
    self.patternHasMixedcase = lowercaseBytes != mixedcaseBytes
    self.patternSuccessiveRejectionFilters = UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      return lowercaseBytes.withUnsafeBufferPointer { lowercaseBytes in
        var rejectionFilters = Self.allocateSuccessiveRejectionFilters(
          lowercaseBytes: lowercaseBytes,
          allocator: &allocator
        )
        defer { allocator.deallocate(&rejectionFilters) }
        return Array(rejectionFilters)
      }
    }
  }

  deinit {
    patternMixedcaseBytes.deallocate()
    patternLowercaseBytes.deallocate()
  }

  /// Perform an insensitive greedy match and return the location where the greedy match stared if it succeeded.
  /// If the match was not successful, return `nil`.
  ///
  /// Future searches used during scoring can use this location to jump past all of the initial bytes that don't match
  /// anything. An empty pattern matches with location 0.
  private func matchLocation(candidate: Candidate) -> Int? {
    if RejectionFilter.match(pattern: patternRejectionFilter, candidate: candidate.rejectionFilter) == .maybe {
      let cBytes = candidate.bytes
      let pCount = patternLowercaseBytes.count
      let cCount = cBytes.count
      var pRemaining = pCount
      var cRemaining = cCount
      if (pRemaining > 0) && (cRemaining > 0) && (pRemaining <= cRemaining) {
        let pFirst = patternLowercaseBytes[0]
        let cStart = cBytes.firstIndex { cByte in
          cByte.lowercasedUTF8Byte == pFirst
        }
        if let cStart = cStart {
          cRemaining -= cStart
          cRemaining -= 1
          pRemaining -= 1
          // While we're not at the end and the remaining pattern is as short or shorter than the remaining candidate.
          while (pRemaining > 0) && (cRemaining > 0) && (pRemaining <= cRemaining) {
            let cIdx = cCount - cRemaining
            let pIdx = pCount - pRemaining
            if cBytes[cIdx].lowercasedUTF8Byte == patternLowercaseBytes[pIdx] {
              pRemaining -= 1
            }
            cRemaining -= 1
          }
          return (pRemaining == 0) ? cStart : nil
        }
      }
      return pCount == 0 ? 0 : nil
    }
    return nil
  }

  package func matches(candidate: Candidate) -> Bool {
    matchLocation(candidate: candidate) != nil
  }

  package func score(candidate: Candidate, precision: Precision) -> Double {
    score(candidate: candidate.bytes, contentType: candidate.contentType, precision: precision)
  }

  package func score(
    candidate candidateMixedcaseBytes: UTF8Bytes,
    contentType: ContentType,
    precision: Precision
  ) -> Double {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      score(
        candidate: candidateMixedcaseBytes,
        contentType: contentType,
        precision: precision,
        allocator: &allocator
      )
      .value
    }
  }

  package struct TextScore: Comparable {
    package var value: Double
    package var falseStarts: Int

    static let worstPossibleScore = TextScore(value: -Double.infinity, falseStarts: Int.max)

    package init(value: Double, falseStarts: Int) {
      self.value = value
      self.falseStarts = falseStarts
    }

    package static func < (_ lhs: Self, _ rhs: Self) -> Bool {
      return (lhs.value <? rhs.value)
        ?? (lhs.falseStarts > rhs.falseStarts)
    }

    fileprivate static let emptyMatchScore = TextScore(value: 1.0, falseStarts: 0)
    fileprivate static let noMatchScore = TextScore(value: 0.0, falseStarts: 0)
  }

  internal func matchAndScore(
    candidate: Candidate,
    precision: Precision,
    allocator: inout UnsafeStackAllocator
  ) -> TextScore? {
    return matchLocation(candidate: candidate).map { firstMatchingLowercaseByteIndex in
      if patternLowercaseBytes.hasContent {
        var indexedCandidate = IndexedCandidate.allocate(
          referencing: candidate.bytes,
          patternByteCount: patternLowercaseBytes.count,
          firstMatchingLowercaseByteIndex: firstMatchingLowercaseByteIndex,
          contentType: candidate.contentType,
          allocator: &allocator
        )
        defer { indexedCandidate.deallocate(allocator: &allocator) }
        return score(
          candidate: &indexedCandidate,
          precision: precision,
          captureMatchingRanges: false,
          allocator: &allocator
        )
      } else {
        return .emptyMatchScore
      }
    }
  }

  package func score(
    candidate candidateMixedcaseBytes: UTF8Bytes,
    contentType: ContentType,
    precision: Precision,
    allocator: inout UnsafeStackAllocator
  ) -> TextScore {
    if patternLowercaseBytes.hasContent {
      var candidate = IndexedCandidate.allocate(
        referencing: candidateMixedcaseBytes,
        patternByteCount: patternLowercaseBytes.count,
        firstMatchingLowercaseByteIndex: nil,
        contentType: contentType,
        allocator: &allocator
      )
      defer { candidate.deallocate(allocator: &allocator) }
      return score(
        candidate: &candidate,
        precision: precision,
        captureMatchingRanges: false,
        allocator: &allocator
      )
    } else {
      return .emptyMatchScore
    }
  }

  package func score(
    candidate candidateMixedcaseBytes: UTF8Bytes,
    contentType: ContentType,
    precision: Precision,
    captureMatchingRanges: Bool,
    ranges: inout [UTF8ByteRange]
  ) -> Double {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      if patternLowercaseBytes.hasContent {
        var candidate = IndexedCandidate.allocate(
          referencing: candidateMixedcaseBytes,
          patternByteCount: patternLowercaseBytes.count,
          firstMatchingLowercaseByteIndex: nil,
          contentType: contentType,
          allocator: &allocator
        )
        defer { candidate.deallocate(allocator: &allocator) }
        let score = score(
          candidate: &candidate,
          precision: precision,
          captureMatchingRanges: captureMatchingRanges,
          allocator: &allocator
        )
        if captureMatchingRanges {
          ranges = Array(candidate.matchedRanges)
        }
        return score.value
      } else {
        return TextScore.emptyMatchScore.value
      }
    }
  }

  private func score(
    candidate: inout IndexedCandidate,
    precision: Precision,
    captureMatchingRanges: Bool,
    allocator: inout UnsafeStackAllocator
  ) -> TextScore {
    switch precision {
    case .fast:
      let matchStyle = populateMatchingRangesForFastScoring(&candidate)
      return singleScore(candidate: candidate, precision: precision, matchStyle: matchStyle)
    case .thorough:
      let budget = 5000
      return bestScore(
        candidate: &candidate,
        budget: budget,
        captureMatchingRanges: captureMatchingRanges,
        allocator: &allocator
      )
    }
  }

  private func eligibleForAcronymMatch(candidate: IndexedCandidate) -> Bool {
    return (patternLowercaseBytes.count >= 3)
      && candidate.contentType.isEligibleForAcronymMatch
      && candidate.tokenization.hasNonUppercaseNonDelimiterBytes
  }

  private enum MatchStyle: CaseIterable {
    case lowercaseContinuous
    case mixedcaseContinuous
    case mixedcaseGreedy
    case lowercaseGreedy
    case acronym
  }

  /// Looks for matches like `tamic` against `[t]ranslates[A]utoresizing[M]ask[I]nto[C]onstraints.`
  /// Or `MOC` against `NS[M]anaged[O]bject[C]ontext`.
  /// Accomplishes this by doing a greedy match over the acronym characters, which are the first characters of each token.
  private func populateMatchingRangesForAcronymMatch(_ candidate: inout IndexedCandidate) -> Bool {
    let tokenization = candidate.tokenization
    if eligibleForAcronymMatch(candidate: candidate) && tokenization.tokens.hasContent {
      let candidateLowercaseBytes = candidate.lowercaseBytes
      let allowFullMatchesBeginningWithTokenIndex =
        candidate.contentType.acronymMatchAllowsMultiCharacterMatchesAfterBaseName
        ? candidate.tokenization.firstNonBaseNameTokenIndex : candidate.tokenization.tokenCount
      var tidx = 0
      let tcnt = tokenization.tokens.count
      var cidx = 0
      let ccnt = candidateLowercaseBytes.count
      var pidx = 0
      let pcnt = patternLowercaseBytes.count

      var matches = true
      while (cidx < ccnt) && (pidx < pcnt) && (tidx < tcnt) && matches {
        let token = tokenization.tokens[tidx]
        var tcidx = 0
        let tccnt = (token.allUppercase || (tidx >= allowFullMatchesBeginningWithTokenIndex)) ? token.length : 1
        let initialCidx = cidx
        while (tcidx < tccnt) && (cidx < ccnt) && (pidx < pcnt) {
          if candidateLowercaseBytes[cidx] == patternLowercaseBytes[pidx] {
            tcidx += 1
            cidx += 1
            pidx += 1
          } else {
            break
          }
        }
        matches =
          (tcidx > 0)  // Matched any characters in this token
          // Allow skipping the first token if it's all uppercase
          || ((tidx == 0) && token.allUppercase)
          // Allow skipping single character delemiters
          || ((token.length == 1) && candidateLowercaseBytes[cidx].isDelimiter)

        if (tcidx > 0) {
          candidate.matchedRanges.append(initialCidx..<cidx)
        }
        cidx = initialCidx + token.length
        tidx += 1
      }

      matches = matches && (pidx == pcnt)
      matches =
        matches
        && ((cidx <= tokenization.baseNameLength) || !candidate.contentType.acronymMatchMustBeInBaseName)

      if !matches {
        candidate.matchedRanges.removeAll()
      }
      return matches
    } else {
      return false
    }
  }

  private static func populateMatchingContinuousRanges(
    _ ranges: inout UnsafeStackArray<UTF8ByteRange>,
    startOffset: Int,
    candidateBytes: UTF8Bytes,
    patternBytes: UTF8Bytes
  ) -> Bool {
    if let contiguousMatch = candidateBytes.rangeOf(bytes: patternBytes, startOffset: startOffset) {
      ranges.append(contiguousMatch)
      return true
    }
    return false
  }

  /// Returns `true` if the pattern matches the candidate according to the rules of the `matchStyle`.
  /// When successful, the matched ranges will be added to `ranges`. Otherwise `ranges` will be cleared.
  private func populateMatchingRanges(_ candidate: inout IndexedCandidate, matchStyle: MatchStyle) -> Bool {
    let startOffset = candidate.firstMatchingLowercaseByteIndex ?? 0
    switch matchStyle {
    case .lowercaseContinuous:
      return Self.populateMatchingContinuousRanges(
        &candidate.matchedRanges,
        startOffset: startOffset,
        candidateBytes: candidate.lowercaseBytes,
        patternBytes: patternLowercaseBytes
      )
    case .mixedcaseContinuous:
      return Self.populateMatchingContinuousRanges(
        &candidate.matchedRanges,
        startOffset: startOffset,
        candidateBytes: candidate.mixedcaseBytes,
        patternBytes: patternMixedcaseBytes
      )
    case .acronym:
      return populateMatchingRangesForAcronymMatch(&candidate)
    case .mixedcaseGreedy:
      return Self.populateGreedyMatchingRanges(
        &candidate.matchedRanges,
        startOffset: startOffset,
        candidateBytes: candidate.mixedcaseBytes,
        patternBytes: patternMixedcaseBytes
      )
    case .lowercaseGreedy:
      return Self.populateGreedyMatchingRanges(
        &candidate.matchedRanges,
        startOffset: startOffset,
        candidateBytes: candidate.lowercaseBytes,
        patternBytes: patternLowercaseBytes
      )
    }
  }

  /// Tries a fixed set of strategies in most to least desirable order for matching the candidate to the pattern.
  ///
  /// Returns the first strategy that matches.
  /// Generally this match will produce the highest score of the considered strategies, but this isn't known, and a
  /// higher scoring match could be found by the `.thorough` search.
  /// For example, the highest priority strategy is a case matched contiguous sequence. If you search for "name" in
  /// "filenames(name:)", this code will select the first one, but the second occurrence will score higher since it's a
  /// complete token.
  /// The fast scoring just needs to get the result into the second round though where `.thorough` will find the better
  /// match.
  private func populateMatchingRangesForFastScoring(_ candidate: inout IndexedCandidate) -> MatchStyle? {
    let startOffset = candidate.firstMatchingLowercaseByteIndex ?? 0
    if Self.populateMatchingContinuousRanges(
      &candidate.matchedRanges,
      startOffset: startOffset,
      candidateBytes: candidate.lowercaseBytes,
      patternBytes: patternLowercaseBytes
    ) {
      return .lowercaseContinuous
    } else if populateMatchingRangesForAcronymMatch(&candidate) {
      return .acronym
    } else if Self.populateGreedyMatchingRanges(
      &candidate.matchedRanges,
      startOffset: startOffset,
      candidateBytes: candidate.mixedcaseBytes,
      patternBytes: patternMixedcaseBytes
    ) {
      return .mixedcaseGreedy
    } else if Self.populateGreedyMatchingRanges(
      &candidate.matchedRanges,
      startOffset: startOffset,
      candidateBytes: candidate.lowercaseBytes,
      patternBytes: patternLowercaseBytes
    ) {
      return .lowercaseGreedy
    }
    return nil
  }

  /// Tries to match `patternBytes` against  `candidateBytes` by greedily matching the first occurrence of a character
  /// it finds, ignoring tokenization. For example, "filename" matches both "file(named:)" and "decoyfileadecoynamedecoy".
  ///
  /// If a successful match was found, returns `true` and populates `ranges` with the matched ranges.
  /// Otherwise `ranges` is cleared since it's used as scratch space.
  private static func populateGreedyMatchingRanges(
    _ ranges: inout UnsafeStackArray<UTF8ByteRange>,
    startOffset: Int,
    candidateBytes: UTF8Bytes,
    patternBytes: UTF8Bytes
  ) -> Bool {
    var cidx = startOffset, pidx = 0
    var currentlyMatching = false
    while (cidx < candidateBytes.count) && (pidx < patternBytes.count) {
      if candidateBytes[cidx] == patternBytes[pidx] {
        pidx += 1
        if !currentlyMatching {
          currentlyMatching = true
          ranges.append(cidx ..+ 0)
        }
        ranges[ranges.count - 1].extend(upperBoundBy: 1)
      } else {
        currentlyMatching = false
      }
      cidx += 1
    }
    let matched = pidx == patternBytes.count
    if !matched {
      ranges.removeAll()
    }
    return matched
  }

  private func singleScore(candidate: IndexedCandidate, precision: Precision, matchStyle: MatchStyle?) -> TextScore {
    func ratio(_ lhs: Int, _ rhs: Int) -> Double {
      return Double(lhs) / Double(rhs)
    }

    var patternCharactersRemaining = patternMixedcaseBytes.count
    let matchedRanges = candidate.matchedRanges
    if let firstMatchedRange = matchedRanges.first {
      let candidateMixedcaseBytes = candidate.mixedcaseBytes
      let tokenization = candidate.tokenization
      let prefixMatchBonusValue = candidate.contentType.prefixMatchBonus
      let contentAfterBasenameIsTrivial = candidate.contentType.contentAfterBasenameIsTrivial
      let leadingCaseMatchableCount =
        contentAfterBasenameIsTrivial ? tokenization.baseNameLength : candidateMixedcaseBytes.count
      var score = 0.0
      var falseStarts = 0
      var uppercaseMatches = 0
      var uppercaseMismatches = 0
      var anyCaseMatches = 0
      var isPrefixUppercaseMatch = false
      do {
        var pidx = 0
        for matchedRange in matchedRanges {
          for cidx in matchedRange {
            let candidateCharacter = candidateMixedcaseBytes[cidx]
            if cidx < leadingCaseMatchableCount {
              if candidateCharacter == patternMixedcaseBytes[pidx] {
                /// Check for case match.
                uppercaseMatches += candidateCharacter.isUppercase ? 1 : 0
                isPrefixUppercaseMatch =
                  isPrefixUppercaseMatch || (candidateCharacter.isUppercase && (cidx == 0))
                anyCaseMatches += 1
              } else {
                uppercaseMismatches += 1
              }
            }
            pidx += 1
          }
        }
      }

      var badShortMatches = 0
      var incompletelyMatchedTokens = 0
      var allRunsStartOnWordStartOrUppercaseLetter = true

      for range in matchedRanges {
        var position = range.lowerBound
        var remainingCharacters = range.length
        var matchedTokenPrefix = false
        repeat {
          let tokenIndex = tokenization.byteTokenAddresses[position].tokenIndex
          let tokenLength = tokenization.tokens[tokenIndex].length
          let positionInToken = tokenization.byteTokenAddresses[position].indexInToken
          let tokenCharactersRemaining = (tokenLength - positionInToken)
          let coveredCharacters =
            (remainingCharacters > tokenCharactersRemaining)
            ? tokenCharactersRemaining : remainingCharacters
          let coveredWholeToken = (coveredCharacters == tokenLength)
          incompletelyMatchedTokens += coveredWholeToken ? 0 : 1
          let laterMatchesExist = (coveredCharacters < patternCharactersRemaining)

          let incompleteMatch = (!coveredWholeToken && laterMatchesExist)
          if incompleteMatch || (positionInToken != 0) {
            falseStarts += 1
          }

          if incompleteMatch && (coveredCharacters <= 2) {
            badShortMatches += 1
          }
          if positionInToken == 0 {
            matchedTokenPrefix = true
          } else if !candidateMixedcaseBytes[position].isUppercase {
            allRunsStartOnWordStartOrUppercaseLetter = false
          }

          patternCharactersRemaining -= coveredCharacters
          remainingCharacters -= coveredCharacters
          position += coveredCharacters
        } while (remainingCharacters > 0)
        if (range.length > 1) || matchedTokenPrefix {
          score += pow(Double(range.length), 1.5)
        }
      }
      // This is for cases like an autogenerated member-wise initializer of a huge struct matching everything.
      // If they only matched within the arguments, and it's a huge symbol, it's a false start.
      if (firstMatchedRange.lowerBound > tokenization.baseNameLength) && (candidateMixedcaseBytes.count > 256) {
        falseStarts += 1
        score *= 0.75
      }

      if (matchStyle == .acronym) {
        badShortMatches = 0
        falseStarts = 0
      }

      if matchedRanges.only?.length == candidateMixedcaseBytes.count {
        score *= candidate.contentType.fullMatchBonus
      } else if matchedRanges.only == 0..<tokenization.baseNameLength {
        score *= candidate.contentType.fullBaseNameMatchBonus
      }
      // + 1 keeps this from going inf via / 0.
      score += ratio(anyCaseMatches, leadingCaseMatchableCount + 1)
      score += Double(uppercaseMatches) * 5
      if patternHasMixedcase {
        // If they're just typing `nswin…` because code completion will fix the casing, don't penalize them.
        score += Double(uppercaseMismatches) * -1.5
      }
      score -= Double(badShortMatches) * 3

      let inverseLength = ratio(1, candidateMixedcaseBytes.count + 1)
      // A shorter candidate is better, but only minimally
      score += inverseLength * inverseLength * inverseLength * inverseLength
      // Less tokens is better, less tokens is more important than less letters
      score += 1.5 * ratio(1, tokenization.tokenCount + 1)

      let allOneRun = matchedRanges.count == 1
      let startedAtBeginning = matchedRanges[0].lowerBound == 0
      let allCasesMatch = (anyCaseMatches == patternMixedcaseBytes.count)
      if allOneRun {
        score += 2
      }
      if startedAtBeginning {
        score += 2
      }
      if startedAtBeginning && allOneRun {
        score *= prefixMatchBonusValue
        if isPrefixUppercaseMatch && allCasesMatch && candidate.looksLikeAType
          && candidate.contentType.isEligibleForTypeNameOverLocalVariableModifier
        {
          score *= localVariableToGlobalTypeScoreRatio
        }
      }
      if precision == .thorough {
        // Only apply these penalties when thoroughly matching - enumerating further matchings could score much better,
        // and this could get the result culled in the first round.
        if !allRunsStartOnWordStartOrUppercaseLetter {
          score /= 2
        }
        if (incompletelyMatchedTokens > 1) && (matchStyle != .acronym) {
          score /= 2
        }
      }
      return TextScore(value: score, falseStarts: falseStarts)
    } else {
      return .noMatchScore
    }
  }

  private static func allocateSuccessiveRejectionFilters(
    lowercaseBytes: UTF8Bytes,
    allocator: inout UnsafeStackAllocator
  ) -> UnsafeStackArray<RejectionFilter> {
    var filters = allocator.allocateUnsafeArray(of: RejectionFilter.self, maximumCapacity: lowercaseBytes.count)
    filters.initializeWithContainedGarbage()
    var idx = lowercaseBytes.count - 1
    var accumulated = RejectionFilter.empty
    while idx >= 0 {
      accumulated.formUnion(lowercaseByte: lowercaseBytes[idx])
      filters[idx] = accumulated
      idx -= 1
    }
    return filters
  }
}

extension Pattern {
  package struct ByteTokenAddress {
    package var tokenIndex = 0
    package var indexInToken = 0
  }

  /// A token is a single conceptual name piece of an identifier, usually separated by camel case or underscores.
  ///
  /// For example `doFancyStuff` is divided into 3 tokens: `do`, `Fancy`, and `Stuff`.
  package struct Token {
    var storage: UInt
    init(length: Int, allUppercase: Bool) {
      let bit: UInt = (allUppercase ? 1 : 0) << (Int.bitWidth - 1)
      storage = UInt(bitPattern: length) | bit
    }

    package var length: Int {
      Int(bitPattern: UInt(storage & ~(1 << (Int.bitWidth - 1))))
    }

    package var allUppercase: Bool {
      (storage & (1 << (Int.bitWidth - 1))) != 0
    }
  }

  package struct Tokenization {
    package private(set) var baseNameLength: Int
    package private(set) var hasNonUppercaseNonDelimiterBytes: Bool
    package private(set) var tokens: UnsafeStackArray<Token>
    package private(set) var byteTokenAddresses: UnsafeStackArray<ByteTokenAddress>

    var tokenCount: Int {
      tokens.count
    }

    var byteCount: Int {
      byteTokenAddresses.count
    }

    private enum CharacterClass: Equatable {
      case uppercase
      case delimiter
      case other
    }

    // `nonisolated(unsafe)` is fine because the underlying buffer is never mutated or deallocated.
    private nonisolated(unsafe) static let characterClasses: UnsafePointer<CharacterClass> = {
      let array: [CharacterClass] = (0...255).map { (character: UInt8) in
        if character.isDelimiter {
          return .delimiter
        } else if character.isUppercase {
          return .uppercase
        } else {
          return .other
        }
      }
      return UnsafeBufferPointer.allocate(copyOf: array).baseAddress!
    }()

    // name -> [name]
    // myName -> [my][Name]
    // File.h -> [File][.][h]
    // NSOpenGLView -> [NS][Open][GL][View]
    // NSURL -> [NSURL]
    private init(mixedcaseBytes: UTF8Bytes, contentType: ContentType, allocator: inout UnsafeStackAllocator) {
      let byteCount = mixedcaseBytes.count
      let maxTokenCount = byteCount
      let baseNameMatchesLast = (contentType.baseNameAffinity == .last)
      let baseNameSeparator = contentType.baseNameSeparator
      byteTokenAddresses = allocator.allocateUnsafeArray(of: ByteTokenAddress.self, maximumCapacity: byteCount)
      tokens = allocator.allocateUnsafeArray(of: Token.self, maximumCapacity: maxTokenCount)
      baseNameLength = -1
      var baseNameLength: Int? = nil
      if byteCount > 1 {
        let mixedcaseBytes = mixedcaseBytes.baseAddress!
        let characterClasses = Self.characterClasses
        let endMixedCaseBytes = mixedcaseBytes + byteCount
        func characterClass(at pointer: UnsafePointer<UTF8Byte>) -> CharacterClass {
          if pointer != endMixedCaseBytes {
            return characterClasses[Int(pointer.pointee)]
          } else {
            return .delimiter
          }
        }
        var previous = characterClass(at: mixedcaseBytes)
        var current = characterClass(at: mixedcaseBytes + 1)
        var token = (index: 0, length: 1, isAllUppercase: (previous == .uppercase))
        hasNonUppercaseNonDelimiterBytes = (previous == .other)
        tokens.initializeWithContainedGarbage()
        byteTokenAddresses.initializeWithContainedGarbage()
        var nextByteTokenAddress = byteTokenAddresses.base
        nextByteTokenAddress.pointee = .init(tokenIndex: 0, indexInToken: 0)
        var nextBytePointer = mixedcaseBytes + 1
        while nextBytePointer != endMixedCaseBytes {
          nextBytePointer += 1
          let next = characterClass(at: nextBytePointer)
          let currentIsUppercase = (current == .uppercase)
          let tokenizeBeforeCurrentCharacter =
            (currentIsUppercase && ((previous == .other) || (next == .other)))
            || (current == .delimiter)
            || (previous == .delimiter)

          if tokenizeBeforeCurrentCharacter {
            let anyOtherCase = !(token.isAllUppercase || (previous == .delimiter))
            hasNonUppercaseNonDelimiterBytes = hasNonUppercaseNonDelimiterBytes || anyOtherCase
            tokens[token.index] = .init(length: token.length, allUppercase: token.isAllUppercase)
            token.isAllUppercase = true
            token.length = 0
            token.index += 1
            let lookBack = nextBytePointer - 2
            if lookBack.pointee == baseNameSeparator {
              if baseNameLength == nil || baseNameMatchesLast {
                baseNameLength = mixedcaseBytes.distance(to: lookBack)
              }
            }
          }
          token.isAllUppercase = token.isAllUppercase && currentIsUppercase
          nextByteTokenAddress += 1
          nextByteTokenAddress.pointee.tokenIndex = token.index
          nextByteTokenAddress.pointee.indexInToken = token.length
          token.length += 1
          previous = current
          current = next
        }
        let anyOtherCase = !(token.isAllUppercase || (previous == .delimiter))
        hasNonUppercaseNonDelimiterBytes = hasNonUppercaseNonDelimiterBytes || anyOtherCase
        tokens[token.index] = .init(length: token.length, allUppercase: token.isAllUppercase)
        tokens.truncateLeavingGarbage(to: token.index + 1)
      } else if byteCount == 1 {
        let characterClass = Self.characterClasses[Int(mixedcaseBytes[0])]
        tokens.append(.init(length: 1, allUppercase: characterClass == .uppercase))
        byteTokenAddresses.append(.init(tokenIndex: 0, indexInToken: 0))
        hasNonUppercaseNonDelimiterBytes = (characterClass == .other)
      } else {
        hasNonUppercaseNonDelimiterBytes = false
      }
      self.baseNameLength = baseNameLength ?? byteCount
    }

    func enumerate(body: (Range<Int>) -> Void) {
      var position = 0
      for token in tokens {
        body(position ..+ token.length)
        position += token.length
      }
    }

    func anySatisfy(predicate: (Range<Int>) -> Bool) -> Bool {
      var position = 0
      for token in tokens {
        if predicate(position ..+ token.length) {
          return true
        }
        position += token.length
      }
      return false
    }

    package mutating func deallocate(allocator: inout UnsafeStackAllocator) {
      allocator.deallocate(&tokens)
      allocator.deallocate(&byteTokenAddresses)
    }

    package static func allocate(
      mixedcaseBytes: UTF8Bytes,
      contentType: ContentType,
      allocator: inout UnsafeStackAllocator
    )
      -> Tokenization
    {
      Tokenization(mixedcaseBytes: mixedcaseBytes, contentType: contentType, allocator: &allocator)
    }

    var firstNonBaseNameTokenIndex: Int {
      (byteCount == baseNameLength) ? tokenCount : byteTokenAddresses[baseNameLength].tokenIndex
    }
  }
}

extension Pattern.UTF8Bytes {
  fileprivate func allocateLowercaseBytes(allocator: inout UnsafeStackAllocator) -> Self {
    let lowercaseBytes = allocator.allocateBuffer(of: UTF8Byte.self, count: count)
    for index in indices {
      lowercaseBytes[index] = self[index].lowercasedUTF8Byte
    }
    return UnsafeBufferPointer(lowercaseBytes)
  }
}

extension Pattern {
  fileprivate struct IndexedCandidate {
    var mixedcaseBytes: UTF8Bytes
    var lowercaseBytes: UTF8Bytes
    var contentType: ContentType
    var tokenization: Tokenization
    var matchedRanges: UnsafeStackArray<UTF8ByteRange>
    var firstMatchingLowercaseByteIndex: Int?

    static func allocate(
      referencing mixedcaseBytes: UTF8Bytes,
      patternByteCount: Int,
      firstMatchingLowercaseByteIndex: Int?,
      contentType: ContentType,
      allocator: inout UnsafeStackAllocator
    ) -> Self {
      let lowercaseBytes = mixedcaseBytes.allocateLowercaseBytes(allocator: &allocator)
      let tokenization = Tokenization.allocate(
        mixedcaseBytes: mixedcaseBytes,
        contentType: contentType,
        allocator: &allocator
      )
      let matchedRanges = allocator.allocateUnsafeArray(of: UTF8ByteRange.self, maximumCapacity: patternByteCount)
      return Self(
        mixedcaseBytes: mixedcaseBytes,
        lowercaseBytes: lowercaseBytes,
        contentType: contentType,
        tokenization: tokenization,
        matchedRanges: matchedRanges,
        firstMatchingLowercaseByteIndex: firstMatchingLowercaseByteIndex
      )
    }

    mutating func deallocate(allocator: inout UnsafeStackAllocator) {
      allocator.deallocate(&matchedRanges)
      tokenization.deallocate(allocator: &allocator)
      allocator.deallocate(&lowercaseBytes)
    }

    /// Create a new stack array such that for every offset `i` in this pattern `result[i]` points to the start offset
    /// of the next token. If there are no more valid start locations `result[i]` points to one character after the end
    /// of the candidate.
    /// Valid start locations are the start of the next token that begins with a byte that's in the pattern.
    ///
    /// Examples:
    /// -------------------------------------------------------------------------------------------------------
    /// Candidate                 | Pattern | Result
    /// -------------------------------------------------------------------------------------------------------
    /// "doSomeWork"              | "SWork" | `[2, 2, 6, 6, 6, 6, 10, 10, 10, 10]`
    /// "fn(one:two:three:four:)" | "tf"    | `[7,7,7,7,7,7,7,11,11,11,11,17,17,17,17,17,17,23,23,23,23,23,23]`
    ///
    fileprivate func allocateNextSearchStarts(
      allocator: inout UnsafeStackAllocator,
      patternRejectionFilter: RejectionFilter
    ) -> UnsafeStackArray<Int> {
      var nextSearchStarts = allocator.allocateUnsafeArray(of: Int.self, maximumCapacity: mixedcaseBytes.count)
      var nextStart = mixedcaseBytes.count
      let byteTokenAddresses = tokenization.byteTokenAddresses
      nextSearchStarts.initializeWithContainedGarbage()
      for cidx in mixedcaseBytes.indices.reversed() {
        nextSearchStarts[cidx] = nextStart
        let isTokenStart = byteTokenAddresses[cidx].indexInToken == 0
        if isTokenStart && patternRejectionFilter.contains(candidateByte: mixedcaseBytes[cidx]) == .maybe {
          nextStart = cidx
        }
      }
      return nextSearchStarts
    }

    var looksLikeAType: Bool {
      (tokenization.hasNonUppercaseNonDelimiterBytes && tokenization.baseNameLength == mixedcaseBytes.count)
    }
  }
}

// MARK: - Best Score Search -

extension Pattern {
  private struct Location {
    var pattern: Int
    var candidate: Int

    func nextByMatching() -> Self {
      Location(pattern: pattern + 1, candidate: candidate + 1)
    }

    func nextBySkipping(validStartingLocations: UnsafeStackArray<Int>) -> Self {
      Location(pattern: pattern, candidate: validStartingLocations[candidate])
    }

    static let start = Self(pattern: 0, candidate: 0)
  }

  private enum RestoredRange {
    case restore(UTF8ByteRange)
    case unwind
    case none

    func restore(ranges: inout UnsafeStackArray<UTF8ByteRange>) {
      switch self {
      case .restore(let lastRange):
        ranges[ranges.count - 1] = lastRange
      case .unwind:
        ranges.removeLast()
      case .none:
        break
      }
    }
  }

  private struct Step {
    var location: Location
    var restoredRange: RestoredRange
  }

  private struct Context {
    var pattern: UTF8Bytes
    var candidate: UTF8Bytes
    var location = Location.start

    var patternBytesRemaining: Int {
      pattern.count - location.pattern
    }

    var candidateBytesRemaining: Int {
      candidate.count - location.candidate
    }

    var enoughCandidateBytesRemain: Bool {
      patternBytesRemaining <= candidateBytesRemaining
    }

    var isCompleteMatch: Bool {
      return patternBytesRemaining == 0
    }

    var isCharacterMatch: Bool {
      pattern[location.pattern] == candidate[location.candidate]
    }
  }

  private struct Buffers {
    var steps: UnsafeStackArray<Step>
    var bestRangeSnapshot: UnsafeStackArray<UTF8ByteRange>
    var validMatchStartingLocations: UnsafeStackArray<Int>
    /// For each byte the candidate's text, a rejection filter that contains all the characters occurring after or
    /// at that offset.
    ///
    /// This way when we have already matched the first 4 bytes, we can check which characters occur from byte 5
    /// onwards and check that they appear in the candidate's remaining text.
    var candidateSuccessiveRejectionFilters: UnsafeStackArray<RejectionFilter>

    static func allocate(
      patternLowercaseBytes: UTF8Bytes,
      candidate: IndexedCandidate,
      patternRejectionFilter: RejectionFilter,
      allocator: inout UnsafeStackAllocator
    ) -> Self {
      let steps = allocator.allocateUnsafeArray(of: Step.self, maximumCapacity: patternLowercaseBytes.count + 1)
      let bestRangeSnapshot = allocator.allocateUnsafeArray(
        of: UTF8ByteRange.self,
        maximumCapacity: patternLowercaseBytes.count
      )
      let validMatchStartingLocations = candidate.allocateNextSearchStarts(
        allocator: &allocator,
        patternRejectionFilter: patternRejectionFilter
      )
      let candidateSuccessiveRejectionFilters = Pattern.allocateSuccessiveRejectionFilters(
        lowercaseBytes: candidate.lowercaseBytes,
        allocator: &allocator
      )
      return Buffers(
        steps: steps,
        bestRangeSnapshot: bestRangeSnapshot,
        validMatchStartingLocations: validMatchStartingLocations,
        candidateSuccessiveRejectionFilters: candidateSuccessiveRejectionFilters
      )
    }

    mutating func deallocate(allocator: inout UnsafeStackAllocator) {
      allocator.deallocate(&candidateSuccessiveRejectionFilters)
      allocator.deallocate(&validMatchStartingLocations)
      allocator.deallocate(&bestRangeSnapshot)
      allocator.deallocate(&steps)
    }
  }

  private struct ExecutionLimit {
    private(set) var remainingCycles: Int
    mutating func permitCycle() -> Bool {
      if remainingCycles == 0 {
        return false
      } else {
        remainingCycles -= 1
        return true
      }
    }
  }

  /// Exhaustively searches for ways to match the pattern to the candidate, scoring each one, and then returning the best score.
  /// If `captureMatchingRanges` is `true`, and a match is found, writes the matching ranges out to `matchedRangesStorage`.
  fileprivate func bestScore(
    candidate: inout IndexedCandidate,
    budget maxSteps: Int,
    captureMatchingRanges: Bool,
    allocator: inout UnsafeStackAllocator
  ) -> TextScore {
    var context = Context(pattern: patternLowercaseBytes, candidate: candidate.lowercaseBytes)
    var bestScore: TextScore? = nil
    // Find the best score by visiting all possible scorings.
    // So given the pattern "down" and candidate "documentDocument", enumerate these matches:
    // - [do]cumentDo[wn]load
    // - [d]ocumentD[own]load
    // - document[Down]load
    // Score each one, and choose the best.
    //
    // While recursion would be easier, use a manual stack because in practice we run out of stack space.
    //
    // Shortcuts:
    // * Stop if there are more character remaining to be matched than candidates to match.
    // * Keep a list of successive reject filters for the candidate and pattern, so that if the remaining pattern
    //   characters are known not to exist in the rest of the candidate, we can stop early.
    // * Each time we step forward after a failed match in a candidate, move up to the next token, not next character.
    // * Impose a budget of several thousand iterations so that we back off if things are going to hit the exponential worst case
    if patternMixedcaseBytes.hasContent && context.enoughCandidateBytesRemain {
      var buffers = Buffers.allocate(
        patternLowercaseBytes: patternLowercaseBytes,
        candidate: candidate,
        patternRejectionFilter: patternRejectionFilter,
        allocator: &allocator
      )
      defer { buffers.deallocate(allocator: &allocator) }
      var executionLimit = ExecutionLimit(remainingCycles: maxSteps)
      buffers.steps.push(Step(location: .start, restoredRange: .none))
      while executionLimit.permitCycle(), let step = buffers.steps.popLast() {
        context.location = step.location
        step.restoredRange.restore(ranges: &candidate.matchedRanges)

        if context.isCompleteMatch {
          let newScore = singleScore(candidate: candidate, precision: .thorough, matchStyle: nil)
          accumulate(
            score: newScore,
            into: &bestScore,
            matchedRanges: candidate.matchedRanges,
            captureMatchingRanges: captureMatchingRanges,
            matchedRangesStorage: &buffers.bestRangeSnapshot
          )
        } else if context.enoughCandidateBytesRemain {
          if RejectionFilter.match(
            pattern: patternSuccessiveRejectionFilters[context.location.pattern],
            candidate: buffers.candidateSuccessiveRejectionFilters[context.location.candidate]
          ) == .maybe {
            if context.isCharacterMatch {
              let extending = candidate.matchedRanges.last?.upperBound == context.location.candidate
              let restoredRange: RestoredRange
              if extending {
                let lastIndex = candidate.matchedRanges.count - 1
                restoredRange = .restore(candidate.matchedRanges[lastIndex])
                candidate.matchedRanges[lastIndex].extend(upperBoundBy: 1)
              } else {
                restoredRange = .unwind
                candidate.matchedRanges.append(context.location.candidate ..+ 1)
              }
              buffers.steps.push(
                Step(
                  location: context.location.nextBySkipping(
                    validStartingLocations: buffers.validMatchStartingLocations
                  ),
                  restoredRange: restoredRange
                )
              )
              buffers.steps.push(Step(location: context.location.nextByMatching(), restoredRange: .none))
            } else {
              buffers.steps.push(
                Step(
                  location: context.location.nextBySkipping(
                    validStartingLocations: buffers.validMatchStartingLocations
                  ),
                  restoredRange: .none
                )
              )
            }
          }
        }
      }

      // We need to consider the special cases the `.fast` search scans for so that a `.fast` score can't be better than
      // a .`thorough` score.
      // For example, they could match 30 character that weren't on a token boundary, which we would have skipped above.
      // Or we could have ran out of time searching and missed a contiguous match.
      for matchStyle in MatchStyle.allCases {
        candidate.matchedRanges.removeAll()
        if populateMatchingRanges(&candidate, matchStyle: matchStyle) {
          let newScore = singleScore(candidate: candidate, precision: .thorough, matchStyle: matchStyle)
          accumulate(
            score: newScore,
            into: &bestScore,
            matchedRanges: candidate.matchedRanges,
            captureMatchingRanges: captureMatchingRanges,
            matchedRangesStorage: &buffers.bestRangeSnapshot
          )
        }
      }
      candidate.matchedRanges.removeAll()
      candidate.matchedRanges.append(contentsOf: buffers.bestRangeSnapshot)
    }
    return bestScore ?? .noMatchScore
  }

  private func accumulate(
    score newScore: TextScore,
    into bestScore: inout TextScore?,
    matchedRanges: UnsafeStackArray<Pattern.UTF8ByteRange>,
    captureMatchingRanges: Bool,
    matchedRangesStorage bestMatchedRangesStorage: inout UnsafeStackArray<UTF8ByteRange>
  ) {
    if newScore > (bestScore ?? .worstPossibleScore) {
      bestScore = newScore
      if captureMatchingRanges {
        bestMatchedRangesStorage.removeAll()
        bestMatchedRangesStorage.append(contentsOf: matchedRanges)
      }
    }
  }
}

extension Pattern {
  package func test_searchStart(candidate: Candidate, contentType: ContentType) -> [Int] {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      var indexedCandidate = IndexedCandidate.allocate(
        referencing: candidate.bytes,
        patternByteCount: patternLowercaseBytes.count,
        firstMatchingLowercaseByteIndex: nil,
        contentType: contentType,
        allocator: &allocator
      )
      defer { indexedCandidate.deallocate(allocator: &allocator) }
      var nextSearchStarts = indexedCandidate.allocateNextSearchStarts(
        allocator: &allocator,
        patternRejectionFilter: patternRejectionFilter
      )
      defer { allocator.deallocate(&nextSearchStarts) }
      return Array(nextSearchStarts)
    }
  }

  package func testPerformance_tokenizing(batch: CandidateBatch, contentType: ContentType) -> Int {
    UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
      var all = 0
      batch.enumerate { candidate in
        var indexedCandidate = IndexedCandidate.allocate(
          referencing: candidate.bytes,
          patternByteCount: patternLowercaseBytes.count,
          firstMatchingLowercaseByteIndex: nil,
          contentType: contentType,
          allocator: &allocator
        )
        defer { indexedCandidate.deallocate(allocator: &allocator) }
        all &= indexedCandidate.tokenization.tokenCount
      }
      return all
    }
  }
}

extension Candidate.ContentType {
  fileprivate var prefixMatchBonus: Double {
    switch self {
    case .codeCompletionSymbol: return 2.00
    case .fileName, .projectSymbol: return 1.05
    case .unknown: return 2.00
    }
  }

  fileprivate var fullMatchBonus: Double {
    switch self {
    case .codeCompletionSymbol: return 1.00
    case .fileName, .projectSymbol: return 1.50
    case .unknown: return 1.00
    }
  }

  fileprivate var fullBaseNameMatchBonus: Double {
    switch self {
    case .codeCompletionSymbol: return 1.00
    case .fileName, .projectSymbol: return 1.50
    case .unknown: return 1.00
    }
  }

  fileprivate var baseNameAffinity: BaseNameAffinity {
    switch self {
    case .codeCompletionSymbol, .projectSymbol: return .first
    case .fileName: return .last
    case .unknown: return .last
    }
  }

  fileprivate var baseNameSeparator: UTF8Byte {
    switch self {
    case .codeCompletionSymbol, .projectSymbol: return .cLeftParentheses
    case .fileName: return .cPeriod
    case .unknown: return 0
    }
  }

  fileprivate var isEligibleForAcronymMatch: Bool {
    switch self {
    case .codeCompletionSymbol, .fileName, .projectSymbol: return true
    case .unknown: return false
    }
  }

  fileprivate var acronymMatchAllowsMultiCharacterMatchesAfterBaseName: Bool {
    switch self {
    // You can't do a acronym match into function arguments
    case .codeCompletionSymbol, .projectSymbol, .unknown: return false
    case .fileName: return true
    }
  }

  fileprivate var acronymMatchMustBeInBaseName: Bool {
    switch self {
    // You can't do a acronym match into function arguments
    case .codeCompletionSymbol, .projectSymbol: return true
    case .fileName, .unknown: return false
    }
  }

  fileprivate var contentAfterBasenameIsTrivial: Bool {
    switch self {
    case .codeCompletionSymbol, .projectSymbol: return false
    case .fileName: return true
    case .unknown: return false
    }
  }

  fileprivate var isEligibleForTypeNameOverLocalVariableModifier: Bool {
    switch self {
    case .codeCompletionSymbol: return true
    case .fileName, .projectSymbol, .unknown: return false
    }
  }

  fileprivate enum BaseNameAffinity {
    case first
    case last
  }
}

extension Pattern {
  @available(*, deprecated, message: "Pass a contentType")
  package func score(
    candidate: UTF8Bytes,
    precision: Precision,
    captureMatchingRanges: Bool,
    ranges: inout [UTF8ByteRange]
  ) -> Double {
    score(
      candidate: candidate,
      contentType: .codeCompletionSymbol,
      precision: precision,
      captureMatchingRanges: captureMatchingRanges,
      ranges: &ranges
    )
  }

  @available(*, deprecated, message: "Pass a contentType")
  package func score(candidate: UTF8Bytes, precision: Precision) -> Double {
    score(candidate: candidate, contentType: .codeCompletionSymbol, precision: precision)
  }
}
