//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
package import SwiftSyntax
package import ToolchainRegistry
import SwiftDocC
import BuildServerIntegration

package actor DocumentationLanguageService: LanguageService, Sendable {
  /// The ``SourceKitLSPServer`` instance that created this `DocumentationLanguageService`.
  private(set) weak var sourceKitLSPServer: SourceKitLSPServer?

  let documentationManager: DocCDocumentationManager

  var documentManager: DocumentManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentManager
    }
  }

  package static var experimentalCapabilities: [String: LSPAny] {
    return [
      DoccDocumentationRequest.method: .dictionary(["version": .int(1)])
    ]
  }

  package init(
    sourceKitLSPServer: SourceKitLSPServer,
    toolchain: Toolchain,
    options: SourceKitLSPOptions,
    hooks: Hooks,
    workspace: Workspace
  ) async throws {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.documentationManager = DocCDocumentationManager(buildServerManager: workspace.buildServerManager)
  }

  package nonisolated func canHandle(workspace: Workspace, toolchain: Toolchain) -> Bool {
    return true
  }

  package func initialize(
    _ initialize: InitializeRequest
  ) async throws -> InitializeResult {
    return InitializeResult(
      capabilities: ServerCapabilities()
    )
  }

  package func shutdown() async {
    // Nothing to tear down
  }

  package func addStateChangeHandler(
    handler: @escaping @Sendable (LanguageServerState, LanguageServerState) -> Void
  ) async {
    // There is no underlying language server with which to report state
  }

  package func openDocument(
    _ notification: DidOpenTextDocumentNotification,
    snapshot: DocumentSnapshot
  ) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func closeDocument(_ notification: DidCloseTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func reopenDocument(_ notification: ReopenTextDocumentNotification) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func syntacticTestItems(for snapshot: DocumentSnapshot) async -> [AnnotatedTestItem] {
    return []
  }

  package func syntacticPlaygrounds(
    for snapshot: DocumentSnapshot,
    in workspace: Workspace
  ) async -> [TextDocumentPlayground] {
    return []
  }

  package func changeDocument(
    _ notification: DidChangeTextDocumentNotification,
    preEditSnapshot: DocumentSnapshot,
    postEditSnapshot: DocumentSnapshot,
    edits: [SwiftSyntax.SourceEdit]
  ) async {
    // The DocumentationLanguageService does not do anything with document events
  }

  package func hover(_ req: HoverRequest) async throws -> HoverResponse? {
    guard let sourceKitLSPServer else {
      throw ResponseError.requestNotImplemented(HoverRequest.self)
    }
    
    let uri = req.textDocument.uri
    let snapshot = try documentManager.latestSnapshot(uri)
    
    guard snapshot.language == .swift else {
      throw ResponseError.requestNotImplemented(HoverRequest.self)
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: req.textDocument.uri) else {
      throw ResponseError.requestNotImplemented(HoverRequest.self)
    }
    
    do {
      let (symbolGraph, symbolUSR, overrideDocComments) = try await sourceKitLSPServer.primaryLanguageService(
        for: snapshot.uri,
        snapshot.language,
        in: workspace
      ).symbolGraph(for: snapshot, at: req.position)
      
      var moduleName: String? = nil
      var catalogURL: URL? = nil
      if let target = await workspace.buildServerManager.canonicalTarget(for: req.textDocument.uri) {
        moduleName = await workspace.buildServerManager.moduleName(for: target)
        catalogURL = await workspace.buildServerManager.doccCatalog(for: target)
      }
      
      let doccResponse = try await documentationManager.renderDocCDocumentation(
        symbolUSR: symbolUSR,
        symbolGraph: symbolGraph,
        overrideDocComments: overrideDocComments,
        markupFile: nil,
        moduleName: moduleName,
        catalogURL: catalogURL
      )
      
      guard let renderNodeData = doccResponse.renderNode.data(using: .utf8) else {
        throw ResponseError.requestNotImplemented(HoverRequest.self)
      }
      let renderNode = try JSONDecoder().decode(RenderNode.self, from: renderNodeData)
      
      guard let markdown = renderNodeToMarkdown(renderNode) else {
        throw ResponseError.requestNotImplemented(HoverRequest.self)
      }
      return HoverResponse(contents: .markupContent(MarkupContent(kind: .markdown, value: markdown)), range: nil)
      
    } catch {
      throw ResponseError.requestNotImplemented(HoverRequest.self)
    }
  }
  
  private func renderNodeToMarkdown(_ renderNode: RenderNode) -> String? {
    var result = ""
    
    let sections = renderNode.primaryContentSections
    for section in sections {
      if let declSection = section as? DeclarationsRenderSection,
         let declaration = declSection.declarations.first {
        let sourceText = declaration.tokens.map { $0.text }.joined()
        result += "```swift\n\(sourceText)\n```\n"
      }
    }
    
    if let abstract = renderNode.abstract {
      let abstractMarkdown = abstract.map { renderInlineContentToMarkdown($0) }.joined()
      if !abstractMarkdown.isEmpty {
        result += "\(abstractMarkdown)\n\n"
      }
    }
    
    for section in sections {
      if let contentSection = section as? ContentRenderSection {
        for contentBlock in contentSection.content {
          result += renderBlockContentToMarkdown(contentBlock) + "\n"
        }
      } else if let parametersSection = section as? ParametersRenderSection {
        result += "## Parameters\n"
        for param in parametersSection.parameters {
          result += "- `\(param.name)`: "
          let paramContent = param.content.compactMap { renderBlockContentToMarkdown($0).trimmingCharacters(in: .whitespacesAndNewlines) }
          result += paramContent.joined(separator: " ") + "\n"
        }
        result += "\n"
      }
    }
    
    let finalResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return finalResult.isEmpty ? nil : finalResult
  }
  
  private func renderInlineContentToMarkdown(_ content: RenderInlineContent) -> String {
    switch content {
    case .text(let text): return text
    case .codeVoice(let code): return "`\(code)`"
    case .strong(let inline): return "**\(inline.map(renderInlineContentToMarkdown).joined())**"
    case .emphasis(let inline): return "*\(inline.map(renderInlineContentToMarkdown).joined())*"
    case .reference(_, _, let overridingTitle, let overridingTitleInlineContent):
      if let titleContent = overridingTitleInlineContent {
        return titleContent.map(renderInlineContentToMarkdown).joined()
      } else if let title = overridingTitle {
        return "`\(title)`"
      } else {
        return ""
      }
    default: return ""
    }
  }
  
  private func renderBlockContentToMarkdown(_ content: RenderBlockContent) -> String {
    switch content {
    case .paragraph(let p):
      return p.inlineContent.map(renderInlineContentToMarkdown).joined() + "\n"
    case .codeListing(_):
      return ""
    case .heading(let h):
      return "\(String(repeating: "#", count: h.level)) \(h.text)\n"
    default:
      return ""
    }
  }
}

