//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2924 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPLogging
import LanguageServerProtocol
import SourceKitD

/// A ranged token in the document used for syntax highlighting.
public struct SyntaxHighlightingTokens {
    public var members: [SyntaxHighlightingToken]

    public init(members: [SyntaxHighlightingToken]) {
        self.members = members
    }

    /// The LSP representation of syntax highlighting tokens. Note that this
    /// requires the tokens in this array to be sorted.
    public var lspEncoded: [UInt32] {
        var previous = Position(line: 0, utf16index: 0)
        var rawTokens: [UInt32] = []
        rawTokens.reserveCapacity(count * 5)

        for token in self.members {
        let lineDelta = token.start.line - previous.line
        let charDelta =
            token.start.utf16index - (
            // The character delta is relative to the previous token's start
            // only if the token is on the previous token's line.
            previous.line == token.start.line ? previous.utf16index : 0)

        // We assert that the tokens are actually sorted
        assert(lineDelta >= 0)
        assert(charDelta >= 0)

        previous = token.start
        rawTokens += [
            UInt32(lineDelta),
            UInt32(charDelta),
            UInt32(token.utf16length),
            token.kind.tokenType,
            token.modifiers.rawValue,
        ]
        }

        return rawTokens
    }

    /// Merges the tokens in this array into a new token array,
    /// preferring the given array's tokens if duplicate ranges are
    /// found.
    public func mergingTokens(with other: SyntaxHighlightingTokens) -> SyntaxHighlightingTokens {
        let otherRanges = Set(other.members.map(\.range))
        return SyntaxHighlightingTokens(members: members.filter { !otherRanges.contains($0.range) } + other.members)
    }

    /// Sorts the tokens in this array by their start position.
    public func sorted(_ areInIncreasingOrder: (SyntaxHighlightingToken, SyntaxHighlightingToken) -> Bool) -> SyntaxHighlightingTokens {
        SyntaxHighlightingTokens(members: members.sorted(by: areInIncreasingOrder))
    }
}
