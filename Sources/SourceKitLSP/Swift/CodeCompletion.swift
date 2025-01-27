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

#if compiler(>=6)
import Foundation
package import LanguageServerProtocol
import SKLogging
import SourceKitD
import SwiftBasicFormat
#else
import Foundation
import LanguageServerProtocol
import SKLogging
import SourceKitD
import SwiftBasicFormat
#endif

extension SwiftLanguageService {
  package func completion(_ req: CompletionRequest) async throws -> CompletionList {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)

    let completionPos = await adjustPositionToStartOfIdentifier(req.position, in: snapshot)
    let filterText = String(snapshot.text[snapshot.index(of: completionPos)..<snapshot.index(of: req.position)])

    let clientSupportsSnippets =
      capabilityRegistry.clientCapabilities.textDocument?.completion?.completionItem?.snippetSupport ?? false
    let buildSettings = await buildSettings(for: snapshot.uri, fallbackAfterTimeout: false)

    let inferredIndentationWidth = BasicFormat.inferIndentation(of: await syntaxTreeManager.syntaxTree(for: snapshot))

    return try await CodeCompletionSession.completionList(
      sourcekitd: sourcekitd,
      snapshot: snapshot,
      options: options,
      indentationWidth: inferredIndentationWidth,
      completionPosition: completionPos,
      cursorPosition: req.position,
      compileCommand: buildSettings,
      clientSupportsSnippets: clientSupportsSnippets,
      filterText: filterText
    )
  }
}
