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

import IndexStoreDB
import LanguageServerProtocol

fileprivate extension SymbolOccurrence {
  /// Assuming that this is a symbol occurrence returned by the index, return whether it can constitute the definition
  /// of a test case.
  ///
  /// The primary intention for this is to filter out references to test cases and extension declarations of test cases.
  /// The latter is important to filter so we don't include extension declarations for the derived `DiscoveredTests`
  /// files on non-Darwin platforms.
  var canBeTestDefinition: Bool {
    guard roles.contains(.definition) else {
      return false
    }
    guard symbol.kind == .class || symbol.kind == .instanceMethod else {
      return false
    }
    return true
  }
}

extension SourceKitLSPServer {
  func workspaceTests(_ req: WorkspaceTestsRequest) async throws -> [WorkspaceSymbolItem]? {
    let testSymbols = workspaces.flatMap { (workspace) -> [SymbolOccurrence] in
      return workspace.index?.unitTests() ?? []
    }
    return
      testSymbols
      .filter { $0.canBeTestDefinition }
      .sorted()
      .map(WorkspaceSymbolItem.init)
  }

  func documentTests(
    _ req: DocumentTestsRequest,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async throws -> [WorkspaceSymbolItem]? {
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)
    let mainFileUri = await workspace.buildSystemManager.mainFile(
      for: req.textDocument.uri,
      language: snapshot.language
    )
    let testSymbols = workspace.index?.unitTests(referencedByMainFiles: [mainFileUri.pseudoPath]) ?? []
    return
      testSymbols
      .filter { $0.canBeTestDefinition }
      .sorted()
      .map(WorkspaceSymbolItem.init)
  }
}
