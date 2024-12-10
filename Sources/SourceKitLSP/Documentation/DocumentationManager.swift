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

import BuildSystemIntegration
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import Markdown
import SemanticIndex
import SwiftDocC
import SwiftExtensions
import SwiftSyntax
import SymbolKit

package final actor DocumentationManager {
  private let server: DocCServer
  private let symbolResolutionService: DocCSymbolResolutionService
  private let catalogIndexManager: DocCCatalogIndexManager

  init() {
    let symbolResolutionServer = DocumentationServer(qualityOfService: .unspecified)
    server = DocCServer(
      peer: symbolResolutionServer,
      qualityOfService: .background
    )
    catalogIndexManager = DocCCatalogIndexManager(server: server)
    symbolResolutionService = DocCSymbolResolutionService()
    symbolResolutionServer.register(service: symbolResolutionService)
  }

  func filesDidChange(_ events: [FileEvent]) async {
    let affectedCatalogURLs = events.reduce(into: Set<URL>()) { affectedCatalogURLs, event in
      guard let catalogURL = event.uri.fileURL?.doccCatalogURL else {
        return
      }
      affectedCatalogURLs.insert(catalogURL)
    }
    await catalogIndexManager.invalidate(catalogURLs: affectedCatalogURLs)
  }

  func convertDocumentation(
    server sourceKitLSPServer: SourceKitLSPServer,
    request: ConvertDocumentationRequest
  ) async throws -> ConvertDocumentationResponse {
    let documentURI = request.textDocument.uri
    let position = request.position
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: documentURI) else {
      throw ResponseError.workspaceNotOpen(documentURI)
    }

    let snapshot = try sourceKitLSPServer.documentManager.latestSnapshot(documentURI)
    let targetId = await workspace.buildSystemManager.canonicalTarget(for: documentURI)
    var moduleName: String? = nil
    var catalogURL: URL? = nil
    if let targetId = targetId {
      moduleName = await workspace.buildSystemManager.buildTarget(named: targetId)?.displayName
      catalogURL = try? await workspace.buildSystemManager.sourceFiles(in: [targetId])
        .flatMap({ $0.sources })
        .compactMap { $0.uri.fileURL?.doccCatalogURL }
        .first
    }
    var catalogIndex: DocCCatalogIndex? = nil
    if let catalogURL = catalogURL {
      catalogIndex = try? await catalogIndexManager.index(for: catalogURL).get()
    }

    var externalIDsToConvert: [String]?
    var markupFiles = [Data]()
    var tutorialFiles = [Data]()
    var symbolGraphs = [Data]()
    switch snapshot.language {
    case .swift:
      guard let languageService = await sourceKitLSPServer.languageService(for: documentURI, .swift, in: workspace),
        let swiftLanguageService = languageService as? SwiftLanguageService
      else {
        throw ResponseError.internalError("Unable to find Swift language service for \(documentURI)")
      }
      // Search for the nearest documentable symbol at this location
      let syntaxTree = await swiftLanguageService.syntaxTreeManager.syntaxTree(for: snapshot)
      guard
        let absoluteSymbolPosition = DocumentableSymbolFinder.find(
          in: [Syntax(syntaxTree)],
          at: snapshot.absolutePosition(of: position)
        )
      else {
        return .error(.noDocumentation)
      }
      // Retrieve the symbol graph as well as information about the symbol
      let position = await swiftLanguageService.adjustPositionToStartOfIdentifier(
        snapshot.position(of: absoluteSymbolPosition),
        in: snapshot
      )
      let (cursorInfo, _, symbolGraph) = try await swiftLanguageService.cursorInfo(
        documentURI,
        position..<position,
        enableSymbolGraph: true,
        fallbackSettingsAfterTimeout: false
      )
      guard let symbolGraph = symbolGraph,
        let cursorInfo = cursorInfo.first,
        let symbolUSR = cursorInfo.symbolInfo.usr
      else {
        throw ResponseError.internalError("Unable to retrieve symbol graph for the document")
      }
      guard let rawSymbolGraph = symbolGraph.data(using: .utf8) else {
        throw ResponseError.internalError("Unable to encode symbol graph")
      }
      externalIDsToConvert = [symbolUSR]
      symbolGraphs.append(rawSymbolGraph)
      // Locate the documentation extension and include it in the request if one exists
      if let index = workspace.index(checkedFor: .deletedFiles),
        let symbolLink = try? symbolResolutionService.lookupSymbolLink(usr: symbolUSR, index: index).get(),
        let documentationExtensionURL = catalogIndex?.documentationExtension(for: symbolLink),
        let documentationExtensionSnapshot = sourceKitLSPServer.documentManager.latestSnapshotOrDisk(
          .init(documentationExtensionURL),
          language: .swift_docc_markdown
        ),
        let documentationExtensionContents = documentationExtensionSnapshot.text.data(using: .utf8)
      {
        markupFiles.append(documentationExtensionContents)
      }
    case .swift_docc_markdown:
      guard let fileContents = snapshot.text.data(using: .utf8) else {
        throw ResponseError.internalError("Failed to encode file contents")
      }
      markupFiles.append(fileContents)
      let markdownDocument = Markdown.Document(parsing: snapshot.text, options: [.parseSymbolLinks])
      if case let .symbol(symbolName) = MarkdownTitleFinder.find(markdownDocument) {
        if let moduleName = moduleName, symbolName == moduleName {
          // This is a page representing the module itself.
          // Create a dummy symbol graph and tell SwiftDocC to convert the module name.
          externalIDsToConvert = [moduleName]
          symbolGraphs.append(
            try JSONEncoder().encode(
              SymbolGraph(
                metadata: .init(formatVersion: .init(major: 0, minor: 5, patch: 0), generator: "SourceKit-LSP"),
                module: .init(name: moduleName, platform: .init()),
                symbols: [],
                relationships: []
              )
            )
          )
        } else {
          // This is a symbol extension page. Find the symbol so that we can include it in the request.
          guard let index = workspace.index(checkedFor: .deletedFiles) else {
            return .error(.indexNotAvailable)
          }
          let symbolComponents = symbolName.split(separator: "/").map { String($0) }
          guard let symbolLink = DocCSymbolLink(componentsIncludingModule: symbolComponents),
            case .success(let symbol) = symbolResolutionService.lookupSymbol(forLink: symbolLink, index: index)
          else {
            return .error(.symbolNotFound(symbolName))
          }
          guard let symbolWorkspace = await sourceKitLSPServer.workspaceForDocument(uri: symbol.location.documentUri),
            let languageService = await sourceKitLSPServer.languageService(
              for: symbol.location.documentUri,
              .swift,
              in: symbolWorkspace
            ) as? SwiftLanguageService,
            let symbolSnapshot = sourceKitLSPServer.documentManager.latestSnapshotOrDisk(
              symbol.location.documentUri,
              language: .swift
            )
          else {
            throw ResponseError.internalError(
              "Unable to find Swift language service for \(symbol.location.documentUri)"
            )
          }
          let position = symbolSnapshot.position(of: symbol.location)
          let cursorInfo = try await languageService.cursorInfo(
            symbol.location.documentUri,
            position..<position,
            enableSymbolGraph: true,
            fallbackSettingsAfterTimeout: false
          )
          guard let symbolGraph = cursorInfo.symbolGraph, let rawSymbolGraph = symbolGraph.data(using: .utf8) else {
            throw ResponseError.internalError("Unable to retrieve symbol graph for \(symbol.name)")
          }
          externalIDsToConvert = [symbol.usr]
          symbolGraphs.append(rawSymbolGraph)
        }
      }
    case .swift_docc_tutorial:
      guard let fileContents = snapshot.text.data(using: .utf8) else {
        throw ResponseError.internalError("Failed to encode file contents")
      }
      tutorialFiles.append(fileContents)
    default:
      return .error(.noDocumentation)
    }
    // Store the convert request identifier in order to fulfill index requests from SwiftDocC
    let convertRequestIdentifier = UUID().uuidString
    if let catalogURL = documentURI.fileURL?.doccCatalogURL {
      symbolResolutionService.add(
        context: .init(
          catalogURL: catalogURL,
          uncheckedIndex: workspace.uncheckedIndex,
          catalogIndex: try? await catalogIndexManager.index(for: catalogURL).get()
        ),
        withKey: convertRequestIdentifier
      )
    }
    // Send the convert request to SwiftDocC and wait for the response
    return try await withCheckedThrowingContinuation { continuation in
      server.convert(
        externalIDsToConvert: externalIDsToConvert,
        documentPathsToConvert: nil,
        includeRenderReferenceStore: false,
        documentationBundleLocation: nil,
        documentationBundleDisplayName: moduleName ?? "Unknown",
        documentationBundleIdentifier: "unknown",
        symbolGraphs: symbolGraphs,
        emitSymbolSourceFileURIs: false,
        markupFiles: markupFiles,
        tutorialFiles: tutorialFiles,
        convertRequestIdentifier: convertRequestIdentifier
      ) { convertResponse in
        self.symbolResolutionService.removeContext(forKey: convertRequestIdentifier)
        switch convertResponse {
        case .success(let convertResponse):
          guard let renderNodeData = convertResponse.renderNodes.first else {
            continuation.resume(throwing: ResponseError.internalError("SwiftDocC did not return any render nodes"))
            return
          }
          guard let renderNode = String(data: renderNodeData, encoding: .utf8) else {
            continuation.resume(throwing: ResponseError.internalError("Failed to encode render node from SwiftDocC"))
            return
          }
          continuation.resume(returning: .renderNode(renderNode))
        case .failure(let serverError):
          continuation.resume(throwing: serverError)
        }
      }
    }
  }
}

fileprivate final class DocumentableSymbolFinder: SyntaxAnyVisitor {
  private let cursorPosition: AbsolutePosition

  /// Accumulating the result in here.
  private var result: AbsolutePosition? = nil

  private init(_ cursorPosition: AbsolutePosition) {
    self.cursorPosition = cursorPosition
    super.init(viewMode: .sourceAccurate)
  }

  /// Designated entry point for `DocumentableSymbolFinder`.
  static func find(
    in nodes: some Sequence<Syntax>,
    at cursorPosition: AbsolutePosition
  ) -> AbsolutePosition? {
    let visitor = DocumentableSymbolFinder(cursorPosition)
    for node in nodes {
      visitor.walk(node)
    }
    return visitor.result
  }

  @discardableResult private func setResult(_ symbolPosition: AbsolutePosition) -> SyntaxVisitorContinueKind {
    if result == nil {
      result = symbolPosition
    }
    return .skipChildren
  }

  private func visitNamedDeclWithMemberBlock(
    node: some SyntaxProtocol,
    name: TokenSyntax,
    memberBlock: MemberBlockSyntax
  ) -> SyntaxVisitorContinueKind {
    if cursorPosition <= memberBlock.leftBrace.positionAfterSkippingLeadingTrivia {
      setResult(name.positionAfterSkippingLeadingTrivia)
    } else if let child = DocumentableSymbolFinder.find(
      in: memberBlock.children(viewMode: .sourceAccurate),
      at: cursorPosition
    ) {
      setResult(child)
    } else if node.range.contains(cursorPosition) {
      setResult(name.positionAfterSkippingLeadingTrivia)
    }
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    return visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let symbolPosition = node.name.positionAfterSkippingLeadingTrivia
    if node.range.contains(cursorPosition) || cursorPosition < symbolPosition {
      setResult(symbolPosition)
    }
    return .skipChildren
  }

  override func visit(_ node: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
    let range = node.leftBrace.endPositionBeforeTrailingTrivia..<node.rightBrace.positionAfterSkippingLeadingTrivia
    guard range.contains(cursorPosition) else {
      return .skipChildren
    }
    return .visitChildren
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    let symbolPosition = node.initKeyword.positionAfterSkippingLeadingTrivia
    if node.range.contains(cursorPosition) || cursorPosition < symbolPosition {
      setResult(symbolPosition)
    }
    return .skipChildren
  }

  override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
    let symbolPosition = node.name.positionAfterSkippingLeadingTrivia
    if node.range.contains(cursorPosition) || cursorPosition < symbolPosition {
      setResult(symbolPosition)
    }
    return .skipChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    // A variable declaration is only documentable if there is only one pattern binding
    guard node.bindings.count == 1,
      let identifier = node.bindings.first!.pattern.as(IdentifierPatternSyntax.self)
    else {
      return .skipChildren
    }
    let symbolPosition = identifier.positionAfterSkippingLeadingTrivia
    if node.range.contains(cursorPosition) || cursorPosition < symbolPosition {
      setResult(symbolPosition)
    }
    return .skipChildren
  }
}

fileprivate struct MarkdownTitleFinder: MarkupVisitor {
  public typealias Result = Title?

  public enum Title {
    case plainText(String)
    case symbol(String)
  }

  public static func find(_ markup: any Markup) -> Result {
    var visitor = MarkdownTitleFinder()
    return visitor.visit(markup)
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
