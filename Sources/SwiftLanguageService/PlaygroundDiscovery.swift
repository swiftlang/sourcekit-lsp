//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry

extension SwiftLanguageService {
  static func syntacticPlaygrounds(
    for snapshot: DocumentSnapshot,
    in workspace: Workspace,
    using syntaxTreeManager: SyntaxTreeManager,
    toolchain: Toolchain
  ) async -> [TextDocumentPlayground] {
    guard toolchain.swiftPlay != nil else {
      return []
    }
    return await SwiftPlaygroundsScanner.findDocumentPlaygrounds(
      for: snapshot,
      workspace: workspace,
      syntaxTreeManager: syntaxTreeManager
    )
  }
}
