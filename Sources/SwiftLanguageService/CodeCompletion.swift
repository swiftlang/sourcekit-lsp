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

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftBasicFormat

extension SwiftLanguageService {
  package func completion(_ req: CompletionRequest) async throws -> CompletionList {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)

    let completionPos = await adjustPositionToStartOfIdentifier(req.position, in: snapshot)
    let filterText = String(snapshot.text[snapshot.index(of: completionPos)..<snapshot.index(of: req.position)])

    let compileCommand = await compileCommand(for: snapshot.uri, fallbackAfterTimeout: false)

    let inferredIndentationWidth = BasicFormat.inferIndentation(of: await syntaxTreeManager.syntaxTree(for: snapshot))

    return try await CodeCompletionSession.completionList(
      sourcekitd: sourcekitd,
      snapshot: snapshot,
      options: options,
      indentationWidth: inferredIndentationWidth,
      completionPosition: completionPos,
      cursorPosition: req.position,
      compileCommand: compileCommand,
      clientCapabilities: capabilityRegistry.clientCapabilities,
      filterText: filterText
    )
  }

  package func completionItemResolve(_ req: CompletionItemResolveRequest) async throws -> CompletionItem {
    return try await CodeCompletionSession.completionItemResolve(item: req.item, sourcekitd: sourcekitd)
  }
}
