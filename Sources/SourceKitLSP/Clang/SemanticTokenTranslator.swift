//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKLogging

/// `clangd` might use a different semantic token legend than SourceKit-LSP.
///
/// This type allows translation the semantic tokens from `clangd` into the token legend that is used by SourceKit-LSP.
struct SemanticTokensLegendTranslator {
  private enum Translation {
    /// The token type or modifier from clangd does not exist in SourceKit-LSP
    case doesNotExistInSourceKitLSP

    /// The token type or modifier exists in SourceKit-LSP but it uses a different index. We need to translate the
    /// clangd index to this SourceKit-LSP index.
    case translation(UInt32)
  }

  /// For all token types whose representation in clang differs from the representation in SourceKit-LSP, maps the
  /// index of that token type in clangd’s token type legend to the corresponding representation in SourceKit-LSP.
  private let tokenTypeTranslations: [UInt32: Translation]

  /// For all token modifiers whose representation in clang differs from the representation in SourceKit-LSP, maps the
  /// index of that token modifier in clangd’s token type legend to the corresponding representation in SourceKit-LSP.
  private let tokenModifierTranslations: [UInt32: Translation]

  /// A bitmask that has all bits set to 1 that are used for clangd token modifiers which have a different
  /// representation in SourceKit-LSP. If a token modifier does not have any bits set in common with this bitmask, no
  /// token mapping needs to be performed.
  private let tokenModifierTranslationBitmask: UInt32

  /// For token types in clangd that do not exist in SourceKit-LSP's token legend, we need to map their token types to
  /// some valid SourceKit-LSP token type. Use the token type with this index.
  private let tokenTypeFallbackIndex: UInt32

  init(clangdLegend: SemanticTokensLegend, sourceKitLSPLegend: SemanticTokensLegend) {
    var tokenTypeTranslations: [UInt32: Translation] = [:]
    for (index, tokenType) in clangdLegend.tokenTypes.enumerated() {
      switch sourceKitLSPLegend.tokenTypes.firstIndex(of: tokenType) {
      case index:
        break
      case nil:
        logger.error("Token type '\(tokenType, privacy: .public)' from clangd does not exist in SourceKit-LSP's legend")
        tokenTypeTranslations[UInt32(index)] = .doesNotExistInSourceKitLSP
      case let sourceKitLSPIndex?:
        logger.info(
          "Token type '\(tokenType, privacy: .public)' from clangd at index \(index) translated to \(sourceKitLSPIndex)"
        )
        tokenTypeTranslations[UInt32(index)] = .translation(UInt32(sourceKitLSPIndex))
      }
    }
    self.tokenTypeTranslations = tokenTypeTranslations

    var tokenModifierTranslations: [UInt32: Translation] = [:]
    for (index, tokenModifier) in clangdLegend.tokenModifiers.enumerated() {
      switch sourceKitLSPLegend.tokenModifiers.firstIndex(of: tokenModifier) {
      case index:
        break
      case nil:
        logger.error(
          "Token modifier '\(tokenModifier, privacy: .public)' from clangd does not exist in SourceKit-LSP's legend"
        )
        tokenModifierTranslations[UInt32(index)] = .doesNotExistInSourceKitLSP
      case let sourceKitLSPIndex?:
        logger.error(
          "Token modifier '\(tokenModifier, privacy: .public)' from clangd at index \(index) translated to \(sourceKitLSPIndex)"
        )
        tokenModifierTranslations[UInt32(index)] = .translation(UInt32(sourceKitLSPIndex))
      }
    }
    self.tokenModifierTranslations = tokenModifierTranslations

    var tokenModifierTranslationBitmask: UInt32 = 0
    for translatedIndex in tokenModifierTranslations.keys {
      tokenModifierTranslationBitmask.setBitToOne(at: Int(translatedIndex))
    }
    self.tokenModifierTranslationBitmask = tokenModifierTranslationBitmask

    self.tokenTypeFallbackIndex = UInt32(
      sourceKitLSPLegend.tokenTypes.firstIndex(of: SemanticTokenTypes.unknown.name) ?? 0
    )
  }

  func translate(_ data: [UInt32]) -> [UInt32] {
    var data = data
    // Translate token types, which are at offset n + 3.
    for i in stride(from: 3, to: data.count, by: 5) {
      switch tokenTypeTranslations[data[i]] {
      case .doesNotExistInSourceKitLSP: data[i] = tokenTypeFallbackIndex
      case .translation(let translatedIndex): data[i] = translatedIndex
      case nil: break
      }
    }

    // Translate token modifiers, which are at offset n + 4
    for i in stride(from: 4, to: data.count, by: 5) {
      guard data[i] & tokenModifierTranslationBitmask != 0 else {
        // Fast path: There is nothing to translate
        continue
      }
      var translatedModifiersBitmask: UInt32 = 0
      for (clangdModifier, sourceKitLSPModifier) in tokenModifierTranslations {
        guard data[i].hasBitSet(at: Int(clangdModifier)) else {
          continue
        }
        switch sourceKitLSPModifier {
        case .doesNotExistInSourceKitLSP: break
        case .translation(let sourceKitLSPIndex): translatedModifiersBitmask.setBitToOne(at: Int(sourceKitLSPIndex))
        }
      }
      data[i] = data[i] & ~tokenModifierTranslationBitmask | translatedModifiersBitmask
    }

    return data
  }
}

fileprivate extension UInt32 {
  mutating func hasBitSet(at index: Int) -> Bool {
    return self & (1 << index) != 0
  }

  mutating func setBitToOne(at index: Int) {
    self |= 1 << index
  }
}
