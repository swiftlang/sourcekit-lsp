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

private typealias UTF8Bytes = Pattern.UTF8Bytes

package struct InfluencingIdentifiers: Sendable {
  // `nonisolated(unsafe)` is fine because the underlying buffer is not modified until `deallocate` is called and the
  // struct must not be used anymore after `deallocate` was called.
  private nonisolated(unsafe) let identifiers: UnsafeBufferPointer<Identifier>

  private init(identifiers: UnsafeBufferPointer<Identifier>) {
    self.identifiers = identifiers
  }

  private static func allocate(copyingTokenizedIdentifiers possiblyEmptyTokenizedIdentifiers: [[String]]) -> Self {
    let tokenizedIdentifiers = possiblyEmptyTokenizedIdentifiers.filter { possiblyEmptyTokenizedIdentifier in
      possiblyEmptyTokenizedIdentifier.count > 0
    }
    let allocatedIdentifiers: [Identifier] = tokenizedIdentifiers.enumerated().map {
      identifierIndex,
      tokenizedIdentifier in
      // First is 1, last is 0.9375, scale is linear. Only a small preference for the first word. Right now when
      // we have two words, it's for cases like an argument label and internal name predicting the argument type
      // or a variable name and its type predicting it's value. This scoring shows a slight affinity for the name.
      let scoreScale =
        (identifierIndex == 0)
        ? 1 : 1 - (0.0625 * (Double(identifierIndex) / Double(tokenizedIdentifiers.count - 1)))
      return Identifier.allocate(copyingTokenizedIdentifier: tokenizedIdentifier, scoreScale: scoreScale)
    }
    return InfluencingIdentifiers(identifiers: UnsafeBufferPointer.allocate(copyOf: allocatedIdentifiers))
  }

  private func deallocate() {
    for identifier in identifiers {
      identifier.deallocate()
    }
    identifiers.deallocate()
  }

  /// Invoke `body` with an instance of `InfluencingIdentifiers` that refers to memory only valid during the scope of `body`.
  /// This pattern is used so that this code has no referencing counting overhead. Using types like Array to represent the
  /// tokens during scoring results in referencing counting costing ~30% of the work. To avoid that, we use unsafe
  /// buffer pointers, and then this method to constrain lifetimes.
  /// - Parameter identifiers: The influencing identifiers in most to least influencing order.
  package static func withUnsafeInfluencingTokenizedIdentifiers<R>(
    _ tokenizedIdentifiers: [[String]],
    body: (Self) throws -> R
  ) rethrows -> R {
    let allocatedIdentifiers = allocate(copyingTokenizedIdentifiers: tokenizedIdentifiers)
    defer { allocatedIdentifiers.deallocate() }
    return try body(allocatedIdentifiers)
  }

  var hasContent: Bool {
    identifiers.hasContent
  }

  private func match(token: Token, candidate: Candidate, candidateTokenization: Pattern.Tokenization) -> Bool {
    candidateTokenization.anySatisfy { candidateTokenRange in
      if token.bytes.count == candidateTokenRange.count {
        let candidateToken = UnsafeBufferPointer(rebasing: candidate.bytes[candidateTokenRange])
        let leadingByteMatches = token.bytes[0].lowercasedUTF8Byte == candidateToken[0].lowercasedUTF8Byte
        return leadingByteMatches && equateBytes(token.bytes.afterFirst(), candidateToken.afterFirst())
      }
      return false
    }
  }

  /// Returns a value between 0...1, where 0 indicates `Candidate` was not textually related to the identifiers, and 1.0
  /// indicates the candidate was strongly related to the identifiers.
  ///
  /// Currently, this is implemented by tokenizing the candidate and the identifiers, and then seeing if any of the tokens
  /// match. If each identifier has one or more tokens in the candidate, return 1.0. If no tokens from the identifiers appear
  /// in the candidate, return 0.0.
  package func score(candidate: Candidate, allocator: inout UnsafeStackAllocator) -> Double {
    var candidateTokenization: Pattern.Tokenization? = nil
    defer { candidateTokenization?.deallocate(allocator: &allocator) }
    var score = 0.0
    for identifier in identifiers {
      // TODO: We could turn this loop inside out to walk the candidate tokens first, and skip the ones that are shorter
      // than the shortest token, or keep bit for each length we have, and skip almost all of them.
      let matchedTokenCount = identifier.tokens.countOf { token in
        if RejectionFilter.match(pattern: token.rejectionFilter, candidate: candidate.rejectionFilter) == .maybe {
          let candidateTokenization = candidateTokenization.lazyInitialize {
            Pattern.Tokenization.allocate(
              mixedcaseBytes: candidate.bytes,
              contentType: candidate.contentType,
              allocator: &allocator
            )
          }
          return match(token: token, candidate: candidate, candidateTokenization: candidateTokenization)
        }
        return false
      }
      score = max(score, identifier.score(matchedTokenCount: matchedTokenCount))
    }
    return score
  }
}

fileprivate extension InfluencingIdentifiers {
  struct Identifier {
    let tokens: UnsafeBufferPointer<Token>
    private let scoreScale: Double

    private init(tokens: UnsafeBufferPointer<Token>, scoreScale: Double) {
      self.tokens = tokens
      self.scoreScale = scoreScale
    }

    func deallocate() {
      for token in tokens {
        token.deallocate()
      }
      tokens.deallocate()
    }

    static func allocate(copyingTokenizedIdentifier tokenizedIdentifier: [String], scoreScale: Double) -> Self {
      return Identifier(
        tokens: UnsafeBufferPointer.allocate(copyOf: tokenizedIdentifier.map(Token.allocate)),
        scoreScale: scoreScale
      )
    }

    /// Returns a value between 0...1
    func score(matchedTokenCount: Int) -> Double {
      if matchedTokenCount == 0 {
        return 0
      } else if tokens.count == 1 {  // We matched them all, make it obvious we won't divide by 0.
        return 1 * scoreScale
      } else {
        let p = Double(matchedTokenCount - 1) / Double(tokens.count - 1)
        return (0.75 + (p * 0.25)) * scoreScale
      }
    }
  }
}

fileprivate extension InfluencingIdentifiers {
  struct Token {
    let bytes: UTF8Bytes
    let rejectionFilter: RejectionFilter
    private init(bytes: UTF8Bytes) {
      self.bytes = bytes
      self.rejectionFilter = RejectionFilter(bytes: bytes)
    }

    static func allocate(_ text: String) -> Self {
      Token(bytes: UnsafeBufferPointer.allocate(copyOf: text.utf8))
    }

    func deallocate() {
      bytes.deallocate()
    }
  }
}
