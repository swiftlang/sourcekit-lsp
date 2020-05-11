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

import BuildServerProtocol
import Dispatch
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import LSPLogging
import SKCore
import SKSupport
import TSCBasic
import TSCLibc
import TSCUtility

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

  let options: Options

  let toolchainRegistry: ToolchainRegistry

  var languageService: [LanguageServiceKey: ToolchainLanguageServer] = [:]

  public var workspace: Workspace?

  let fs: FileSystem

  var onExit: () -> Void

  /// Creates a language server for the given client.
  public init(client: Connection, fileSystem: FileSystem = localFileSystem, options: Options, onExit: @escaping () -> Void = {}) {

    self.fs = fileSystem
    self.toolchainRegistry = ToolchainRegistry.shared
    self.options = options
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

    registerWorkspaceRequest(SourceKitServer.workspaceSymbols)
    registerWorkspaceRequest(SourceKitServer.references)
    registerWorkspaceRequest(SourceKitServer.pollIndex)
    registerWorkspaceRequest(SourceKitServer.executeCommand)

    registerToolchainTextDocumentRequest(SourceKitServer.completion,
                                         CompletionList(isIncomplete: false, items: []))
    registerToolchainTextDocumentRequest(SourceKitServer.hover, nil)
    registerToolchainTextDocumentRequest(SourceKitServer.definition, .locations([]))
    registerToolchainTextDocumentRequest(SourceKitServer.implementation, .locations([]))
    registerToolchainTextDocumentRequest(SourceKitServer.symbolInfo, [])
    registerToolchainTextDocumentRequest(SourceKitServer.documentSymbolHighlight, nil)
    registerToolchainTextDocumentRequest(SourceKitServer.foldingRange, nil)
    registerToolchainTextDocumentRequest(SourceKitServer.documentSymbol, nil)
    registerToolchainTextDocumentRequest(SourceKitServer.documentColor, nil)
    registerToolchainTextDocumentRequest(SourceKitServer.colorPresentation, nil)
    registerToolchainTextDocumentRequest(SourceKitServer.codeAction, nil)
  }

  func registerToolchainTextDocumentRequest<PositionRequest: TextDocumentRequest>(
    _ requestHandler: @escaping (SourceKitServer) -> (Request<PositionRequest>, ToolchainLanguageServer) -> Void,
    _ fallback: PositionRequest.Response
  ) {
    _register { [unowned self] (req: Request<PositionRequest>) in
      guard let workspace = self.workspace else {
        return req.reply(.failure(.serverNotInitialized))
      }
      guard let languageService = workspace.documentService[req.params.textDocument.uri] else {
        return req.reply(fallback)
      }
      requestHandler(self)(req, languageService)
    }
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
      self.client.send(CancelRequestNotification(id: id))
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

  func toolchain(for uri: DocumentURI, _ language: Language) -> Toolchain? {
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

  func languageService(for toolchain: Toolchain, _ language: Language) -> ToolchainLanguageServer? {
    let key = LanguageServiceKey(toolchain: toolchain.identifier, language: language)
    if let service = languageService[key] {
      return service
    }

    // Start a new service.
    return orLog("failed to start language service", level: .error) {
      guard let service = try SourceKit.languageService(for: toolchain, language, options: options, client: self) else {
        return nil
      }

      let pid = Int(ProcessInfo.processInfo.processIdentifier)
      let resp = try service.initializeSync(InitializeRequest(
        processId: pid,
        rootPath: nil,
        rootURI: workspace?.rootUri,
        initializationOptions: nil,
        capabilities: workspace?.clientCapabilities ?? ClientCapabilities(workspace: nil, textDocument: nil),
        trace: .off,
        workspaceFolders: nil))

      // FIXME: store the server capabilities.
      let syncKind = resp.capabilities.textDocumentSync?.change ?? .incremental
      guard syncKind == .incremental else {
        fatalError("non-incremental update not implemented")
      }

      service.clientInitialized(InitializedNotification())

      languageService[key] = service
      return service
    }
  }

  func languageService(for uri: DocumentURI, _ language: Language, in workspace: Workspace) -> ToolchainLanguageServer? {
    if let service = workspace.documentService[uri] {
      return service
    }

    guard let toolchain = toolchain(for: uri, language),
          let service = languageService(for: toolchain, language)
    else {
      return nil
    }

    log("Using toolchain \(toolchain.displayName) (\(toolchain.identifier)) for \(uri)")

    workspace.documentService[uri] = service
    return service
  }
}

// MARK: - Build System Delegate

extension SourceKitServer: BuildSystemDelegate {
  public func buildTargetsChanged(_ changes: [BuildTargetEvent]) {
    // TODO: do something with these changes once build target support is in place
  }

  private func affectedOpenDocumentsForChangeSet(
    _ changes: Set<DocumentURI>,
    _ documentManager: DocumentManager
  ) -> Set<DocumentURI> {
    // An empty change set is treated as if all open files have been modified.
    guard !changes.isEmpty else {
      return documentManager.openDocuments
    }
    return documentManager.openDocuments.intersection(changes)
  }

  public func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) {
    queue.async {
      guard let workspace = self.workspace else {
        return
      }
      let documentManager = workspace.documentManager
      for uri in self.affectedOpenDocumentsForChangeSet(changedFiles, documentManager) {
        log("Build settings changed for opened file \(uri)")
        if let snapshot = documentManager.latestSnapshot(uri),
          let service = self.languageService(for: uri, snapshot.document.language, in: workspace) {
          service.documentUpdatedBuildSettings(uri, language: snapshot.document.language)
        }
      }
    }
  }

  public func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    queue.async {
      guard let workspace = self.workspace else {
        return
      }
      let documentManager = workspace.documentManager
      for uri in self.affectedOpenDocumentsForChangeSet(changedFiles, documentManager) {
        log("Dependencies updated for opened file \(uri)")
        if let snapshot = documentManager.latestSnapshot(uri),
          let service = self.languageService(for: uri, snapshot.document.language, in: workspace) {
          service.documentDependenciesUpdated(uri, language: snapshot.document.language)
        }
      }
    }
  }
}

// MARK: - Request and notification handling

extension SourceKitServer {

  // MARK: - General

  func initialize(_ req: Request<InitializeRequest>) {

    var indexOptions = self.options.indexOptions
    if case .dictionary(let options) = req.params.initializationOptions {
      if case .bool(let listenToUnitEvents) = options["listenToUnitEvents"] {
        indexOptions.listenToUnitEvents = listenToUnitEvents
      }
    }

    // Any messages sent before initialize returns are expected to fail, so this will run before
    // the first "supported" request. Run asynchronously to hide the latency of setting up the
    // build system and index.
    queue.async {
      if let uri = req.params.rootURI {
        self.workspace = try? Workspace(
          rootUri: uri,
          clientCapabilities: req.params.capabilities,
          toolchainRegistry: self.toolchainRegistry,
          buildSetup: self.options.buildSetup,
          indexOptions: indexOptions)
      } else if let path = req.params.rootPath {
        self.workspace = try? Workspace(
          rootUri: DocumentURI(URL(fileURLWithPath: path)),
          clientCapabilities: req.params.capabilities,
          toolchainRegistry: self.toolchainRegistry,
          buildSetup: self.options.buildSetup,
          indexOptions: indexOptions)
      }

      if self.workspace == nil {
        log("no workspace found", level: .warning)

        self.workspace = Workspace(
          rootUri: req.params.rootURI,
          clientCapabilities: req.params.capabilities,
          toolchainRegistry: self.toolchainRegistry,
          buildSetup: self.options.buildSetup,
          underlyingBuildSystem: BuildSystemList(),
          index: nil,
          indexDelegate: nil)
      }

      assert(self.workspace != nil)
      self.workspace?.buildSettings.delegate = self
    }

    req.reply(InitializeResult(capabilities: ServerCapabilities(
      textDocumentSync: TextDocumentSyncOptions(
        openClose: true,
        change: .incremental,
        willSave: true,
        willSaveWaitUntil: false,
        save: TextDocumentSyncOptions.SaveOptions(includeText: false)
      ),
      hoverProvider: true,
      completionProvider: CompletionOptions(
        resolveProvider: false,
        triggerCharacters: ["."]
      ),
      definitionProvider: true,
      implementationProvider: .bool(true),
      referencesProvider: true,
      documentHighlightProvider: true,
      documentSymbolProvider: true,
      workspaceSymbolProvider: true,
      codeActionProvider: .value(CodeActionServerCapabilities(
        clientCapabilities: req.params.capabilities.textDocument?.codeAction,
        codeActionOptions: CodeActionOptions(codeActionKinds: nil),
        supportsCodeActions: true
      )),
      colorProvider: .bool(true),
      foldingRangeProvider: .bool(true),
      executeCommandProvider: ExecuteCommandOptions(
        commands: builtinSwiftCommands // FIXME: Clangd commands?
      )
    )))
  }

  func clientInitialized(_: Notification<InitializedNotification>) {
    // Nothing to do.
  }

  func cancelRequest(_ notification: Notification<CancelRequestNotification>) {
    let key = RequestCancelKey(client: notification.clientID, request: notification.params.id)
    requestCancellation[key]?.cancel()
  }

  /// The server is about to exit, and the server should flush any buffered state.
  ///
  /// The server shall not be used to handle more requests (other than possibly
  /// `shutdown` and `exit`) and should attempt to flush any buffered state
  /// immediately, such as sending index changes to disk.
  public func prepareForExit() {
    // Note: this method should be safe to call multiple times, since we want to
    // be resilient against multiple possible shutdown sequences, including
    // pipe failure.

    // Close the index, which will flush to disk.
    self.queue.sync {
      self._prepareForExit()
    }
  }

  func _prepareForExit() {
    // Note: this method should be safe to call multiple times, since we want to
    // be resilient against multiple possible shutdown sequences, including
    // pipe failure.

    // Close the index, which will flush to disk.
    self.workspace?.index = nil
  }


  func shutdown(_ request: Request<ShutdownRequest>) {
    _prepareForExit()
    request.reply(VoidResponse())
  }

  func exit(_ notification: Notification<ExitNotification>) {
    // Should have been called in shutdown, but allow misbehaving clients.
    _prepareForExit()

    // Call onExit only once, and hop off queue to allow the handler to call us back.
    let onExit = self.onExit
    self.onExit = {}
    DispatchQueue.global().async {
      onExit()
    }
  }

  // MARK: - Text synchronization

  func openDocument(_ note: Notification<DidOpenTextDocumentNotification>, workspace: Workspace) {
    workspace.documentManager.open(note.params)

    let textDocument = note.params.textDocument
    workspace.buildSettings.registerForChangeNotifications(
      for: textDocument.uri, language: textDocument.language)

    if let service = languageService(for: textDocument.uri, textDocument.language, in: workspace) {
      service.openDocument(note.params)
    }
  }

  func closeDocument(_ note: Notification<DidCloseTextDocumentNotification>, workspace: Workspace) {
    workspace.documentManager.close(note.params)

    workspace.buildSettings.unregisterForChangeNotifications(for: note.params.textDocument.uri)

    if let service = workspace.documentService[note.params.textDocument.uri] {
      service.closeDocument(note.params)
    }
  }

  func changeDocument(_ note: Notification<DidChangeTextDocumentNotification>, workspace: Workspace) {
    workspace.documentManager.edit(note.params)

    if let service = workspace.documentService[note.params.textDocument.uri] {
      service.changeDocument(note.params)
    }
  }

  func willSaveDocument(_ note: Notification<WillSaveTextDocumentNotification>, workspace: Workspace) {
    if let service = workspace.documentService[note.params.textDocument.uri] {
      service.willSaveDocument(note.params)
    }
  }

  func didSaveDocument(_ note: Notification<DidSaveTextDocumentNotification>, workspace: Workspace) {
    if let service = workspace.documentService[note.params.textDocument.uri] {
      service.didSaveDocument(note.params)
    }
  }

  // MARK: - Language features

  func completion(_ req: Request<CompletionRequest>, languageService: ToolchainLanguageServer) {
    languageService.completion(req)
  }

  func hover(_ req: Request<HoverRequest>, languageService: ToolchainLanguageServer) {
    languageService.hover(req)
  }

  /// Find all symbols in the workspace that include a string in their name.
  /// - returns: An array of SymbolOccurrences that match the string.
  func findWorkspaceSymbols(matching: String) -> [SymbolOccurrence] {
    var symbolOccurenceResults: [SymbolOccurrence] = []
    workspace?.index?.forEachCanonicalSymbolOccurrence(
      containing: matching,
      anchorStart: false,
      anchorEnd: false,
      subsequence: true,
      ignoreCase: true
    ) {symbol in
      if !symbol.location.isSystem && !symbol.roles.contains(.accessorOf) {
        symbolOccurenceResults.append(symbol)
      }
      return true
    }
    return symbolOccurenceResults
  }

  /// Handle a workspace/symbols request, returning the SymbolInformation.
  /// - returns: An array with SymbolInformation for each matching symbol in the workspace.
  func workspaceSymbols(_ req: Request<WorkspaceSymbolsRequest>, workspace: Workspace) {
    let symbols = findWorkspaceSymbols(
      matching: req.params.query
    ).map({symbolOccurrence -> SymbolInformation in
      let symbolPosition = Position(
        line: symbolOccurrence.location.line - 1, // 1-based -> 0-based
        // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
        utf16index: symbolOccurrence.location.utf8Column - 1)

      let symbolLocation = Location(
        uri: DocumentURI(URL(fileURLWithPath: symbolOccurrence.location.path)),
        range: Range(symbolPosition))

      return SymbolInformation(
        name: symbolOccurrence.symbol.name,
        kind: symbolOccurrence.symbol.kind.asLspSymbolKind(),
        deprecated: nil,
        location: symbolLocation,
        containerName: symbolOccurrence.getContainerName()
      )
    })
    req.reply(symbols)
  }

  /// Forwards a SymbolInfoRequest to the appropriate toolchain service for this document.
  func symbolInfo(_ req: Request<SymbolInfoRequest>, languageService: ToolchainLanguageServer) {
    languageService.symbolInfo(req)
  }

  func documentSymbolHighlight(
    _ req: Request<DocumentHighlightRequest>,
    languageService: ToolchainLanguageServer
  ) {
    languageService.documentSymbolHighlight(req)
  }

  func foldingRange(_ req: Request<FoldingRangeRequest>, languageService: ToolchainLanguageServer) {
    languageService.foldingRange(req)
  }

  func documentSymbol(
    _ req: Request<DocumentSymbolRequest>,
    languageService: ToolchainLanguageServer
  ) {
    languageService.documentSymbol(req)
  }

  func documentColor(
    _ req: Request<DocumentColorRequest>,
    languageService: ToolchainLanguageServer
  ) {
    languageService.documentColor(req)
  }

  func colorPresentation(
    _ req: Request<ColorPresentationRequest>,
    languageService: ToolchainLanguageServer
  ) {
    languageService.colorPresentation(req)
  }

  func executeCommand(_ req: Request<ExecuteCommandRequest>, workspace: Workspace) {
    guard let uri = req.params.textDocument?.uri else {
      log("attempted to perform executeCommand request without an url!", level: .error)
      req.reply(nil)
      return
    }
    guard let languageService = workspace.documentService[uri] else {
      req.reply(nil)
      return
    }
    let params = req.params
    let executeCommand = ExecuteCommandRequest(command: params.command,
                                               arguments: params.argumentsWithoutSourceKitMetadata)
    let callback = callbackOnQueue(self.queue) { (result: Result<ExecuteCommandRequest.Response, ResponseError>) in
      req.reply(result)
    }
    let request = Request(executeCommand, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    languageService.executeCommand(request)
  }

  func codeAction(_ req: Request<CodeActionRequest>, languageService: ToolchainLanguageServer) {
    let codeAction = CodeActionRequest(range: req.params.range, context: req.params.context,
                                       textDocument: req.params.textDocument)
    let callback = callbackOnQueue(self.queue) { (result: Result<CodeActionRequest.Response, ResponseError>) in
      switch result {
      case .success(let reply):
        req.reply(req.params.injectMetadata(toResponse: reply))
      default:
        req.reply(result)
      }
    }
    let request = Request(codeAction, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    languageService.codeAction(request)
  }

  func definition(_ req: Request<DefinitionRequest>, languageService: ToolchainLanguageServer) {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let index = self.workspace?.index
    let callback = callbackOnQueue(self.queue) { (result: Result<SymbolInfoRequest.Response, ResponseError>) in
      guard let symbols: [SymbolDetails] = result.success ?? nil, let symbol = symbols.first else {
        let handled = languageService.definition(req)
        guard !handled else { return }
        if let error = result.failure {
          req.reply(.failure(error))
        } else {
          req.reply(.locations([]))
        }
        return
      }

      let fallbackLocation = [symbol.bestLocalDeclaration].compactMap { $0 }

      guard let usr = symbol.usr, let index = index else {
        return req.reply(.locations(fallbackLocation))
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
          uri: DocumentURI(URL(fileURLWithPath: occur.location.path)),
          range: Range(Position(
            line: occur.location.line - 1, // 1-based -> 0-based
            // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
            utf16index: occur.location.utf8Column - 1
            ))
        )
      }

      req.reply(.locations(locations.isEmpty ? fallbackLocation : locations))
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    languageService.symbolInfo(request)
  }

  // FIXME: a lot of duplication with definition request
  func implementation(
    _ req: Request<ImplementationRequest>,
    languageService: ToolchainLanguageServer
  ) {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let index = self.workspace?.index
    let callback = callbackOnQueue(self.queue) { (result: Result<SymbolInfoRequest.Response, ResponseError>) in
      guard let symbols: [SymbolDetails] = result.success ?? nil, let symbol = symbols.first else {
        if let error = result.failure {
          req.reply(.failure(error))
        } else {
          req.reply(.locations([]))
        }
        return
      }

      guard let usr = symbol.usr, let index = index else {
        return req.reply(.locations([]))
      }

      var occurs = index.occurrences(ofUSR: usr, roles: .baseOf)
      if occurs.isEmpty {
        occurs = index.occurrences(relatedToUSR: usr, roles: .overrideOf)
      }

      let locations = occurs.compactMap { occur -> Location? in
        if occur.location.path.isEmpty {
          return nil
        }
        return Location(
          uri: DocumentURI(URL(fileURLWithPath: occur.location.path)),
          range: Range(Position(
            line: occur.location.line - 1, // 1-based -> 0-based
            // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
            utf16index: occur.location.utf8Column - 1
            ))
        )
      }

      req.reply(.locations(locations))
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    languageService.symbolInfo(request)
  }

  // FIXME: a lot of duplication with definition request
  func references(_ req: Request<ReferencesRequest>, workspace: Workspace) {
    guard let service = workspace.documentService[req.params.textDocument.uri] else {
      req.reply([])
      return
    }

    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let callback = callbackOnQueue(self.queue) { (result: Result<SymbolInfoRequest.Response, ResponseError>) in
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
      if req.params.context.includeDeclaration {
        roles.formUnion([.declaration, .definition])
      }

      let occurs = index.occurrences(ofUSR: usr, roles: roles)

      let locations = occurs.compactMap { occur -> Location? in
        if occur.location.path.isEmpty {
          return nil
        }
        return Location(
          uri: DocumentURI(URL(fileURLWithPath: occur.location.path)),
          range: Range(Position(
            line: occur.location.line - 1, // 1-based -> 0-based
            // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
            utf16index: occur.location.utf8Column - 1
            ))
        )
      }

      req.reply(locations)
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    service.symbolInfo(request)
  }

  func pollIndex(_ req: Request<PollIndexRequest>, workspace: Workspace) {
    workspace.index?.pollForUnitChangesAndWait()
    req.reply(VoidResponse())
  }
}

private func callbackOnQueue<R: ResponseType>(
  _ queue: DispatchQueue,
  _ callback: @escaping (LSPResult<R>) -> Void
) -> (LSPResult<R>) -> Void {
  return { (result: LSPResult<R>) in
    queue.async {
      callback(result)
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
  options: SourceKitServer.Options,
  client: MessageHandler) throws -> ToolchainLanguageServer?
{
  switch language {

  case .c, .cpp, .objective_c, .objective_cpp:
    guard toolchain.clangd != nil else { return nil }
    return try makeJSONRPCClangServer(client: client, toolchain: toolchain, buildSettings: (client as? SourceKitServer)?.workspace?.buildSettings, clangdOptions: options.clangdOptions)

  case .swift:
    guard let sourcekitd = toolchain.sourcekitd else { return nil }
    return try makeLocalSwiftServer(client: client, sourcekitd: sourcekitd, buildSettings: (client as? SourceKitServer)?.workspace?.buildSettings, clientCapabilities: (client as? SourceKitServer)?.workspace?.clientCapabilities)

  default:
    return nil
  }
}

public typealias Notification = LanguageServerProtocol.Notification
public typealias Diagnostic = LanguageServerProtocol.Diagnostic

extension IndexSymbolKind {
  func asLspSymbolKind() -> SymbolKind {
    switch self {
    case .class: 
      return .class
    case .classMethod, .instanceMethod, .staticMethod: 
      return .method
    case .instanceProperty, .staticProperty, .classProperty: 
      return .property
    case .enum: 
      return .enum
    case .enumConstant: 
      return .enumMember
    case .protocol: 
      return .interface
    case .function, .conversionFunction: 
      return .function
    case .variable: 
      return .variable
    case .struct: 
      return .struct
    case .parameter: 
      return .typeParameter

    default:
      return .null
    }
  }
}

extension SymbolOccurrence {
  /// Get the name of the symbol that is a parent of this symbol, if one exists
  func getContainerName() -> String? {
    return relations.first(where: { $0.roles.contains(.childOf) })?.symbol.name
  }
}
