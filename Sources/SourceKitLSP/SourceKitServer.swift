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
import SourceKitD

import PackageLoading

import protocol TSCBasic.FileSystem
import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem

public typealias URL = Foundation.URL

/// Exhaustive enumeration of all toolchain language servers known to SourceKit-LSP.
enum LanguageServerType: Hashable {
  case clangd
  case swift

  init?(language: Language) {
    switch language {
    case .c, .cpp, .objective_c, .objective_cpp:
      self = .clangd
    case .swift:
      self = .swift
    default:
      return nil
    }
  }

  /// The `ToolchainLanguageServer` class used to provide functionality for this language class.
  var serverType: ToolchainLanguageServer.Type {
    switch self {
    case .clangd:
      return ClangLanguageServerShim.self
    case .swift:
      return SwiftLanguageServer.self
    }
  }
}

/// Keeps track of the state to send work done progress updates to the client
final actor WorkDoneProgressState {
  private enum State {
    /// No `WorkDoneProgress` has been created.
    case noProgress
    /// We have sent the request to create a `WorkDoneProgress` but haven’t received a response yet.
    case creating
    /// A `WorkDoneProgress` has been created.
    case created
    /// The creation of a `WorkDoneProgress has failed`.
    ///
    /// This causes us to just give up creating any more `WorkDoneProgress` in
    /// the future as those will most likely also fail.
    case progressCreationFailed
  }

  /// How many active tasks are running.
  ///
  /// A work done progress should be displayed if activeTasks > 0
  private var activeTasks: Int = 0
  private var state: State = .noProgress

  /// The token by which we track the `WorkDoneProgress`.
  private let token: ProgressToken

  /// The title that should be displayed to the user in the UI.
  private let title: String

  init(_ token: String, title: String) {
    self.token = ProgressToken.string(token)
    self.title = title
  }
  
  /// Start a new task, creating a new `WorkDoneProgress` if none is running right now.
  ///
  /// - Parameter server: The server that is used to create the `WorkDoneProgress` on the client
  func startProgress(server: SourceKitServer) {
    activeTasks += 1
    if state == .noProgress {
      state = .creating
      // Discard the handle. We don't support cancellation of the creation of a work done progress.
      _ = server.client.send(CreateWorkDoneProgressRequest(token: token), queue: server.clientCommunicationQueue) { result in
        if result.success != nil {
          if self.activeTasks == 0 {
            // ActiveTasks might have been decreased while we created the `WorkDoneProgress`
            self.state = .noProgress
            server.client.send(WorkDoneProgress(token: self.token, value: .end(WorkDoneProgressEnd())))
          } else {
            self.state = .created
            server.client.send(WorkDoneProgress(token: self.token, value: .begin(WorkDoneProgressBegin(title: self.title))))
          }
        } else {
          self.state = .progressCreationFailed
        }
      }
    }
  }

  /// End a new task stated using `startProgress`.
  ///
  /// If this drops the active task count to 0, the work done progress is ended on the client.
  ///
  /// - Parameter server: The server that is used to send and update of the `WorkDoneProgress` to the client
  func endProgress(server: SourceKitServer) {
    assert(activeTasks > 0, "Unbalanced startProgress/endProgress calls")
    activeTasks -= 1
    if state == .created && activeTasks == 0 {
      server.client.send(WorkDoneProgress(token: token, value: .end(WorkDoneProgressEnd())))
    }
  }
}

/// The SourceKit language server.
///
/// This is the client-facing language server implementation, providing indexing, multiple-toolchain
/// and cross-language support. Requests may be dispatched to language-specific services or handled
/// centrally, but this is transparent to the client.
public actor SourceKitServer {
  // FIXME: (async) We can remove this if we migrate client.send to be async and it thus doesn't take a queue anymore.
  /// The queue on which we communicate with the client.
  public let clientCommunicationQueue: DispatchQueue = DispatchQueue(label: "language-server-queue", qos: .userInitiated)

  /// The queue on which all messages (notifications, requests, responses) are
  /// handled.
  ///
  /// The queue is blocked until the message has been sufficiently handled to
  /// avoid out-of-order handling of messages. For sourcekitd, this means that
  /// a request has been sent to sourcekitd and for clangd, this means that we
  /// have forwarded the request to clangd.
  ///
  /// The actual semantic handling of the message happens off this queue.
  private let messageHandlingQueue = AsyncQueue(.concurrent)

  /// The connection to the editor.
  public let client: Connection

  var options: Options

  let toolchainRegistry: ToolchainRegistry

  var capabilityRegistry: CapabilityRegistry?

  var languageServices: [LanguageServerType: [ToolchainLanguageServer]] = [:]

  private let documentManager = DocumentManager()

  private var packageLoadingWorkDoneProgress = WorkDoneProgressState("SourceKitLSP.SourceKitServer.reloadPackage", title: "Reloading Package")

  /// **Public for testing**
  public var _documentManager: DocumentManager {
    return documentManager
  }

  /// Caches which workspace a document with the given URI should be opened in.
  /// Must only be accessed from `queue`.
  private var uriToWorkspaceCache: [DocumentURI: WeakWorkspace] = [:]

  private var workspaces: [Workspace] = [] {
    didSet {
      uriToWorkspaceCache = [:]
    }
  }

  /// **Public for testing**
  public var _workspaces: [Workspace] {
    get {
      return self.workspaces
    }
    set {
      self.workspaces = newValue
    }
  }

  let fs: FileSystem

  var onExit: () -> Void

  /// Creates a language server for the given client.
  public init(client: Connection, fileSystem: FileSystem = localFileSystem, options: Options, onExit: @escaping () -> Void = {}) {
    self.fs = fileSystem
    self.toolchainRegistry = ToolchainRegistry.shared
    self.options = options
    self.onExit = onExit

    self.client = client
  }

  public func workspaceForDocument(uri: DocumentURI) async -> Workspace? {
    if workspaces.count == 1 {
      // Special handling: If there is only one workspace, open all files in it.
      // This retains the behavior of SourceKit-LSP before it supported multiple workspaces.
      return workspaces.first
    }

    if let cachedWorkspace = uriToWorkspaceCache[uri]?.value {
      return cachedWorkspace
    }

    // Pick the workspace with the best FileHandlingCapability for this file.
    // If there is a tie, use the workspace that occurred first in the list.
    var bestWorkspace: (workspace: Workspace?, fileHandlingCapability: FileHandlingCapability) = (nil, .unhandled)
    for workspace in workspaces {
      let fileHandlingCapability = await workspace.buildSystemManager.fileHandlingCapability(for: uri)
      if fileHandlingCapability > bestWorkspace.fileHandlingCapability {
        bestWorkspace = (workspace, fileHandlingCapability)
      }
    }
    uriToWorkspaceCache[uri] = WeakWorkspace(bestWorkspace.workspace)
    return bestWorkspace.workspace
  }

  /// Execute `notificationHandler` with the request as well as the workspace
  /// and language that handle this document.
  private func withLanguageServiceAndWorkspace<NotificationType: TextDocumentNotification>(
    for notification: Notification<NotificationType>,
    notificationHandler: @escaping (Notification<NotificationType>, ToolchainLanguageServer) async -> Void
  ) async {
    let doc = notification.params.textDocument.uri
    guard let workspace = await self.workspaceForDocument(uri: doc) else {
      return
    }

    // This should be created as soon as we receive an open call, even if the document
    // isn't yet ready.
    guard let languageService = workspace.documentService[doc] else {
      return
    }

    await notificationHandler(notification, languageService)
  }

  /// Execute `requestHandler` with the request as well as the workspace
  /// and language that handle this document.
  ///
  /// If no language service exists for the document mentioned in the request,
  /// reply with `fallback`.
  private func withLanguageServiceAndWorkspace<RequestType: TextDocumentRequest>(
    for request: Request<RequestType>,
    requestHandler: @escaping (Request<RequestType>, Workspace, ToolchainLanguageServer) async -> Void,
    fallback: RequestType.Response
  ) async {
    let doc = request.params.textDocument.uri
    guard let workspace = await self.workspaceForDocument(uri: doc) else {
      return request.reply(.failure(.workspaceNotOpen(doc)))
    }

    // This should be created as soon as we receive an open call, even if the document
    // isn't yet ready.
    guard let languageService = workspace.documentService[doc] else {
      return request.reply(fallback)
    }

    await requestHandler(request, workspace, languageService)
  }

  private func withLanguageServiceAndWorkspace<RequestType: TextDocumentRequest>(
    for request: Request<RequestType>,
    requestHandler: @escaping (RequestType, Workspace, ToolchainLanguageServer) async throws -> RequestType.Response,
    fallback: RequestType.Response
  ) async {
    let doc = request.params.textDocument.uri
    guard let workspace = await self.workspaceForDocument(uri: doc) else {
      return request.reply(.failure(.workspaceNotOpen(doc)))
    }

    guard let languageService = workspace.documentService[doc] else {
      return request.reply(fallback)
    }

    do {
      let result = try await requestHandler(request.params, workspace, languageService)
      request.reply(.success(result))
    } catch let error as ResponseError {
      request.reply(.failure(error))
    } catch let error as SKDError {
      request.reply(.failure(ResponseError(error)))
    } catch is CancellationError {
      request.reply(.failure(.cancelled))
    } catch {
      request.reply(.failure(.unknown("Unknown error: \(error)")))
    }
  }


  /// Send the given notification to the editor.
  public func sendNotificationToClient(_ notification: some NotificationType) {
    client.send(notification)
  }

  /// Send the given request to the editor.
  ///
  /// Return the result via the `reply` completion handler. `reply` is guaranteed
  /// to be called exactly once.
  public func sendRequestToClient<R: RequestType>(_ request: R, reply: @escaping (LSPResult<R.Response>) -> Void) {
    _ = client.send(request, queue: clientCommunicationQueue) { result in
      reply(result)
    }
    // FIXME: (async) Handle cancellation
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
  
  /// After the language service has crashed, send `DidOpenTextDocumentNotification`s to a newly instantiated language service for previously open documents.
  func reopenDocuments(for languageService: ToolchainLanguageServer) async {
    for documentUri in self.documentManager.openDocuments {
      guard let workspace = await self.workspaceForDocument(uri: documentUri) else {
        continue
      }
      guard workspace.documentService[documentUri] === languageService else {
        continue
      }
      guard let snapshot = self.documentManager.latestSnapshot(documentUri) else {
        // The document has been closed since we retrieved its URI. We don't care about it anymore.
        continue
      }

      // Close the document properly in the document manager and build system manager to start with a clean sheet when re-opening it.
      let closeNotification = DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(documentUri))
      await self.closeDocument(closeNotification, workspace: workspace)

      let textDocument = TextDocumentItem(uri: documentUri,
                                          language: snapshot.document.language,
                                          version: snapshot.version,
                                          text: snapshot.text)
      await self.openDocument(DidOpenTextDocumentNotification(textDocument: textDocument), workspace: workspace)
    }
  }

  /// If a language service of type `serverType` that can handle `workspace` has
  /// already been started, return it, otherwise return `nil`.
  private func existingLanguageService(_ serverType: LanguageServerType, workspace: Workspace) -> ToolchainLanguageServer? {
    for languageService in languageServices[serverType, default: []] {
      if languageService.canHandle(workspace: workspace) {
        return languageService
      }
    }
    return nil
  }

  func languageService(
    for toolchain: Toolchain,
    _ language: Language,
    in workspace: Workspace
  ) async -> ToolchainLanguageServer? {
    guard let serverType = LanguageServerType(language: language) else {
      return nil
    }
    // Pick the first language service that can handle this workspace.
    if let languageService = existingLanguageService(serverType, workspace: workspace) {
      return languageService
    }

    // Start a new service.
    return await orLog("failed to start language service", level: .error) {
      let service = try await serverType.serverType.init(
        sourceKitServer: self,
        toolchain: toolchain,
        options: options,
        workspace: workspace
      )

      guard let service else {
        return nil
      }

      let pid = Int(ProcessInfo.processInfo.processIdentifier)
      let resp = try await service.initializeSync(InitializeRequest(
        processId: pid,
        rootPath: nil,
        rootURI: workspace.rootUri,
        initializationOptions: nil,
        capabilities: workspace.capabilityRegistry.clientCapabilities,
        trace: .off,
        workspaceFolders: nil))
      let languages = languageClass(for: language)
      self.registerCapabilities(
        for: resp.capabilities, languages: languages, registry: workspace.capabilityRegistry)

      // FIXME: store the server capabilities.
      var syncKind: TextDocumentSyncKind
      switch resp.capabilities.textDocumentSync {
      case .options(let options):
        syncKind = options.change ?? .incremental
      case .kind(let kind):
        syncKind = kind
      default:
        syncKind = .incremental
      }
      guard syncKind == .incremental else {
        fatalError("non-incremental update not implemented")
      }

      await service.clientInitialized(InitializedNotification())

      if let concurrentlyInitializedService = existingLanguageService(serverType, workspace: workspace) {
        // Since we 'await' above, another call to languageService might have
        // happened concurrently, passed the `existingLanguageService` check at
        // the top and started initializing another language service.
        // If this race happened, just shut down our server and return the
        // other one.
        await service.shutdown()
        return concurrentlyInitializedService
      }

      languageServices[serverType, default: []].append(service)
      return service
    }
  }

  /// **Public for testing purposes only**
  public func _languageService(for uri: DocumentURI, _ language: Language, in workspace: Workspace) async -> ToolchainLanguageServer? {
    return await languageService(for: uri, language, in: workspace)
  }

  func languageService(for uri: DocumentURI, _ language: Language, in workspace: Workspace) async -> ToolchainLanguageServer? {
    if let service = workspace.documentService[uri] {
      return service
    }

    guard let toolchain = toolchain(for: uri, language),
          let service = await languageService(for: toolchain, language, in: workspace)
    else {
      return nil
    }

    log("Using toolchain \(toolchain.displayName) (\(toolchain.identifier)) for \(uri)")

    if let concurrentlySetService = workspace.documentService[uri] {
      // Since we await the construction of `service`, another call to this
      // function might have happened and raced us, setting
      // `workspace.documentServices[uri]`. If this is the case, return the
      // existing value and discard the service that we just retrieved.
      return concurrentlySetService
    }
    workspace.documentService[uri] = service
    return service
  }
}

// MARK: - MessageHandler

extension SourceKitServer: MessageHandler {
  public nonisolated func handle(_ params: some NotificationType, from clientID: ObjectIdentifier) {
    // All of the notifications sourcekit-lsp currently handles might modify the
    // global state (eg. whether a document is open or its contents) in a way
    // that changes the results of requsts before and after.
    // We thus need to ensure that we handle the notifications in order, so they
    // need to be dispatch barriers.
    //
    // Technically, we could optimize this further by having an `AsyncQueue` for
    // each file, because edits on one file should not block requests on another
    // file from executing but, at least in Swift, this would get us any real 
    // benefits at the moment because sourcekitd only has a single, global queue,
    // instead of a queue per file.
    // Additionally, usually you are editing one file in a source editor, which
    // means that concurrent requests to multiple files tend to be rare.
    messageHandlingQueue.async(barrier: true) {
      let notification = Notification(params, clientID: clientID)
      await self._logNotification(notification)

      switch notification {
      case let notification as Notification<InitializedNotification>:
        await self.clientInitialized(notification)
      case let notification as Notification<CancelRequestNotification>:
        await self.cancelRequest(notification)
      case let notification as Notification<ExitNotification>:
        await self.exit(notification)
      case let notification as Notification<DidOpenTextDocumentNotification>:
        await self.openDocument(notification)
      case let notification as Notification<DidCloseTextDocumentNotification>:
        await self.closeDocument(notification)
      case let notification as Notification<DidChangeTextDocumentNotification>:
        await self.changeDocument(notification)
      case let notification as Notification<DidChangeWorkspaceFoldersNotification>:
        await self.didChangeWorkspaceFolders(notification)
      case let notification as Notification<DidChangeWatchedFilesNotification>:
        await self.didChangeWatchedFiles(notification)
      case let notification as Notification<WillSaveTextDocumentNotification>:
        await self.withLanguageServiceAndWorkspace(for: notification, notificationHandler: self.willSaveDocument)
      case let notification as Notification<DidSaveTextDocumentNotification>:
        await self.withLanguageServiceAndWorkspace(for: notification, notificationHandler: self.didSaveDocument)
      default:
        break
      }
    }
  }

  public nonisolated func handle<R: RequestType>(_ params: R, id: RequestID, from clientID: ObjectIdentifier, reply: @escaping (LSPResult<R.Response >) -> Void) {
    // All of the requests sourcekit-lsp do not modify global state or require
    // the client to wait for the result before using the modified global state.
    // For example
    //  - `DeclarationRequest` does not modify global state
    //  - `CodeCompletionRequest` modifies the state of the current code
    //    completion session but it only makes sense for the client to request
    //    more results for this completion session after it has received the
    //    initial results.
    messageHandlingQueue.async(barrier: false) {
      let cancellationToken = CancellationToken()

      let request = Request(params, id: id, clientID: clientID, cancellation: cancellationToken, reply: { [weak self] result in
        reply(result)
        if let self {
          Task {
            await self._logResponse(result, id: id, method: R.method)
          }
        }
      })

      self._logRequest(request)

      switch request {
      case let request as Request<InitializeRequest>:
        await self.initialize(request)
      case let request as Request<ShutdownRequest>:
        await self.shutdown(request)
      case let request as Request<WorkspaceSymbolsRequest>:
        await self.workspaceSymbols(request)
      case let request as Request<PollIndexRequest>:
        await self.pollIndex(request)
      case let request as Request<ExecuteCommandRequest>:
        await self.executeCommand(request)
      case let request as Request<CallHierarchyIncomingCallsRequest>:
        await self.incomingCalls(request)
      case let request as Request<CallHierarchyOutgoingCallsRequest>:
        await self.outgoingCalls(request)
      case let request as Request<TypeHierarchySupertypesRequest>:
        await self.supertypes(request)
      case let request as Request<TypeHierarchySubtypesRequest>:
        await self.subtypes(request)
      case let request as Request<CompletionRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.completion, fallback: CompletionList(isIncomplete: false, items: []))
      case let request as Request<HoverRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.hover, fallback: nil)
      case let request as Request<OpenInterfaceRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.openInterface, fallback: nil)
      case let request as Request<DeclarationRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.declaration, fallback: nil)
      case let request as Request<DefinitionRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.definition, fallback: .locations([]))
      case let request as Request<ReferencesRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.references, fallback: [])
      case let request as Request<ImplementationRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.implementation, fallback: .locations([]))
      case let request as Request<CallHierarchyPrepareRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.prepareCallHierarchy, fallback: [])
      case let request as Request<TypeHierarchyPrepareRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.prepareTypeHierarchy, fallback: [])
      case let request as Request<SymbolInfoRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.symbolInfo, fallback: [])
      case let request as Request<DocumentHighlightRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentSymbolHighlight, fallback: nil)
      case let request as Request<FoldingRangeRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.foldingRange, fallback: nil)
      case let request as Request<DocumentSymbolRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentSymbol, fallback: nil)
      case let request as Request<DocumentColorRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentColor, fallback: [])
      case let request as Request<DocumentSemanticTokensRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentSemanticTokens, fallback: nil)
      case let request as Request<DocumentSemanticTokensDeltaRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentSemanticTokensDelta, fallback: nil)
      case let request as Request<DocumentSemanticTokensRangeRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentSemanticTokensRange, fallback: nil)
      case let request as Request<ColorPresentationRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.colorPresentation, fallback: [])
      case let request as Request<CodeActionRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.codeAction, fallback: nil)
      case let request as Request<InlayHintRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.inlayHint, fallback: [])
      case let request as Request<DocumentDiagnosticsRequest>:
        await self.withLanguageServiceAndWorkspace(for: request, requestHandler: self.documentDiagnostic, fallback: .full(.init(items: [])))
      default:
        reply(.failure(ResponseError.methodNotFound(R.method)))
      }
    }
  }

  private nonisolated func _logRequest<R>(_ request: Request<R>) {
    logAsync { currentLevel in
      guard currentLevel >= LogLevel.debug else {
        return "\(type(of: self)): Request<\(R.method)(\(request.id))>"
      }
      return "\(type(of: self)): \(request)"
    }
  }

  private func _logNotification<N>(_ notification: Notification<N>) {
    logAsync { currentLevel in
      guard currentLevel >= LogLevel.debug else {
        return "\(type(of: self)): Notification<\(N.method)>"
      }
      return "\(type(of: self)): \(notification)"
    }
  }

  private func _logResponse<Response>(_ result: LSPResult<Response>, id: RequestID, method: String) {
    logAsync { currentLevel in
      guard currentLevel >= LogLevel.debug else {
        return "\(type(of: self)): Response<\(method)(\(id))>"
      }
      return """
      \(type(of: self)): Response<\(method)(\(id))>(
        \(result)
      )
      """
    }
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

  /// Handle a build settings change notification from the `BuildSystem`.
  /// This has two primary cases:
  /// - Initial settings reported for a given file, now we can fully open it
  /// - Changed settings for an already open file
  public func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    for uri in changedFiles {
      guard self.documentManager.openDocuments.contains(uri) else {
        continue
      }

      guard let service = await self.workspaceForDocument(uri: uri)?.documentService[uri] else {
        continue
      }

      await service.documentUpdatedBuildSettings(uri)
    }
  }

  /// Handle a dependencies updated notification from the `BuildSystem`.
  /// We inform the respective language services as long as the given file is open
  /// (not queued for opening).
  public func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) async {
    // Split the changedFiles into the workspaces they belong to.
    // Then invoke affectedOpenDocumentsForChangeSet for each workspace with its affected files.
    let changedFilesAndWorkspace = await changedFiles.asyncMap {
      return (uri: $0, workspace: await self.workspaceForDocument(uri: $0))
    }
    for workspace in self.workspaces {
      let changedFilesForWorkspace = Set(changedFilesAndWorkspace.filter({ $0.workspace === workspace }).map(\.uri))
      if changedFilesForWorkspace.isEmpty {
        continue
      }
      for uri in self.affectedOpenDocumentsForChangeSet(changedFilesForWorkspace, self.documentManager) {
        log("Dependencies updated for opened file \(uri)")
        if let service = workspace.documentService[uri] {
          await service.documentDependenciesUpdated(uri)
        }
      }
    }
  }

  public func fileHandlingCapabilityChanged() {
    self.uriToWorkspaceCache = [:]
  }
}

// MARK: - Request and notification handling

extension SourceKitServer {

  // MARK: - General

  /// Creates a workspace at the given `uri`.
  private func createWorkspace(uri: DocumentURI) async -> Workspace? {
    guard let capabilityRegistry = capabilityRegistry else {
      log("Cannot open workspace before server is initialized")
      return nil
    }
    return try? await Workspace(
      documentManager: self.documentManager,
      rootUri: uri,
      capabilityRegistry: capabilityRegistry,
      toolchainRegistry: self.toolchainRegistry,
      buildSetup: self.options.buildSetup,
      indexOptions: self.options.indexOptions,
      reloadPackageStatusCallback: { status in
        guard capabilityRegistry.clientCapabilities.window?.workDoneProgress ?? false else {
          // Client doesn’t support work done progress
          return
        }
        switch status {
        case .start:
          await self.packageLoadingWorkDoneProgress.startProgress(server: self)
        case .end:
          await self.packageLoadingWorkDoneProgress.endProgress(server: self)
        }
      }
    )
  }

  func initialize(_ req: Request<InitializeRequest>) async {
    if case .dictionary(let options) = req.params.initializationOptions {
      if case .bool(let listenToUnitEvents) = options["listenToUnitEvents"] {
        self.options.indexOptions.listenToUnitEvents = listenToUnitEvents
      }
      if case .dictionary(let completionOptions) = options["completion"] {
        if case .bool(let serverSideFiltering) = completionOptions["serverSideFiltering"] {
          self.options.completionOptions.serverSideFiltering = serverSideFiltering
        }
        switch completionOptions["maxResults"] {
        case .none:
          break
        case .some(.null):
          self.options.completionOptions.maxResults = nil
        case .some(.int(let maxResults)):
          self.options.completionOptions.maxResults = maxResults
        case .some(let invalid):
          log("expected null or int for 'maxResults'; got \(invalid)", level: .warning)
        }
      }
    }

    capabilityRegistry = CapabilityRegistry(clientCapabilities: req.params.capabilities)

    if let workspaceFolders = req.params.workspaceFolders {
      self.workspaces += await workspaceFolders.asyncCompactMap { await self.createWorkspace(uri: $0.uri) }
    } else if let uri = req.params.rootURI {
      if let workspace = await self.createWorkspace(uri: uri) {
        self.workspaces.append(workspace)
      }
    } else if let path = req.params.rootPath {
      if let workspace = await self.createWorkspace(uri: DocumentURI(URL(fileURLWithPath: path))) {
        self.workspaces.append(workspace)
      }
    }

    if self.workspaces.isEmpty {
      log("no workspace found", level: .warning)

      let workspace = await Workspace(
        documentManager: self.documentManager,
        rootUri: req.params.rootURI,
        capabilityRegistry: self.capabilityRegistry!,
        toolchainRegistry: self.toolchainRegistry,
        buildSetup: self.options.buildSetup,
        underlyingBuildSystem: nil,
        index: nil,
        indexDelegate: nil
      )

      // Another workspace might have been added while we awaited the
      // construction of the workspace above. If that race happened, just
      // discard the workspace we created here since `workspaces` now isn't
      // empty anymore.
      if self.workspaces.isEmpty {
        self.workspaces.append(workspace)
      }
    }

    assert(!self.workspaces.isEmpty)
    for workspace in self.workspaces {
      await workspace.buildSystemManager.setDelegate(self)
    }

    req.reply(InitializeResult(capabilities:
      self.serverCapabilities(for: req.params.capabilities, registry: self.capabilityRegistry!)))
  }

  func serverCapabilities(
    for client: ClientCapabilities,
    registry: CapabilityRegistry
  ) -> ServerCapabilities {
    let completionOptions: CompletionOptions?
    if registry.clientHasDynamicCompletionRegistration {
      // We'll initialize this dynamically instead of statically.
      completionOptions = nil
    } else {
      completionOptions = LanguageServerProtocol.CompletionOptions(
        resolveProvider: false,
        triggerCharacters: ["."]
      )
    }
    let executeCommandOptions: ExecuteCommandOptions?
    if registry.clientHasDynamicExecuteCommandRegistration {
      executeCommandOptions = nil
    } else {
      executeCommandOptions = ExecuteCommandOptions(commands: builtinSwiftCommands)
    }
    return ServerCapabilities(
      textDocumentSync: .options(TextDocumentSyncOptions(
        openClose: true,
        change: .incremental
      )),
      hoverProvider: .bool(true),
      completionProvider: completionOptions,
      definitionProvider: .bool(true),
      implementationProvider: .bool(true),
      referencesProvider: .bool(true),
      documentHighlightProvider: .bool(true),
      documentSymbolProvider: .bool(true),
      workspaceSymbolProvider: .bool(true),
      codeActionProvider: .value(CodeActionServerCapabilities(
        clientCapabilities: client.textDocument?.codeAction,
        codeActionOptions: CodeActionOptions(codeActionKinds: nil),
        supportsCodeActions: true
      )),
      colorProvider: .bool(true),
      foldingRangeProvider: .bool(!registry.clientHasDynamicFoldingRangeRegistration),
      declarationProvider: .bool(true),
      executeCommandProvider: executeCommandOptions,
      workspace: WorkspaceServerCapabilities(workspaceFolders: .init(
        supported: true,
        changeNotifications: .bool(true)
      )),
      callHierarchyProvider: .bool(true),
      typeHierarchyProvider: .bool(true)
    )
  }

  func registerCapabilities(
    for server: ServerCapabilities,
    languages: [Language],
    registry: CapabilityRegistry
  ) {
    if let completionOptions = server.completionProvider {
      registry.registerCompletionIfNeeded(options: completionOptions, for: languages) {
        self.dynamicallyRegisterCapability($0, registry)
      }
    }
    if server.foldingRangeProvider?.isSupported == true {
      registry.registerFoldingRangeIfNeeded(options: FoldingRangeOptions(), for: languages) {
        self.dynamicallyRegisterCapability($0, registry)
      }
    }
    if let semanticTokensOptions = server.semanticTokensProvider {
      registry.registerSemanticTokensIfNeeded(options: semanticTokensOptions, for: languages) {
        self.dynamicallyRegisterCapability($0, registry)
      }
    }
    if let inlayHintProvider = server.inlayHintProvider,
       inlayHintProvider.isSupported {
      let options: InlayHintOptions
      switch inlayHintProvider {
      case .bool(_):
        options = InlayHintOptions()
      case .value(let opts):
        options = opts
      }
      registry.registerInlayHintIfNeeded(options: options, for: languages) {
        self.dynamicallyRegisterCapability($0, registry)
      }
    }
    if let diagnosticOptions = server.diagnosticProvider {
      registry.registerDiagnosticIfNeeded(options: diagnosticOptions, for: languages) {
        self.dynamicallyRegisterCapability($0, registry)
      }
    }
    if let commandOptions = server.executeCommandProvider {
      registry.registerExecuteCommandIfNeeded(commands: commandOptions.commands) {
        self.dynamicallyRegisterCapability($0, registry)
      }
    }

    /// This must be a superset of the files that return true for SwiftPM's `Workspace.fileAffectsSwiftOrClangBuildSettings`.
    var watchers = FileRuleDescription.builtinRules.flatMap({ $0.fileTypes }).map { fileExtension in
      return FileSystemWatcher(globPattern: "**/*.\(fileExtension)", kind: [.create, .delete])
    }
    watchers.append(FileSystemWatcher(globPattern: "**/Package.swift", kind: [.change]))
    watchers.append(FileSystemWatcher(globPattern: "**/compile_commands.json", kind: [.create, .change, .delete]))
    watchers.append(FileSystemWatcher(globPattern: "**/compile_flags.txt", kind: [.create, .change, .delete]))
    registry.registerDidChangeWatchedFiles(watchers: watchers) {
      self.dynamicallyRegisterCapability($0, registry)
    }
  }

  private func dynamicallyRegisterCapability(
    _ registration: CapabilityRegistration,
    _ registry: CapabilityRegistry
  ) {
    let req = RegisterCapabilityRequest(registrations: [registration])
    let _ = client.send(req, queue: clientCommunicationQueue) { result in
      if let error = result.failure {
        log("Failed to dynamically register for \(registration.method): \(error)", level: .error)
        registry.remove(registration: registration)
      }
    }
  }

  func clientInitialized(_: Notification<InitializedNotification>) {
    // Nothing to do.
  }

  func cancelRequest(_ notification: Notification<CancelRequestNotification>) {
    // TODO: Implement cancellation
  }

  /// The server is about to exit, and the server should flush any buffered state.
  ///
  /// The server shall not be used to handle more requests (other than possibly
  /// `shutdown` and `exit`) and should attempt to flush any buffered state
  /// immediately, such as sending index changes to disk.
  public func prepareForExit() async {
    // Note: this method should be safe to call multiple times, since we want to
    // be resilient against multiple possible shutdown sequences, including
    // pipe failure.

    // Theoretically, new workspaces could be added while we are awaiting inside
    // the loop. But since we are currently exiting, it doesn't make sense for
    // the client to open new workspaces.
    for workspace in self.workspaces {
      await workspace.buildSystemManager.setMainFilesProvider(nil)
      // Close the index, which will flush to disk.
      workspace.index = nil

      // Break retain cycle with the BSM.
      await workspace.buildSystemManager.setDelegate(nil)
    }
  }


  func shutdown(_ request: Request<ShutdownRequest>) async {
    await prepareForExit()

    await withTaskGroup(of: Void.self) { taskGroup in
      for service in languageServices.values.flatMap({ $0 }) {
        taskGroup.addTask {
          await service.shutdown()
        }
      }
    }

    // We have a semantic guarantee that no request or notification should be
    // sent to an LSP server after the shutdown request. Thus, there's no chance
    // that a new language service has been started during the above 'await'
    // call.
    languageServices = [:]

    // Wait for all services to shut down before sending the shutdown response.
    // Otherwise we might terminate sourcekit-lsp while it still has open
    // connections to the toolchain servers, which could send messages to
    // sourcekit-lsp while it is being deallocated, causing crashes.
    request.reply(VoidResponse())
  }

  func exit(_ notification: Notification<ExitNotification>) async {
    // Should have been called in shutdown, but allow misbehaving clients.
    await prepareForExit()

    // Call onExit only once, and hop off queue to allow the handler to call us back.
    let onExit = self.onExit
    self.onExit = {}
    DispatchQueue.global().async {
      onExit()
    }
  }

  // MARK: - Text synchronization

  func openDocument(_ note: Notification<DidOpenTextDocumentNotification>) async {
    let uri = note.params.textDocument.uri
    guard let workspace = await workspaceForDocument(uri: uri) else {
      log("received open notification for file '\(uri)' without a corresponding workspace, ignoring...", level: .error)
      return
    }
    await openDocument(note.params, workspace: workspace)
  }

  private func openDocument(_ note: DidOpenTextDocumentNotification, workspace: Workspace) async {
    // Immediately open the document even if the build system isn't ready. This is important since
    // we check that the document is open when we receive messages from the build system.
    documentManager.open(note)

    let textDocument = note.textDocument
    let uri = textDocument.uri
    let language = textDocument.language

    // If we can't create a service, this document is unsupported and we can bail here.
    guard let service = await languageService(for: uri, language, in: workspace) else {
      return
    }

    await workspace.buildSystemManager.registerForChangeNotifications(for: uri, language: language)

    // If the document is ready, we can immediately send the notification.
    await service.openDocument(note)
  }

  func closeDocument(_ note: Notification<DidCloseTextDocumentNotification>) async {
    let uri = note.params.textDocument.uri
    guard let workspace = await workspaceForDocument(uri: uri) else {
      log("received close notification for file '\(uri)' without a corresponding workspace, ignoring...", level: .error)
      return
    }
    await self.closeDocument(note.params, workspace: workspace)
  }

  func closeDocument(_ note: DidCloseTextDocumentNotification, workspace: Workspace) async {
    // Immediately close the document. We need to be sure to clear our pending work queue in case
    // the build system still isn't ready.
    documentManager.close(note)

    let uri = note.textDocument.uri

    await workspace.buildSystemManager.unregisterForChangeNotifications(for: uri)

    await workspace.documentService[uri]?.closeDocument(note)
  }

  func changeDocument(_ note: Notification<DidChangeTextDocumentNotification>) async {
    let uri = note.params.textDocument.uri

    guard let workspace = await workspaceForDocument(uri: uri) else {
      log("received change notification for file '\(uri)' without a corresponding workspace, ignoring...", level: .error)
      return
    }

    // If the document is ready, we can handle the change right now.
    documentManager.edit(note.params)
    await workspace.documentService[uri]?.changeDocument(note.params)
  }

  func willSaveDocument(
    _ note: Notification<WillSaveTextDocumentNotification>,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.willSaveDocument(note.params)
  }

  func didSaveDocument(
    _ note: Notification<DidSaveTextDocumentNotification>,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.didSaveDocument(note.params)
  }

  func didChangeWorkspaceFolders(_ note: Notification<DidChangeWorkspaceFoldersNotification>) async {
    // There is a theoretical race condition here: While we await in this function,
    // the open documents or workspaces could have changed. Because of this,
    // we might close a document in a workspace that is no longer responsible
    // for it.
    // In practice, it is fine: sourcekit-lsp will not handle any new messages
    // while we are executing this function and thus there's no risk of
    // documents or workspaces changing. To hit the race condition, you need
    // to invoke the API of `SourceKitServer` directly and open documents
    // while this function is executing. Even in such an API use case, hitting
    // that race condition seems very unlikely.
    var preChangeWorkspaces: [DocumentURI: Workspace] = [:]
    for docUri in self.documentManager.openDocuments {
      preChangeWorkspaces[docUri] = await self.workspaceForDocument(uri: docUri)
    }
    if let removed = note.params.event.removed {
      self.workspaces.removeAll { workspace in
        return removed.contains(where: { workspaceFolder in
          workspace.rootUri == workspaceFolder.uri
        })
      }
    }
    if let added = note.params.event.added {
      let newWorkspaces = await added.asyncCompactMap { await self.createWorkspace(uri: $0.uri) }
      for workspace in newWorkspaces {
        await workspace.buildSystemManager.setDelegate(self)
      }
      self.workspaces.append(contentsOf: newWorkspaces)
    }

    // For each document that has moved to a different workspace, close it in
    // the old workspace and open it in the new workspace.
    for docUri in self.documentManager.openDocuments {
      let oldWorkspace = preChangeWorkspaces[docUri]
      let newWorkspace = await self.workspaceForDocument(uri: docUri)
      if newWorkspace !== oldWorkspace {
        guard let snapshot = documentManager.latestSnapshot(docUri) else {
          continue
        }
        if let oldWorkspace = oldWorkspace {
          await self.closeDocument(DidCloseTextDocumentNotification(
            textDocument: TextDocumentIdentifier(docUri)
          ), workspace: oldWorkspace)
        }
        if let newWorkspace = newWorkspace {
          await self.openDocument(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
            uri: docUri,
            language: snapshot.document.language,
            version: snapshot.version,
            text: snapshot.text
          )), workspace: newWorkspace)
        }
      }
    }
  }

  func didChangeWatchedFiles(_ note: Notification<DidChangeWatchedFilesNotification>) async {
    // We can't make any assumptions about which file changes a particular build
    // system is interested in. Just because it doesn't have build settings for
    // a file doesn't mean a file can't affect the build system's build settings
    // (e.g. Package.swift doesn't have build settings but affects build
    // settings). Inform the build system about all file changes.
    for workspace in workspaces {
      await workspace.buildSystemManager.filesDidChange(note.params.changes)
    }
  }

  // MARK: - Language features

  func completion(
    _ req: CompletionRequest,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async throws -> CompletionList {
    return try await languageService.completion(req)
  }

  func hover(
    _ req: HoverRequest,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async throws -> HoverResponse? {
    return try await languageService.hover(req)
  }
  
  func openInterface(
    _ req: Request<OpenInterfaceRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.openInterface(req)
  }

  /// Find all symbols in the workspace that include a string in their name.
  /// - returns: An array of SymbolOccurrences that match the string.
  func findWorkspaceSymbols(matching: String) -> [SymbolOccurrence] {
    // Ignore short queries since they are:
    // - noisy and slow, since they can match many symbols
    // - normally unintentional, triggered when the user types slowly or if the editor doesn't
    //   debounce events while the user is typing
    guard matching.count >= minWorkspaceSymbolPatternLength else {
      return []
    }
    var symbolOccurenceResults: [SymbolOccurrence] = []
    for workspace in workspaces {
      workspace.index?.forEachCanonicalSymbolOccurrence(
        containing: matching,
        anchorStart: false,
        anchorEnd: false,
        subsequence: true,
        ignoreCase: true
      ) { symbol in
        guard !symbol.location.isSystem && !symbol.roles.contains(.accessorOf) else {
          return true
        }
        symbolOccurenceResults.append(symbol)
        // FIXME: Once we have cancellation support, we should fetch all results and take the top
        // `maxWorkspaceSymbolResults` symbols but bail if cancelled.
        //
        // Until then, take the first `maxWorkspaceSymbolResults` symbols to limit the impact of
        // queries which match many symbols.
        return symbolOccurenceResults.count < maxWorkspaceSymbolResults
      }
    }
    return symbolOccurenceResults
  }

  /// Handle a workspace/symbol request, returning the SymbolInformation.
  /// - returns: An array with SymbolInformation for each matching symbol in the workspace.
  func workspaceSymbols(_ req: Request<WorkspaceSymbolsRequest>) {
    let symbols = findWorkspaceSymbols(
      matching: req.params.query
    ).map({symbolOccurrence -> WorkspaceSymbolItem in
      let symbolPosition = Position(
        line: symbolOccurrence.location.line - 1, // 1-based -> 0-based
        // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
        utf16index: symbolOccurrence.location.utf8Column - 1)

      let symbolLocation = Location(
        uri: DocumentURI(URL(fileURLWithPath: symbolOccurrence.location.path)),
        range: Range(symbolPosition))

      return .symbolInformation(SymbolInformation(
        name: symbolOccurrence.symbol.name,
        kind: symbolOccurrence.symbol.kind.asLspSymbolKind(),
        deprecated: nil,
        location: symbolLocation,
        containerName: symbolOccurrence.getContainerName()
      ))
    })
    req.reply(symbols)
  }

  /// Forwards a SymbolInfoRequest to the appropriate toolchain service for this document.
  func symbolInfo(
    _ req: Request<SymbolInfoRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.symbolInfo(req)
  }

  func documentSymbolHighlight(
    _ req: Request<DocumentHighlightRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentSymbolHighlight(req)
  }

  func foldingRange(
    _ req: FoldingRangeRequest,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async throws -> [FoldingRange]? {
    return try await languageService.foldingRange(req)
  }

  func documentSymbol(
    _ req: Request<DocumentSymbolRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentSymbol(req)
  }

  func documentColor(
    _ req: Request<DocumentColorRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentColor(req)
  }

  func documentSemanticTokens(
    _ req: Request<DocumentSemanticTokensRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentSemanticTokens(req)
  }

  func documentSemanticTokensDelta(
    _ req: Request<DocumentSemanticTokensDeltaRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentSemanticTokensDelta(req)
  }

  func documentSemanticTokensRange(
    _ req: Request<DocumentSemanticTokensRangeRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentSemanticTokensRange(req)
  }

  func colorPresentation(
    _ req: Request<ColorPresentationRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.colorPresentation(req)
  }

  func executeCommand(_ req: Request<ExecuteCommandRequest>) async {
    guard let uri = req.params.textDocument?.uri else {
      log("attempted to perform executeCommand request without an url!", level: .error)
      req.reply(nil)
      return
    }
    guard let workspace = await workspaceForDocument(uri: uri) else {
      req.reply(.failure(.workspaceNotOpen(uri)))
      return
    }
    guard let languageService = workspace.documentService[uri] else {
      req.reply(nil)
      return
    }

    let params = req.params
    let executeCommand = ExecuteCommandRequest(command: params.command,
                                               arguments: params.argumentsWithoutSourceKitMetadata)
    let callback = { (result: Result<ExecuteCommandRequest.Response, ResponseError>) in
      req.reply(result)
    }
    let request = Request(executeCommand, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    await languageService.executeCommand(request)
  }

  func codeAction(
    _ req: CodeActionRequest,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async throws -> CodeActionRequestResponse? {
    let response = try await languageService.codeAction(req)
    return req.injectMetadata(toResponse: response)
  }

  func inlayHint(
    _ req: Request<InlayHintRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.inlayHint(req)
  }

  func documentDiagnostic(
    _ req: Request<DocumentDiagnosticsRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    await languageService.documentDiagnostic(req)
  }

  /// Converts a location from the symbol index to an LSP location.
  /// 
  /// - Parameter location: The symbol index location
  /// - Returns: The LSP location
  private func indexToLSPLocation(_ location: SymbolLocation) -> Location? {
    guard !location.path.isEmpty else { return nil }
    return Location(
      uri: DocumentURI(URL(fileURLWithPath: location.path)),
      range: Range(Position(
        // 1-based -> 0-based
        // Note that we still use max(0, ...) as a fallback if the location is zero.
        line: max(0, location.line - 1),
        // FIXME: we need to convert the utf8/utf16 column, which may require reading the file!
        utf16index: max(0, location.utf8Column - 1)
      ))
    )
  }

  /// Extracts the locations of an indexed symbol's occurrences,
  /// e.g. for definition or reference lookups.
  /// 
  /// - Parameters:
  ///   - result: The symbol to look up
  ///   - index: The index in which the occurrences will be looked up
  ///   - useLocalFallback: Whether to consider the best known local declaration if no other locations are found
  ///   - extractOccurrences: A function fetching the occurrences by the desired roles given a usr from the index
  /// - Returns: The resolved symbol locations
  private func extractIndexedOccurrences(
    result: LSPResult<SymbolInfoRequest.Response>,
    index: IndexStoreDB?,
    useLocalFallback: Bool = false,
    extractOccurrences: (String, IndexStoreDB) -> [SymbolOccurrence]
  ) -> LSPResult<[(occurrence: SymbolOccurrence?, location: Location)]> {
    guard case .success(let symbols) = result else {
      return .failure(result.failure!)
    }

    guard let symbol = symbols.first else {
      return .success([])
    }

    let fallback: [(occurrence: SymbolOccurrence?, location: Location)]
    if useLocalFallback, let bestLocalDeclaration = symbol.bestLocalDeclaration {
      fallback = [(occurrence: nil, location: bestLocalDeclaration)]
    } else {
      fallback = []
    }

    guard let usr = symbol.usr, let index = index else {
      return .success(fallback)
    }

    let occurs = extractOccurrences(usr, index)
    let resolved = occurs.compactMap { occur in
      indexToLSPLocation(occur.location).map {
        (occurrence: occur, location: $0)
      }
    }

    return .success(resolved.isEmpty ? fallback : resolved)
  }

  func declaration(
    _ req: Request<DeclarationRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    guard await languageService.declaration(req) else {
      return req.reply(.locations([]))
    }
  }

  func definition(
    _ req: Request<DefinitionRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let index = await self.workspaceForDocument(uri: req.params.textDocument.uri)?.index
    let callback = { (result: LSPResult<SymbolInfoRequest.Response>) -> Void in
      Task {
        // If this symbol is a module then generate a textual interface
        if case .success(let symbols) = result, let symbol = symbols.first, symbol.kind == .module, let name = symbol.name {
          await self.respondWithInterface(req, moduleName: name, symbolUSR: nil, languageService: languageService)
          return
        }

        let extractedResult = self.extractIndexedOccurrences(result: result, index: index, useLocalFallback: true) { (usr, index) in
          log("performing indexed jump-to-def with usr \(usr)")
          var occurs = index.occurrences(ofUSR: usr, roles: [.definition])
          if occurs.isEmpty {
            occurs = index.occurrences(ofUSR: usr, roles: [.declaration])
          }
          return occurs
        }

        switch extractedResult {
        case .success(let resolved):
          // if first resolved location is in `.swiftinterface` file. Use moduleName to return
          // textual interface
          if let firstResolved = resolved.first,
             let moduleName = firstResolved.occurrence?.location.moduleName,
             firstResolved.location.uri.fileURL?.pathExtension == "swiftinterface" {
            await self.respondWithInterface(
              req,
              moduleName: moduleName,
              symbolUSR: firstResolved.occurrence?.symbol.usr,
              languageService: languageService
            )
            return
          }
          let locs = resolved.map(\.location)
          // If we're unable to handle the definition request using our index, see if the
          // language service can handle it (e.g. clangd can provide AST based definitions).
          guard locs.isEmpty else {
            req.reply(.locations(locs))
            return
          }
          let handled = await languageService.definition(req)
          guard !handled else { return }
          req.reply(.locations([]))
        case .failure(let error):
          req.reply(.failure(error))
        }
      }
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    await languageService.symbolInfo(request)
  }

  func respondWithInterface(
    _ req: Request<DefinitionRequest>,
    moduleName: String,
    symbolUSR: String?,
    languageService: ToolchainLanguageServer
  ) async {
      let openInterface = OpenInterfaceRequest(textDocument: req.params.textDocument, name: moduleName, symbolUSR: symbolUSR)
      let request = Request(openInterface, id: req.id, clientID: ObjectIdentifier(self),
                            cancellation: req.cancellationToken, reply: { (result: Result<OpenInterfaceRequest.Response, ResponseError>) in
        switch result {
        case .success(let interfaceDetails?):
          let position = interfaceDetails.position ?? Position(line: 0, utf16index: 0)
          let loc = Location(uri: interfaceDetails.uri, range: Range(position))
          req.reply(.locations([loc]))
        case .success(nil):
          req.reply(.failure(.unknown("Could not generate Swift Interface for \(moduleName)")))
        case .failure(let error):
          req.reply(.failure(error))
        }
      })
      await languageService.openInterface(request)
  }

  func implementation(
    _ req: Request<ImplementationRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let index = await self.workspaceForDocument(uri: req.params.textDocument.uri)?.index
    let callback = { (result: LSPResult<SymbolInfoRequest.Response>) in
      let extractedResult = self.extractIndexedOccurrences(result: result, index: index) { (usr, index) in
        var occurs = index.occurrences(ofUSR: usr, roles: .baseOf)
        if occurs.isEmpty {
          occurs = index.occurrences(relatedToUSR: usr, roles: .overrideOf)
        }
        return occurs
      }

      req.reply(extractedResult.map { .locations($0.map(\.location)) })
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    await languageService.symbolInfo(request)
  }

  func references(
    _ req: Request<ReferencesRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let index = await self.workspaceForDocument(uri: req.params.textDocument.uri)?.index
    let callback = { (result: LSPResult<SymbolInfoRequest.Response>) in
      let extractedResult = self.extractIndexedOccurrences(result: result, index: index) { (usr, index) in
        log("performing indexed jump-to-def with usr \(usr)")
        var roles: SymbolRole = [.reference]
        if req.params.context.includeDeclaration {
          roles.formUnion([.declaration, .definition])
        }
        return index.occurrences(ofUSR: usr, roles: roles)
      }

      req.reply(extractedResult.map { $0.map(\.location) })
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    await languageService.symbolInfo(request)
  }

  private func indexToLSPCallHierarchyItem(
    symbol: Symbol,
    moduleName: String?,
    location: Location
  ) -> CallHierarchyItem {
    CallHierarchyItem(
      name: symbol.name,
      kind: symbol.kind.asLspSymbolKind(),
      tags: nil,
      detail: moduleName,
      uri: location.uri,
      range: location.range,
      selectionRange: location.range,
      // We encode usr and uri for incoming/outgoing call lookups in the implementation-specific data field
      data: .dictionary([
        "usr": .string(symbol.usr),
        "uri": .string(location.uri.stringValue),
      ])
    )
  }

  func prepareCallHierarchy(
    _ req: Request<CallHierarchyPrepareRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    let index = await self.workspaceForDocument(uri: req.params.textDocument.uri)?.index
    let callback = { (result: LSPResult<SymbolInfoRequest.Response>) in
      // For call hierarchy preparation we only locate the definition
      let extractedResult = self.extractIndexedOccurrences(result: result, index: index) { (usr, index) in
        index.occurrences(ofUSR: usr, roles: [.definition, .declaration])
      }
      let items = extractedResult.map { resolved -> [CallHierarchyItem]? in
        resolved.compactMap { info -> CallHierarchyItem? in
          guard let occurrence = info.occurrence else {
            return nil
          }
          let symbol = occurrence.symbol
          return self.indexToLSPCallHierarchyItem(
            symbol: symbol,
            moduleName: occurrence.location.moduleName,
            location: info.location
          )
        }
      }
      req.reply(items)
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    await languageService.symbolInfo(request)
  }

  /// Extracts our implementation-specific data about a call hierarchy
  /// item as encoded in `indexToLSPCallHierarchyItem`.
  /// 
  /// - Parameter data: The opaque data structure to extract
  /// - Returns: The extracted data if successful or nil otherwise
  private nonisolated func extractCallHierarchyItemData(_ rawData: LSPAny?) -> (uri: DocumentURI, usr: String)? {
    guard case let .dictionary(data) = rawData,
          case let .string(uriString) = data["uri"],
          case let .string(usr) = data["usr"] else {
      return nil
    }
    return (
      uri: DocumentURI(string: uriString),
      usr: usr
    )
  }

  func incomingCalls(_ req: Request<CallHierarchyIncomingCallsRequest>) async {
    guard let data = extractCallHierarchyItemData(req.params.item.data),
          let index = await self.workspaceForDocument(uri: data.uri)?.index else {
      req.reply([])
      return
    }
    let occurs = index.occurrences(ofUSR: data.usr, roles: .calledBy)
    let calls = occurs.compactMap { occurrence -> CallHierarchyIncomingCall? in
      guard let location = indexToLSPLocation(occurrence.location),
            let related = occurrence.relations.first else {
        return nil
      }

      // Resolve the caller's definition to find its location
      let definition = index.occurrences(ofUSR: related.symbol.usr, roles: [.definition, .declaration]).first
      let definitionSymbolLocation = definition?.location
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation)

      return CallHierarchyIncomingCall(
        from: indexToLSPCallHierarchyItem(
          symbol: related.symbol,
          moduleName: definitionSymbolLocation?.moduleName,
          location: definitionLocation ?? location // Use occurrence location as fallback
        ),
        fromRanges: [location.range]
      )
    }
    req.reply(calls)
  }

  func outgoingCalls(_ req: Request<CallHierarchyOutgoingCallsRequest>) async {
    guard let data = extractCallHierarchyItemData(req.params.item.data),
          let index = await self.workspaceForDocument(uri: data.uri)?.index else {
      req.reply([])
      return
    }
    let occurs = index.occurrences(relatedToUSR: data.usr, roles: .calledBy)
    let calls = occurs.compactMap { occurrence -> CallHierarchyOutgoingCall? in
      guard let location = indexToLSPLocation(occurrence.location) else {
        return nil
      }

      // Resolve the callee's definition to find its location
      let definition = index.occurrences(ofUSR: occurrence.symbol.usr, roles: [.definition, .declaration]).first
      let definitionSymbolLocation = definition?.location
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation)

      return CallHierarchyOutgoingCall(
        to: indexToLSPCallHierarchyItem(
          symbol: occurrence.symbol,
          moduleName: definitionSymbolLocation?.moduleName,
          location: definitionLocation ?? location // Use occurrence location as fallback
        ),
        fromRanges: [location.range]
      )
    }
    req.reply(calls)
  }

  private func indexToLSPTypeHierarchyItem(
    symbol: Symbol,
    moduleName: String?,
    location: Location,
    index: IndexStoreDB
  ) -> TypeHierarchyItem {
    let name: String
    let detail: String?

    switch symbol.kind {
    case .extension:
      // Query the conformance added by this extension
      let conformances = index.occurrences(relatedToUSR: symbol.usr, roles: .baseOf)
      if conformances.isEmpty {
        name = symbol.name
      } else {
        name = "\(symbol.name): \(conformances.map(\.symbol.name).joined(separator: ", "))"
      }
      // Add the file name and line to the detail string
      if 
        let url = location.uri.fileURL, 
        let basename = (try? AbsolutePath(validating: url.path))?.basename 
      {
        detail = "Extension at \(basename):\(location.range.lowerBound.line + 1)"
      } else if let moduleName = moduleName {
        detail = "Extension in \(moduleName)"
      } else {
        detail = "Extension"
      }
    default:
      name = symbol.name
      detail = moduleName
    }

    return TypeHierarchyItem(
      name: name,
      kind: symbol.kind.asLspSymbolKind(),
      tags: nil,
      detail: detail,
      uri: location.uri,
      range: location.range,
      selectionRange: location.range,
      // We encode usr and uri for incoming/outgoing type lookups in the implementation-specific data field
      data: .dictionary([
        "usr": .string(symbol.usr),
        "uri": .string(location.uri.stringValue),
      ])
    )
  }

  func prepareTypeHierarchy(
    _ req: Request<TypeHierarchyPrepareRequest>,
    workspace: Workspace,
    languageService: ToolchainLanguageServer
  ) async {
    let symbolInfo = SymbolInfoRequest(textDocument: req.params.textDocument, position: req.params.position)
    guard let index = await self.workspaceForDocument(uri: req.params.textDocument.uri)?.index else {
      req.reply([])
      return
    }
    let callback = { (result: LSPResult<SymbolInfoRequest.Response>) in
      // For type hierarchy preparation we only locate the definition
      let extractedResult = self.extractIndexedOccurrences(result: result, index: index) { (usr, index) in
        index.occurrences(ofUSR: usr, roles: [.definition, .declaration])
      }
      let items = extractedResult.map { resolved -> [TypeHierarchyItem]? in
        resolved.compactMap { info -> TypeHierarchyItem? in
          guard let occurrence = info.occurrence else {
            return nil
          }
          let symbol = occurrence.symbol
          return self.indexToLSPTypeHierarchyItem(
            symbol: symbol,
            moduleName: occurrence.location.moduleName,
            location: info.location,
            index: index
          )
        }
      }
      req.reply(items)
    }
    let request = Request(symbolInfo, id: req.id, clientID: ObjectIdentifier(self),
                          cancellation: req.cancellationToken, reply: callback)
    await languageService.symbolInfo(request)
  }

  /// Extracts our implementation-specific data about a type hierarchy
  /// item as encoded in `indexToLSPTypeHierarchyItem`.
  /// 
  /// - Parameter data: The opaque data structure to extract
  /// - Returns: The extracted data if successful or nil otherwise
  private nonisolated func extractTypeHierarchyItemData(_ rawData: LSPAny?) -> (uri: DocumentURI, usr: String)? {
    guard case let .dictionary(data) = rawData,
          case let .string(uriString) = data["uri"],
          case let .string(usr) = data["usr"] else {
      return nil
    }
    return (
      uri: DocumentURI(string: uriString),
      usr: usr
    )
  }

  func supertypes(_ req: Request<TypeHierarchySupertypesRequest>) async {
    guard let data = extractTypeHierarchyItemData(req.params.item.data),
          let index = await self.workspaceForDocument(uri: data.uri)?.index else {
      req.reply([])
      return
    }

    // Resolve base types
    let baseOccurs = index.occurrences(relatedToUSR: data.usr, roles: .baseOf)

    // Resolve retroactive conformances via the extensions
    let extensions = index.occurrences(ofUSR: data.usr, roles: .extendedBy)
    let retroactiveConformanceOccurs = extensions.flatMap { occurrence -> [SymbolOccurrence] in
      guard let related = occurrence.relations.first else {
        return []
      }
      return index.occurrences(relatedToUSR: related.symbol.usr, roles: .baseOf)
    }

    // Convert occurrences to type hierarchy items
    let occurs = baseOccurs + retroactiveConformanceOccurs
    let types = occurs.compactMap { occurrence -> TypeHierarchyItem? in
      guard let location = indexToLSPLocation(occurrence.location) else {
        return nil
      }

      // Resolve the supertype's definition to find its location
      let definition = index.occurrences(ofUSR: occurrence.symbol.usr, roles: [.definition, .declaration]).first
      let definitionSymbolLocation = definition?.location
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation)

      return indexToLSPTypeHierarchyItem(
        symbol: occurrence.symbol,
        moduleName: definitionSymbolLocation?.moduleName,
        location: definitionLocation ?? location, // Use occurrence location as fallback
        index: index
      )
    }
    req.reply(types)
  }

  func subtypes(_ req: Request<TypeHierarchySubtypesRequest>) async {
    guard let data = extractTypeHierarchyItemData(req.params.item.data),
          let index = await self.workspaceForDocument(uri: data.uri)?.index else {
      req.reply([])
      return
    }

    // Resolve child types and extensions
    let occurs = index.occurrences(ofUSR: data.usr, roles: [.baseOf, .extendedBy])

    // Convert occurrences to type hierarchy items
    let types = occurs.compactMap { occurrence -> TypeHierarchyItem? in
      guard let location = indexToLSPLocation(occurrence.location),
            let related = occurrence.relations.first else {
        return nil
      }

      // Resolve the subtype's definition to find its location
      let definition = index.occurrences(ofUSR: related.symbol.usr, roles: [.definition, .declaration]).first
      let definitionSymbolLocation = definition.map(\.location)
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation)

      return indexToLSPTypeHierarchyItem(
        symbol: related.symbol,
        moduleName: definitionSymbolLocation?.moduleName,
        location: definitionLocation ?? location, // Use occurrence location as fallback
        index: index
      )
    }
    req.reply(types)
  }

  func pollIndex(_ req: Request<PollIndexRequest>) {
    for workspace in workspaces {
      workspace.index?.pollForUnitChangesAndWait()
    }
    req.reply(VoidResponse())
  }
}

private func languageClass(for language: Language) -> [Language] {
  switch language {
  case .c, .cpp, .objective_c, .objective_cpp:
    return [.c, .cpp, .objective_c, .objective_cpp]
  case .swift:
    return [.swift]
  default:
    return [language]
  }
}

/// Minimum supported pattern length for a `workspace/symbol` request, smaller pattern
/// strings are not queried and instead we return no results.
private let minWorkspaceSymbolPatternLength = 3

/// The maximum number of results to return from a `workspace/symbol` request.
private let maxWorkspaceSymbolResults = 4096

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

/// Simple struct for pending notifications/requests, including a cancellation handler.
/// For convenience the notifications/request handlers are type erased via wrapping.
fileprivate struct NotificationRequestOperation {
  let operation: () async -> Void
  let cancellationHandler: (() -> Void)?
}

/// Used to queue up notifications and requests for documents which are blocked
/// on `BuildSystem` operations such as fetching build settings.
///
/// Note: This is not thread safe. Must be called from the `SourceKitServer.queue`.
fileprivate struct DocumentNotificationRequestQueue {
  fileprivate var queue = [NotificationRequestOperation]()

  /// Add an operation to the end of the queue.
  mutating func add(operation: @escaping () async -> Void, cancellationHandler: (() -> Void)? = nil) {
    queue.append(NotificationRequestOperation(operation: operation, cancellationHandler: cancellationHandler))
  }

  /// Cancel all operations in the queue. No-op for operations without a cancellation
  /// handler.
  mutating func cancelAll() {
    for task in queue {
      if let cancellationHandler = task.cancellationHandler {
        cancellationHandler()
      }
    }
    queue = []
  }
}
