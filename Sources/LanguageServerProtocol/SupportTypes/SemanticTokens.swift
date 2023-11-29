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

/// The legend for a server's encoding of semantic tokens.
public struct SemanticTokensLegend: Codable, Hashable, LSPAnyCodable {
  /// The token types for a server.
  ///
  /// Token types are looked up by indexing into this array, e.g. a `tokenType`
  /// of `1` means `tokenTypes[1]`.
  public var tokenTypes: [String]

  /// The token modifies for a server.
  ///
  /// A token can have multiple modifiers, so a `tokenModifier` is viewed
  /// as a binary bit field and then indexed into this array, e.g. a
  /// `tokenModifier` of `3` is viewed as binary `0b00000011` which
  /// means `[tokenModifiers[0], tokenModifiers[1]]` because
  /// bits 0 and 1 are set.
  public var tokenModifiers: [String]

  public init(tokenTypes: [String], tokenModifiers: [String]) {
    self.tokenTypes = tokenTypes
    self.tokenModifiers = tokenModifiers
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    self.tokenTypes = []
    if let tokenTypesAny = dictionary["tokenTypes"],
      let tokenTypes = [String](fromLSPArray: tokenTypesAny)
    {
      self.tokenTypes = tokenTypes
    }

    self.tokenModifiers = []
    if let tokenModifiersAny = dictionary["tokenModifiers"],
      let tokenModifiers = [String](fromLSPArray: tokenModifiersAny)
    {
      self.tokenModifiers = tokenModifiers
    }
  }

  public func encodeToLSPAny() -> LSPAny {
    .dictionary([
      "tokenTypes": tokenTypes.encodeToLSPAny(),
      "tokenModifiers": tokenModifiers.encodeToLSPAny(),
    ])
  }
}

/// The encoding format for semantic tokens. Currently only `relative` is supported.
public struct TokenFormat: RawRepresentable, Codable, Hashable {
  public var rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let relative: TokenFormat = TokenFormat(rawValue: "relative")
}
