//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKitD
import LanguageServerProtocol
import LSPLogging

/// A ranged token in the document used for syntax highlighting.
public struct SyntaxHighlightingToken: Hashable {
  /// The range of the token in the document. Must be on a single line.
  public var range: Range<Position> {
    didSet {
      assert(range.lowerBound.line == range.upperBound.line)
    }
  }
  /// The token type.
  public var kind: Kind
  /// Additional metadata about the token.
  public var modifiers: Modifiers

  /// The (inclusive) start position of the token.
  public var start: Position { range.lowerBound }
  /// The (exclusive) end position of the token.
  public var end: Position { range.upperBound }
  /// The length of the token in UTF-16 code units.
  public var utf16length: Int { end.utf16index - start.utf16index }

  public init(range: Range<Position>, kind: Kind, modifiers: Modifiers = []) {
    assert(range.lowerBound.line == range.upperBound.line)

    self.range = range
    self.kind = kind
    self.modifiers = modifiers
  }

  public init(start: Position, utf16length: Int, kind: Kind, modifiers: Modifiers = []) {
    let range = start..<Position(line: start.line, utf16index: start.utf16index + utf16length)
    self.init(range: range, kind: kind, modifiers: modifiers)
  }

  /// The token type.
  ///
  /// Represented using an int to make the conversion to
  /// LSP tokens efficient. The order of this enum does not have to be
  /// stable, since we provide a `SemanticTokensLegend` during initialization.
  /// It is, however, important that the values are numbered from 0 due to
  /// the way the kinds are encoded in LSP.
  /// Also note that we intentionally use an enum here instead of e.g. a
  /// `RawRepresentable` struct, since we want to have a conversion to
  /// strings for known kinds and since these kinds are only provided by the
  /// server, i.e. there is no need to handle cases where unknown kinds
  /// have to be decoded.
  public enum Kind: UInt32, CaseIterable, Hashable {
    case namespace = 0
    case type
    case `class`
    case `enum`
    case interface
    case `struct`
    case typeParameter
    case parameter
    case variable
    case property
    case enumMember
    case event
    case function
    case method
    case macro
    case keyword
    case modifier
    case comment
    case string
    case number
    case regexp
    case `operator`
    case decorator
    /// **(LSP Extension)**
    case identifier

    /// The name of the token type used by LSP.
    var lspName: String {
      switch self {
      case .namespace: return "namespace"
      case .type: return "type"
      case .class: return "class"
      case .enum: return "enum"
      case .interface: return "interface"
      case .struct: return "struct"
      case .typeParameter: return "typeParameter"
      case .parameter: return "parameter"
      case .variable: return "variable"
      case .property: return "property"
      case .enumMember: return "enumMember"
      case .event: return "event"
      case .function: return "function"
      case .method: return "method"
      case .macro: return "macro"
      case .keyword: return "keyword"
      case .modifier: return "modifier"
      case .comment: return "comment"
      case .string: return "string"
      case .number: return "number"
      case .regexp: return "regexp"
      case .operator: return "operator"
      case .decorator: return "decorator"
      case .identifier: return "identifier"
      }
    }

    /// **Public for testing**
    public var _lspName: String {
      lspName
    }
  }

  /// Additional metadata about a token.
  ///
  /// Similar to `Kind`, the raw values do not actually have
  /// to be stable, do note however that the bit indices should
  /// be numbered starting at 0 and that the ordering should
  /// correspond to `allModifiers`.
  public struct Modifiers: OptionSet, Hashable {
    public static let declaration = Self(rawValue: 1 << 0)
    public static let definition = Self(rawValue: 1 << 1)
    public static let readonly = Self(rawValue: 1 << 2)
    public static let `static` = Self(rawValue: 1 << 3)
    public static let deprecated = Self(rawValue: 1 << 4)
    public static let abstract = Self(rawValue: 1 << 5)
    public static let async = Self(rawValue: 1 << 6)
    public static let modification = Self(rawValue: 1 << 7)
    public static let documentation = Self(rawValue: 1 << 8)
    public static let defaultLibrary = Self(rawValue: 1 << 9)

    /// All available modifiers, in ascending order of the bit index
    /// they are represented with (starting at the rightmost bit).
    public static let allModifiers: [Self] = [
      .declaration,
      .definition,
      .readonly,
      .static,
      .deprecated,
      .abstract,
      .async,
      .modification,
      .documentation,
      .defaultLibrary,
    ]

    public let rawValue: UInt32

    /// The name of the modifier used by LSP, if this
    /// is a single modifier. Note that every modifier
    /// in `allModifiers` must have an associated `lspName`.
    var lspName: String? {
      switch self {
      case .declaration: return "declaration"
      case .definition: return "definition"
      case .readonly: return "readonly"
      case .static: return "static"
      case .deprecated: return "deprecated"
      case .abstract: return "abstract"
      case .async: return "async"
      case .modification: return "modification"
      case .documentation: return "documentation"
      case .defaultLibrary: return "defaultLibrary"
      default: return nil
      }
    }

    /// **Public for testing**
    public var _lspName: String? {
      lspName
    }

    public init(rawValue: UInt32) {
      self.rawValue = rawValue
    }
  }
}

extension Array where Element == SyntaxHighlightingToken {
  /// The LSP representation of syntax highlighting tokens. Note that this
  /// requires the tokens in this array to be sorted.
  public var lspEncoded: [UInt32] {
    var previous = Position(line: 0, utf16index: 0)
    var rawTokens: [UInt32] = []
    rawTokens.reserveCapacity(count * 5)

    for token in self {
      let lineDelta = token.start.line - previous.line
      let charDelta = token.start.utf16index - (
        // The character delta is relative to the previous token's start
        // only if the token is on the previous token's line.
        previous.line == token.start.line ? previous.utf16index : 0
      )

      // We assert that the tokens are actually sorted
      assert(lineDelta >= 0)
      assert(charDelta >= 0)

      previous = token.start
      rawTokens += [
        UInt32(lineDelta),
        UInt32(charDelta),
        UInt32(token.utf16length),
        token.kind.rawValue,
        token.modifiers.rawValue
      ]
    }

    return rawTokens
  }

  /// Merges the tokens in this array into a new token array,
  /// preferring the given array's tokens if duplicate ranges are
  /// found.
  public func mergingTokens(with other: [SyntaxHighlightingToken]) -> [SyntaxHighlightingToken] {
    let otherRanges = Set(other.map(\.range))
    return filter { !otherRanges.contains($0.range) } + other
  }
}
