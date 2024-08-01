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

import LanguageServerProtocol

extension SemanticTokenTypes {
  // LSP doesn’t know about actors. Display actors as classes.
  package static var actor: Self { Self.class }

  /// Token types are looked up by index
  package var tokenType: UInt32 {
    UInt32(Self.all.firstIndex(of: self)!)
  }
}

extension SemanticTokensLegend {
  /// The semantic tokens legend that is used between SourceKit-LSP and the editor.
  static let sourceKitLSPLegend = SemanticTokensLegend(
    tokenTypes: SemanticTokenTypes.all.map(\.name),
    tokenModifiers: SemanticTokenModifiers.all.compactMap(\.name)
  )
}
