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
import SwiftSyntax
import SwiftIDEUtils
import SwiftParser

/// Syntax highlighting tokens for a particular document.
public struct DocumentTokens {
  /// Semantic tokens, e.g. variable references, type references, ...
  public var semantic: [SyntaxHighlightingToken] = []
}
