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

#if canImport(SwiftDocC)
import BuildSystemIntegration
import BuildServerProtocol
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import SemanticIndex
import SwiftDocC
import SwiftExtensions
import SwiftSyntax

package final actor DocumentationManager {
  private weak var sourceKitLSPServer: SourceKitLSPServer?

  private let doccServer: DocCServer

  init(sourceKitLSPServer: SourceKitLSPServer) {
    self.sourceKitLSPServer = sourceKitLSPServer
    self.doccServer = DocCServer(peer: nil, qualityOfService: .background)
  }

  func convertDocumentation(
    _ documentURI: DocumentURI,
    at position: Position = Position(line: 0, utf16index: 0)
  ) async throws -> ConvertDocumentationResponse {
    guard let sourceKitLSPServer = sourceKitLSPServer else {
      throw ResponseError.internalError("SourceKit-LSP is shutting down")
    }
    guard let workspace = await sourceKitLSPServer.workspaceForDocument(uri: documentURI) else {
      throw ResponseError.workspaceNotOpen(documentURI)
    }

    let snapshot = try sourceKitLSPServer.documentManager.latestSnapshot(documentURI)
    let targetId = await workspace.buildSystemManager.canonicalTarget(for: documentURI)
    var moduleName: String? = nil
    if let targetId = targetId {
      moduleName = await workspace.buildSystemManager.buildTarget(named: targetId)?.displayName
    }

    var externalIDsToConvert: [String]?
    var symbolGraphs = [Data]()
    var overridingDocumentationComments = [String: [String]]()
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
        let nearestDocumentableSymbol = DocumentableSymbolFinder.find(
          in: [Syntax(syntaxTree)],
          at: snapshot.absolutePosition(of: position)
        )
      else {
        return .error(.noDocumentation)
      }
      // Retrieve the symbol graph as well as information about the symbol
      let position = await swiftLanguageService.adjustPositionToStartOfIdentifier(
        snapshot.position(of: nearestDocumentableSymbol.position),
        in: snapshot
      )
      let (cursorInfo, _, symbolGraph) = try await swiftLanguageService.cursorInfo(
        documentURI,
        position..<position,
        includeSymbolGraph: true,
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
      overridingDocumentationComments[symbolUSR] = nearestDocumentableSymbol.documentationComments
    default:
      return .error(.noDocumentation)
    }
    // Send the convert request to SwiftDocC and wait for the response
    return try await withCheckedThrowingContinuation { continuation in
      doccServer.convert(
        externalIDsToConvert: externalIDsToConvert,
        documentPathsToConvert: nil,
        includeRenderReferenceStore: false,
        documentationBundleLocation: nil,
        documentationBundleDisplayName: moduleName ?? "Unknown",
        documentationBundleIdentifier: "unknown",
        symbolGraphs: symbolGraphs,
        overridingDocumentationComments: overridingDocumentationComments,
        emitSymbolSourceFileURIs: false,
        markupFiles: [],
        tutorialFiles: [],
        convertRequestIdentifier: UUID().uuidString
      ) { convertResponse in
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
  struct Symbol {
    let position: AbsolutePosition
    let documentationComments: [String]
  }

  private let cursorPosition: AbsolutePosition

  /// Accumulating the result in here.
  private var result: Symbol? = nil

  private init(_ cursorPosition: AbsolutePosition) {
    self.cursorPosition = cursorPosition
    super.init(viewMode: .sourceAccurate)
  }

  /// Designated entry point for `DocumentableSymbolFinder`.
  static func find(
    in nodes: some Sequence<Syntax>,
    at cursorPosition: AbsolutePosition
  ) -> Symbol? {
    let visitor = DocumentableSymbolFinder(cursorPosition)
    for node in nodes {
      visitor.walk(node)
    }
    return visitor.result
  }

  private func setResult(node: some SyntaxProtocol, position: AbsolutePosition) {
    setResult(
      result: Symbol(
        position: position,
        documentationComments: node.leadingTrivia.flatMap { trivia -> [String] in
          switch trivia {
          case .docLineComment(let comment):
            return [String(comment.dropFirst(3).trimmingCharacters(in: .whitespaces))]
          case .docBlockComment(let comment):
            return comment.dropFirst(3)
              .dropLast(2)
              .split(separator: "\n")
              .map { String($0).trimmingCharacters(in: .whitespaces) }
          default:
            return []
          }
        }
      )
    )
  }

  private func setResult(result symbol: Symbol) {
    if result == nil {
      result = symbol
    }
  }

  private func visitNamedDeclWithMemberBlock(
    node: some SyntaxProtocol,
    name: TokenSyntax,
    memberBlock: MemberBlockSyntax
  ) -> SyntaxVisitorContinueKind {
    if cursorPosition <= memberBlock.leftBrace.positionAfterSkippingLeadingTrivia {
      setResult(node: node, position: name.positionAfterSkippingLeadingTrivia)
    } else if let child = DocumentableSymbolFinder.find(
      in: memberBlock.children(viewMode: .sourceAccurate),
      at: cursorPosition
    ) {
      setResult(result: child)
    } else if node.range.contains(cursorPosition) {
      setResult(node: node, position: name.positionAfterSkippingLeadingTrivia)
    }
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    visitNamedDeclWithMemberBlock(node: node, name: node.name, memberBlock: node.memberBlock)
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let symbolPosition = node.name.positionAfterSkippingLeadingTrivia
    if node.range.contains(cursorPosition) || cursorPosition < symbolPosition {
      setResult(node: node, position: symbolPosition)
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
      setResult(node: node, position: symbolPosition)
    }
    return .skipChildren
  }

  override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
    let symbolPosition = node.name.positionAfterSkippingLeadingTrivia
    if node.range.contains(cursorPosition) || cursorPosition < symbolPosition {
      setResult(node: node, position: symbolPosition)
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
      setResult(node: node, position: symbolPosition)
    }
    return .skipChildren
  }
}
#endif
