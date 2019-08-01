//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKCore
import SKSupport
import IndexStoreDB
import Basic
import SPMUtility
import Dispatch
import Foundation
import SPMLibc

public typealias URL = Foundation.URL

/// The SourceKit language server.
///
/// This is the client-facing language server implementation, providing indexing, multiple-toolchain
/// and cross-language support. Requests may be dispatched to language-specific services or handled
/// centrally, but this is transparent to the client.
public final class SourceKitServer: LanguageServer {

  struct LanguageServiceKey: Hashable {
    var toolchain: String
    var language: Language
  }

  let buildSetup: BuildSetup

  let toolchainRegistry: ToolchainRegistry

  var languageService: [LanguageServiceKey: Connection] = [:]

  public var workspace: Workspace?

  let fs: FileSystem

  let onExit: () -> Void

  /// Creates a language server for the given client.
  public init(client: Connection, fileSystem: FileSystem = localFileSystem, buildSetup: BuildSetup, onExit: @escaping () -> Void = {}) {

    self.fs = fileSystem
    self.toolchainRegistry = ToolchainRegistry.shared
    self.buildSetup = buildSetup
    self.onExit = onExit

    super.init(client: client)
  }

  public override func _registerBuiltinHandlers() {
    _register(SourceKitServer.initialize)
    _register(SourceKitServer.clientInitialized)
    _register(SourceKitServer.cancelRequest)
    _register(SourceKitServer.shutdown)
    _register(SourceKitServer.exit)

    registerWorkspaceNotfication(SourceKitServer.openDocument)
    registerWorkspaceNotfication(SourceKitServer.closeDocument)
    registerWorkspaceNotfication(SourceKitServer.changeDocument)
    registerWorkspaceNotfication(SourceKitServer.willSaveDocument)
    registerWorkspaceNotfication(SourceKitServer.didSaveDocument)
    registerWorkspaceRequest(SourceKitServer.completion)
    registerWorkspaceRequest(SourceKitServer.hover)
    registerWorkspaceRequest(SourceKitServer.definition)
    registerWorkspaceRequest(SourceKitServer.references)
    registerWorkspaceRequest(SourceKitServer.documentSymbolHighlight)
    registerWorkspaceRequest(SourceKitServer.foldingRange)
    registerWorkspaceRequest(SourceKitServer.symbolInfo)
    registerWorkspaceRequest(SourceKitServer.documentSymbol)
    registerWorkspaceRequest(SourceKitServer.documentColor)
    registerWorkspaceRequest(SourceKitServer.colorPresentation)
    registerWorkspaceRequest(SourceKitServer.codeAction)
  }

  func registerWorkspaceRequest<R>(
    _ requestHandler: @escaping (SourceKitServer) -> (Request<R>, Workspace) -> Void)
  {
    _register { [unowned self] (req: Request<R>) in
      guard let workspace = self.workspace else {
        return req.reply(.failure(.serverNotInitialized))
      }

      requestHandler(self)(req, workspace)
    }
  }

  func registerWorkspaceNotfication<N>(
    _ noteHandler: @escaping (SourceKitServer) -> (Notification<N>, Workspace) -> Void)
  {
    _register { [unowned self] (note: Notification<N>) in
      guard let workspace = self.workspace else {
        log("received notification before \"initialize\", ignoring...", level: .error)
        return
      }

      noteHandler(self)(note, workspace)
    }
  }

  public override func _handleUnknown<R>(_ req: Request<R>) {
    if req.clientID == ObjectIdentifier(client) {
      return super._handleUnknown(req)
    }

    // Unknown requests from a language server are passed on to the client.
    let id = client.send(req.params, queue: queue) { result in
      req.reply(result)
    }
    req.cancellationToken.addCancellationHandler {
      self.client.send(CancelRequest(id: id))
    }
  }

  /// Handle an unknown notification.
  public override func _handleUnknown<N>(_ note: Notification<N>) {
    if note.clientID == ObjectIdentifier(client) {
      return super._handleUnknown(note)
    }

    // Unknown notifications from a language server are passed on to the client.
    client.send(note.params)
  }

  func toolchain(for url: URL, _ language: Language) -> Toolchain? {
    if let toolchain = workspace?.buildSettings.settings(for: url, language)?.preferredToolchain {
      return toolchain
    }

    let supportsLang = { (toolchain: Toolchain) -> Bool in
      // FIXME: the fact that we're looking at clangd/sourcekitd instead of the compiler indicates this method needs a parameter stating what kind of tool we're looking for.
      switch language {
      case .swift:
        return toolchain.sourcekitd != nil
      case .c, .cpp, .objective_c, .objective_cpp:
        return toolchain.clangd != nil
      default:
        return false
      }
    }

    if let toolchain = toolchainRegistry.default, supportsLang(toolchain) {
      return toolchain
    }

    for toolchain in toolchainRegistry.toolchains {
      if supportsLang(toolchain) {
        return toolchain
      }
    }

    return nil
  }

  func languageService(for toolchain: Toolchain, _ language: Language) -> Connection? {
    let key = LanguageServiceKey(toolchain: toolchain.identifier, language: language)
    if let service = languageService[key] {
      return service
    }

    // Start a new service.
    return orLog("failed to start language service", level: .error) {
      guard let service = try SourceKit.languageService(for: toolchain, language, client: self) else {
        return nil
      }

      let pid = Int(ProcessInfo.processInfo.processIdentifier)
      let resp = try service.sendSync(InitializeRequest(
        processId: pid,
        rootPath: nil,
        rootURL: (workspace?.rootPath).map { URL(fileURLWithPath: $0.pathString) },
        initializationOptions: InitializationOptions(),
        capabilities: workspace?.clientCapabilities ?? ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))

      // FIXME: store the server capabilities.
      guard case .incremental? = resp.capabilities.textDocumentSync?.change else {
        fatalError("non-incremental update not implemented")
      }

      service.send(InitializedNotification())

      languageService[key] = service
      return service
    }
  }

  func languageService(for url: URL, _ language: Language, in workspace: Workspace) -> Connection? {
    if let service = workspace.documentService[url] {
      return service
    }

    guard let toolchain = toolchain(for: url, language),
          let service = languageService(for: toolchain, language)
    else {
      return nil
    }

    log("Using toolchain \(toolchain.displayName) (\(toolchain.identifier)) for \(url)")

    workspace.documentService[url] = service
    return service
  }
}

// MARK: - Request and notification handling

extension SourceKitServer {

  // MARK: - General

  func initialize(_ req: Request<InitializeRequest>) {
    if let url = req.params.rootURL {
      self.workspace = try? Workspace(
        url: url,
        clientCapabilities: req.params.capabilities,
        toolchainRegistry: self.toolchainRegistry,
        buildSetup: self.buildSetup)
    } else if let path = req.params.rootPath {
      self.workspace = try? Workspace(
        url: URL(fileURLWithPath: path),
        clientCapabilities: req.params.capabilities,
        toolchainRegistry: self.toolchainRegistry,
        buildSetup: self.buildSetup)
    }

    if self.workspace == nil {
      log("no workspace found", level: .warning)

      self.workspace = Workspace(
        rootPath: nil,
        clientCapabilities: req.params.capabilities,
        buildSettings: BuildSystemList(),
        index: nil,
        buildSetup: self.buildSetup
      )
    }

    req.reply(InitializeResult(capabilities: ServerCapabilities(
      textDocumentSync: TextDocumentSyncOptions(
        openClose: true,
        change: .incremental,
        willSave: true,
        willSaveWaitUntil: false,
        save: TextDocumentSyncOptions.SaveOptions(includeText: false)
      ),
      completionProvider: CompletionOptions(
        resolveProvider: false,
        triggerCharacters: ["."]
      ),
      hoverProvider: true,
      definitionProvider: true,
      referencesProvider: true,
      documentHighlightProvider: true,
      foldingRangeProvider: true,
      documentSymbolProvider: true,
      colorProvider: true,
      codeActionProvider: CodeActionServerCapabilities(
        clientCapabilities: req.params.capabilities.textDocument?.codeAction,
        codeActionOptions: CodeActionOptions(codeActionKinds: nil),
        supportsCodeActions: false // TODO: Turn it on after a provider is implemented.
      )
    )))
  }

  func clientInitialized(_: Notification<InitializedNotification>) {
    // Nothing to do.
  }

  func cancelRequest(_ notification: Notification<CancelRequest>) {
    let key = RequestCancelKey(client: notification.clientID, request: notification.params.id)
    requestCancellation[key]?.cancel()
  }

  func shutdown(_ request: Request<Shutdown>) {
    // Nothing to do yet.
    request.reply(VoidResponse())
  }

  func exit(_ notification: Notification<Exit>) {
    onExit()
  }

  // MARK: - Text synchronization

  func openDocument(_ note: Notification<DidOpenTextDocument>, workspace: Workspace) {
    workspace.documentManager.open(note)

    if let service = languageService(for: note.params.textDocument.url, note.params.textDocument.language, in: workspace) {
      service.send(note.params)
    }
  }

  func closeDocument(_ note: Notification<DidCloseTextDocument>, workspace: Workspace) {
    workspace.documentManager.close(note)

    if let service = workspace.documentService[note.params.textDocument.url] {
      service.send(note.params)
    }
  }

  func changeDocument(_ note: Notification<DidChangeTextDocument>, workspace: Workspace) {
    workspace.documentManager.edit(note)

    if let service = workspace.documentService[note.params.textDocument.url] {
      service.send(note.params)
    }
  }

  func willSaveDocument(_ note: Notification<WillSaveTextDocument>, workspace: Workspace) {

  }

  func didSaveDocument(_ note: Notification<DidSaveTextDocument>, workspace: Workspace) {

  }

  // MARK: - Language features

  func completion(_ req: Request<CompletionRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(
      req,
      workspace: workspace,
      fallback: CompletionList(isIncomplete: false, items: []))
  }

  func hover(_ req: Request<HoverRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  /// Forwards a SymbolInfoRequest to the appropriate toolchain service for this document.
  func symbolInfo(_ req: Request<SymbolInfoRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: [])
  }

  func documentSymbolHighlight(_ req: Request<DocumentHighlightRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  func foldingRange(_ req: Request<FoldingRangeRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  func documentSymbol(_ req: Request<DocumentSymbolRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  func documentColor(_ req: Request<DocumentColorRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  func colorPresentation(_ req: Request<ColorPresentationRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  func codeAction(_ req: Request<CodeActionRequest>, workspace: Workspace) {
    toolchainTextDocumentRequest(req, workspace: workspace, fallback: nil)
  }

  func definition(_ req: Request<DefinitionRequest>, workspace: Workspace) {
    // FIXME: sending yourself a request isn't very convenient

    guard let service = workspace.documentService[req.params.textDocument.url] else {
      req.reply([])
      return
    }

    let id = service.send(SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position), queue: queue) { result in
      guard let symbols: [SymbolDetails] = result.success ?? nil, let symbol = symbols.first else {
        if let error = result.failure {
          req.reply(.failure(error))
        } else {
          req.reply([])
        }
        return
      }

      let fallbackLocation = [symbol.bestLocalDeclaration].compactMap { $0 }

      guard let usr = symbol.usr, let index = workspace.index else {
        return req.reply(fallbackLocation)
      }

      log("performing indexed jump-to-def with usr \(usr)")

      var occurs = index.occurrences(ofUSR: usr, roles: [.definition])
      if occurs.isEmpty {
        occurs = index.occurrences(ofUSR: usr, roles: [.declaration])
      }

      // FIXME: overrided method logic

      let locations = occurs.compactMap { occur -> Location? in
        if occur.location.path.isEmpty {
          return nil
        }
        return Location(
          url: URL(fileURLWithPath: occur.location.path),
          range: Range(Position(
            line: occur.location.line - 1, // 1-based -> 0-based
            // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
            utf16index: occur.location.utf8Column - 1
            ))
        )
      }

      req.reply(locations.isEmpty ? fallbackLocation : locations)
    }
    req.cancellationToken.addCancellationHandler { [weak service] in
      service?.send(CancelRequest(id: id))
    }
  }

  // FIXME: a lot of duplication with definition request
  func references(_ req: Request<ReferencesRequest>, workspace: Workspace) {
    // FIXME: sending yourself a request isn't very convenient

    guard let service = workspace.documentService[req.params.textDocument.url] else {
      req.reply([])
      return
    }


    let id = service.send(SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position), queue: queue) { result in
      guard let symbols: [SymbolDetails] = result.success ?? nil, let symbol = symbols.first else {
        if let error = result.failure {
          req.reply(.failure(error))
        } else {
          req.reply([])
        }
        return
      }

      guard let usr = symbol.usr, let index = workspace.index else {
        req.reply([])
        return
      }

      log("performing indexed jump-to-def with usr \(usr)")

      var roles: SymbolRole = [.reference]
      if req.params.includeDeclaration != false {
        roles.formUnion([.declaration, .definition])
      }

      let occurs = index.occurrences(ofUSR: usr, roles: roles)

      let locations = occurs.compactMap { occur -> Location? in
        if occur.location.path.isEmpty {
          return nil
        }
        return Location(
          url: URL(fileURLWithPath: occur.location.path),
          range: Range(Position(
            line: occur.location.line - 1, // 1-based -> 0-based
            // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
            utf16index: occur.location.utf8Column - 1
            ))
        )
      }

      req.reply(locations)
    }
    req.cancellationToken.addCancellationHandler { [weak service] in
      service?.send(CancelRequest(id: id))
    }
  }

  func toolchainTextDocumentRequest<PositionRequest>(
    _ req: Request<PositionRequest>,
    workspace: Workspace,
    fallback: @autoclosure () -> PositionRequest.Response)
  where PositionRequest: TextDocumentRequest
  {
    guard let service = workspace.documentService[req.params.textDocument.url] else {
      req.reply(fallback())
      return
    }

    let id = service.send(req.params, queue: DispatchQueue.global()) { result in
      req.reply(result)
    }
    req.cancellationToken.addCancellationHandler { [weak service] in
      service?.send(CancelRequest(id: id))
    }
  }
}

/// Creates a new connection from `client` to a service for `language` if available, and launches
/// the service. Does *not* send the initialization request.
///
/// - returns: The connection, if a suitable language service is available; otherwise nil.
/// - throws: If there is a suitable service but it fails to launch, throws an error.
public func languageService(
  for toolchain: Toolchain,
  _ language: Language,
  client: MessageHandler) throws -> Connection?
{
  switch language {

  case .c, .cpp, .objective_c, .objective_cpp:
    guard let clangd = toolchain.clangd else { return nil }
    return try makeJSONRPCClangServer(client: client, clangd: clangd, buildSettings: (client as? SourceKitServer)?.workspace?.buildSettings)

  case .swift:
    guard let sourcekitd = toolchain.sourcekitd else { return nil }
    return try makeLocalSwiftServer(client: client, sourcekitd: sourcekitd, buildSettings: (client as? SourceKitServer)?.workspace?.buildSettings, clientCapabilities: (client as? SourceKitServer)?.workspace?.clientCapabilities)

  default:
    return nil
  }
}

public typealias Notification = LanguageServerProtocol.Notification
public typealias Diagnostic = LanguageServerProtocol.Diagnostic
