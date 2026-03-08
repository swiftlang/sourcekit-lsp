//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SourceKitLSP

/// A code action provider that can defer expensive work to `codeAction/resolve`
protocol ResolvableCodeActionProvider {

  /// Stable identifier used to route resolve requests back to this provider.
  static var resolveIdentifier: String { get }

  static func resolve(
    _ codeAction: CodeAction,
    context: SyntaxCodeActionResolutionContext
  ) async throws -> CodeAction
}

struct SyntaxCodeActionResolutionContext: Sendable {
  let scope: SyntaxCodeActionScope
  let workspace: Workspace
  let documentManager: DocumentManager
  let languageService: any LanguageService
}

extension ResolvableCodeActionProvider {
  static func makeResolveData(
    scope: SyntaxCodeActionScope,
    _ fields: [String: LSPAny] = [:]
  ) -> LSPAny {
    var dict = fields
    dict["resolveIdentifier"] = .string(resolveIdentifier)
    dict["uri"] = .string(scope.request.textDocument.uri.stringValue)
    dict["range"] = scope.request.range.encodeToLSPAny()
    return .dictionary(dict)
  }
}
