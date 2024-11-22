//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(SwiftDocC)
import Foundation
import IndexStoreDB
import Markdown
import SemanticIndex
import SymbolKit

#if compiler(>=6)
package import LanguageServerProtocol
#else
import LanguageServerProtocol
#endif

extension DocumentationLanguageService {
  private var documentationManager: DocumentationManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentationManager
    }
  }

  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    guard let sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.workspaceNotOpen(req.textDocument.uri)
    }
    let doccBuildInfo = await workspace.doccBuildInformation(for: req.textDocument.uri)
    guard let fileContents = snapshot.text.data(using: .utf8) else {
      throw ResponseError.internalError("Failed to encode file contents")
    }

    var externalIDsToConvert: [String]? = nil
    var symbolGraphs: [Data] = []
    var markupFiles: [Data] = []
    var tutorialFiles: [Data] = []
    switch snapshot.language {
    case .tutorial:
      tutorialFiles.append(fileContents)
    case .markdown:
      markupFiles.append(fileContents)
      if case let .symbol(symbolName) = MarkdownTitleFinder.find(parsing: snapshot.text) {
        if let moduleName = doccBuildInfo.moduleName, symbolName == moduleName {
          // This is a page representing the module itself.
          // Create a dummy symbol graph and tell SwiftDocC to convert the module name.
          externalIDsToConvert = [moduleName]
          symbolGraphs.append(
            try JSONEncoder().encode(
              SymbolGraph(
                metadata: SymbolGraph.Metadata(
                  formatVersion: SymbolGraph.SemanticVersion(major: 0, minor: 5, patch: 0),
                  generator: "SourceKit-LSP"
                ),
                module: SymbolGraph.Module(name: moduleName, platform: SymbolGraph.Platform()),
                symbols: [],
                relationships: []
              )
            )
          )
        } else {
          // This is a symbol extension page. Find the symbol so that we can include it in the request.
          guard let index = workspace.index(checkedFor: .deletedFiles) else {
            throw ResponseError.requestFailed(doccDocumentationError: .indexNotAvailable)
          }
          guard let symbolLink = DocCSymbolLink(string: symbolName),
            let symbolOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofDocCSymbolLink: symbolLink)
          else {
            throw ResponseError.requestFailed(doccDocumentationError: .symbolNotFound(symbolName))
          }
          guard
            let symbolWorkspace = try await workspaceForDocument(uri: symbolOccurrence.location.documentUri),
            let languageService = try await languageService(
              for: symbolOccurrence.location.documentUri,
              .swift,
              in: symbolWorkspace
            ) as? SwiftLanguageService,
            let symbolSnapshot = try documentManager.latestSnapshotOrDisk(
              symbolOccurrence.location.documentUri,
              language: .swift
            )
          else {
            throw ResponseError.internalError(
              "Unable to find Swift language service for \(symbolOccurrence.location.documentUri)"
            )
          }
          let position = symbolSnapshot.position(of: symbolOccurrence.location)
          let cursorInfo = try await languageService.cursorInfo(
            symbolOccurrence.location.documentUri,
            position..<position,
            includeSymbolGraph: true,
            fallbackSettingsAfterTimeout: false
          )
          guard let symbolGraph = cursorInfo.symbolGraph, let rawSymbolGraph = symbolGraph.data(using: .utf8) else {
            throw ResponseError.internalError("Unable to retrieve symbol graph for \(symbolOccurrence.symbol.name)")
          }
          externalIDsToConvert = [symbolOccurrence.symbol.usr]
          symbolGraphs.append(rawSymbolGraph)
        }
      }
    default:
      throw ResponseError.requestFailed(doccDocumentationError: .noDocumentation)
    }
    return try await documentationManager.convertDocumentation(
      workspace: workspace,
      buildInformation: doccBuildInfo,
      externalIDsToConvert: externalIDsToConvert,
      symbolGraphs: symbolGraphs,
      markupFiles: markupFiles,
      tutorialFiles: tutorialFiles
    )
  }
}

struct MarkdownTitleFinder: MarkupVisitor {
  public typealias Result = Title?

  public enum Title {
    case plainText(String)
    case symbol(String)
  }

  public static func find(parsing text: String) -> Result {
    let document = Markdown.Document(parsing: text, options: [.parseSymbolLinks])
    var visitor = MarkdownTitleFinder()
    return visitor.visit(document)
  }

  public mutating func defaultVisit(_ markup: any Markup) -> Result {
    for child in markup.children {
      if let value = visit(child) {
        return value
      }
    }
    return nil
  }

  public mutating func visitHeading(_ heading: Heading) -> Result {
    guard heading.level == 1 else {
      return nil
    }
    if let symbolLink = heading.child(at: 0) as? SymbolLink {
      // Remove the surrounding backticks to find the symbol name
      let plainText = symbolLink.plainText
      let startIndex = plainText.index(plainText.startIndex, offsetBy: 2)
      let endIndex = plainText.index(plainText.endIndex, offsetBy: -2)
      return .symbol(String(plainText[startIndex..<endIndex]))
    }
    return .plainText(heading.plainText)
  }
}
#endif
