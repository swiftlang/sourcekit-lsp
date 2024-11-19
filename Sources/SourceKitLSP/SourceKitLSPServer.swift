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
import BuildServerProtocol
import BuildSystemIntegration
import Dispatch
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
package import LanguageServerProtocolExtensions
import LanguageServerProtocolJSONRPC
import PackageLoading
import SKLogging
package import SKOptions
import SemanticIndex
import SourceKitD
package import SwiftExtensions
package import ToolchainRegistry

import struct PackageModel.BuildFlags
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
#else
import BuildServerProtocol
import BuildSystemIntegration
import Dispatch
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import LanguageServerProtocolJSONRPC
import PackageLoading
import SKLogging
import SKOptions
import SemanticIndex
import SourceKitD
import SwiftExtensions
import ToolchainRegistry

import struct PackageModel.BuildFlags
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
#endif

/// Disambiguate LanguageServerProtocol.Language and IndexstoreDB.Language
package typealias Language = LanguageServerProtocol.Language

/// The SourceKit-LSP server.
///
/// This is the client-facing language server implementation, providing indexing, multiple-toolchain
/// and cross-language support. Requests may be dispatched to language-specific services or handled
/// centrally, but this is transparent to the client.
package actor SourceKitLSPServer {
  package let messageHandlingHelper = QueueBasedMessageHandlerHelper(
    signpostLoggingCategory: "message-handling",
    createLoggingScope: true
  )

  package let messageHandlingQueue = AsyncQueue<MessageHandlingDependencyTracker>()

  /// The queue on which we keep track of `inProgressTextDocumentRequests` to ensure updates to
  /// `inProgressTextDocumentRequests` are handled in order.
  package let textDocumentTrackingQueue = AsyncQueue<Serial>()

  /// The queue on which all modifications of `workspaceForUri` happen. This means that the value of
  /// `workspacesAndIsImplicit` and `workspaceForUri` can't change while executing a closure on `workspaceQueue`.
  private let workspaceQueue = AsyncQueue<Serial>()

  /// The connection to the editor.
  package let client: Connection

  /// Set to `true` after the `SourceKitLSPServer` has send the reply to the `InitializeRequest`.
  ///
  /// Initialization can be awaited using `waitUntilInitialized`.
  private var initialized: Bool = false

  /// Set to `true` after the user has opened a project that doesn't support background indexing while having background
  /// indexing enabled.
  ///
  /// This ensures that we only inform the user about background indexing not being supported for these projects once.
  private var didSendBackgroundIndexingNotSupportedNotification = false

  var options: SourceKitLSPOptions

  let testHooks: TestHooks

  let toolchainRegistry: ToolchainRegistry

  package var capabilityRegistry: CapabilityRegistry?

  var languageServices: [LanguageServerType: [LanguageService]] = [:]

  package let documentManager = DocumentManager()

  /// The `TaskScheduler` that schedules all background indexing tasks.
  ///
  /// Shared process-wide to ensure the scheduled index operations across multiple workspaces don't exceed the maximum
  /// number of processor cores that the user allocated to background indexing.
  private let indexTaskScheduler: TaskScheduler<AnyIndexTaskDescription>

  /// Implicitly unwrapped optional so we can create an `IndexProgressManager` that has a weak reference to
  /// `SourceKitLSPServer`.
  /// `nonisolated(unsafe)` because `indexProgressManager` will not be modified after it is assigned from the
  /// initializer.
  private(set) nonisolated(unsafe) var indexProgressManager: IndexProgressManager!

  /// Implicitly unwrapped optional so we can create an `SharedWorkDoneProgressManager` that has a weak reference to
  /// `SourceKitLSPServer`.
  /// `nonisolated(unsafe)` because `sourcekitdCrashedWorkDoneProgress` will not be modified after it is assigned from
  /// the initializer.
  nonisolated(unsafe) var sourcekitdCrashedWorkDoneProgress: SharedWorkDoneProgressManager!

  /// Stores which workspace the given URI has been opened in.
  ///
  /// - Important: Must only be modified from `workspaceQueue`. This means that the value of `workspaceForUri`
  ///   can't change while executing an operation on `workspaceQueue`.
  private var workspaceForUri: [DocumentURI: WeakWorkspace] = [:]

  /// The open workspaces.
  ///
  /// Implicit workspaces are workspaces that weren't actually specified by the client during initialization or by a
  /// `didChangeWorkspaceFolders` request. Instead, they were opened by sourcekit-lsp because a file could not be
  /// handled by any of the open workspaces but one of the file's parent directories had handling capabilities for it.
  ///
  /// - Important: Must only be modified from `workspaceQueue`. This means that the value of `workspacesAndIsImplicit`
  ///   can't change while executing an operation on `workspaceQueue`.
  private var workspacesAndIsImplicit: [(workspace: Workspace, isImplicit: Bool)] = [] {
    didSet {
      self.scheduleUpdateOfUriToWorkspace()
    }
  }

  var workspaces: [Workspace] {
    return workspacesAndIsImplicit.map(\.workspace)
  }

  package func setWorkspaces(_ newValue: [(workspace: Workspace, isImplicit: Bool)]) {
    workspaceQueue.async {
      self.workspacesAndIsImplicit = newValue
    }
  }

  /// For all currently handled text document requests a mapping from the document to the corresponding request ID.
  private var inProgressTextDocumentRequests: [DocumentURI: Set<RequestID>] = [:]

  var onExit: () -> Void

  /// The files that we asked the client to watch.
  private var watchers: Set<FileSystemWatcher> = []

  /// Creates a language server for the given client.
  package init(
    client: Connection,
    toolchainRegistry: ToolchainRegistry,
    options: SourceKitLSPOptions,
    testHooks: TestHooks,
    onExit: @escaping () -> Void = {}
  ) {
    self.toolchainRegistry = toolchainRegistry
    self.options = options
    self.testHooks = testHooks
    self.onExit = onExit

    self.client = client
    let processorCount = ProcessInfo.processInfo.processorCount
    let lowPriorityCores =
      options.indexOrDefault.maxCoresPercentageToUseForBackgroundIndexingOrDefault * Double(processorCount)
    self.indexTaskScheduler = TaskScheduler(maxConcurrentTasksByPriority: [
      (TaskPriority.medium, processorCount),
      (TaskPriority.low, max(Int(lowPriorityCores), 1)),
    ])
    self.indexProgressManager = nil
    self.indexProgressManager = IndexProgressManager(sourceKitLSPServer: self)
    self.sourcekitdCrashedWorkDoneProgress = SharedWorkDoneProgressManager(
      sourceKitLSPServer: self,
      tokenPrefix: "sourcekitd-crashed",
      title: "SourceKit-LSP: Restoring functionality",
      message: "Please run 'sourcekit-lsp diagnose' to file an issue"
    )
  }

  /// Await until the server has send the reply to the initialize request.
  package func waitUntilInitialized() async {
    // The polling of `initialized` is not perfect but it should be OK, because
    //  - In almost all cases the server should already be initialized.
    //  - If it's not initialized, we expect initialization to finish fairly quickly. Even if initialization takes 5s
    //    this only results in 50 polls, which is acceptable.
    // Alternative solutions that signal via an async sequence seem overkill here.
    while !initialized {
      do {
        try await Task.sleep(for: .seconds(0.1))
      } catch {
        break
      }
    }
  }

  /// Search through all the parent directories of `uri` and check if any of these directories contain a workspace with
  /// a build system.
  ///
  /// The search will not consider any directory that is not a child of any of the directories in `rootUris`. This
  /// prevents us from picking up a workspace that is outside of the folders that the user opened.
  private func findImplicitWorkspace(for uri: DocumentURI) async -> Workspace? {
    guard var url = uri.fileURL?.deletingLastPathComponent() else {
      return nil
    }
    let projectRoots = await self.workspacesAndIsImplicit.filter { !$0.isImplicit }.asyncCompactMap {
      await $0.workspace.buildSystemManager.projectRoot
    }
    let rootURLs = workspacesAndIsImplicit.filter { !$0.isImplicit }.compactMap { $0.workspace.rootUri?.fileURL }
    while url.pathComponents.count > 1 && rootURLs.contains(where: { $0.isPrefix(of: url) }) {
      defer {
        url.deleteLastPathComponent()
      }
      // Ignore workspaces that have the same project root as an existing workspace.
      // This might happen if there is an existing SwiftPM workspace that hasn't been reloaded after a new file
      // was added to it and thus currently doesn't know that it can handle that file. In that case, we shouldn't open
      // a new workspace for the same root. Instead, the existing workspace's build system needs to be reloaded.
      let uri = DocumentURI(url)
      guard let buildSystemSpec = determineBuildSystem(forWorkspaceFolder: uri, options: self.options) else {
        continue
      }
      guard !projectRoots.contains(buildSystemSpec.projectRoot) else {
        continue
      }
      guard
        let workspace = await orLog(
          "Creating workspace",
          { try await createWorkspace(workspaceFolder: uri, buildSystemSpec: buildSystemSpec) }
        )
      else {
        continue
      }
      return workspace
    }
    return nil
  }

  package func workspaceForDocument(uri: DocumentURI) async -> Workspace? {
    let uri = uri.primaryFile ?? uri
    if let cachedWorkspace = self.workspaceForUri[uri]?.value {
      return cachedWorkspace
    }

    return await self.workspaceQueue.async {
      await self.computeWorkspaceForDocument(uri: uri)
    }.valuePropagatingCancellation
  }

  /// This method must be executed on `workspaceQueue` to ensure that the file handling capabilities of the
  /// workspaces don't change during the computation. Otherwise, we could run into a race condition like the following:
  ///  1. We don't have an entry for file `a.swift` in `workspaceForUri` and start the computation
  ///  2. We find that the first workspace in `self.workspaces` can handle this file.
  ///  3. During the `await ... .fileHandlingCapability` for a second workspace the file handling capabilities for the
  ///    first workspace change, meaning it can no longer handle the document. This resets `workspaceForUri`
  ///    assuming that the URI to workspace relation will get re-computed.
  ///  4. But we then set `workspaceForUri[uri]` to the workspace found in step (2), caching an out-of-date result.
  ///
  /// Furthermore, the computation of the workspace for a URI can create a new implicit workspace, which modifies
  /// `workspacesAndIsImplicit` and which must only be modified on `workspaceQueue`.
  ///
  /// - Important: Must only be invoked from `workspaceQueue`.
  private func computeWorkspaceForDocument(uri: DocumentURI) async -> Workspace? {
    // Pick the workspace with the best FileHandlingCapability for this file.
    // If there is a tie, use the workspace that occurred first in the list.
    var bestWorkspace = await self.workspaces.asyncFirst {
      await !$0.buildSystemManager.targets(for: uri).isEmpty
    }
    if bestWorkspace == nil {
      // We weren't able to handle the document with any of the known workspaces. See if any of the document's parent
      // directories contain a workspace that might be able to handle the document
      if let workspace = await self.findImplicitWorkspace(for: uri) {
        logger.log("Opening implicit workspace at \(workspace.rootUri.forLogging) to handle \(uri.forLogging)")
        self.workspacesAndIsImplicit.append((workspace: workspace, isImplicit: true))
        bestWorkspace = workspace
      }
    }
    let workspace = bestWorkspace ?? self.workspaces.first
    self.workspaceForUri[uri] = WeakWorkspace(workspace)
    return workspace
  }

  /// Check that the entries in `workspaceForUri` are still up-to-date after workspaces might have changed.
  ///
  /// For any entries that are not up-to-date, close the document in the old workspace and open it in the new document.
  ///
  /// This method returns immediately and schedules the check in the background as a global configuration change.
  /// Requests may still be served by their old workspace until this configuration change is executed by
  /// `SourceKitLSPServer`.
  private func scheduleUpdateOfUriToWorkspace() {
    messageHandlingQueue.async(priority: .low, metadata: .globalConfigurationChange) {
      logger.info("Updating URI to workspace")
      // For each document that has moved to a different workspace, close it in
      // the old workspace and open it in the new workspace.
      for docUri in self.documentManager.openDocuments {
        await self.workspaceQueue.async {
          let oldWorkspace = self.workspaceForUri[docUri]?.value
          let newWorkspace = await self.computeWorkspaceForDocument(uri: docUri)
          guard newWorkspace !== oldWorkspace else {
            return  // Nothing to do, workspace didn't change for this document
          }
          guard let snapshot = try? self.documentManager.latestSnapshot(docUri) else {
            return
          }
          if let oldWorkspace = oldWorkspace {
            await self.closeDocument(
              DidCloseTextDocumentNotification(
                textDocument: TextDocumentIdentifier(docUri)
              ),
              workspace: oldWorkspace
            )
          }
          logger.info(
            "Changing workspace of \(docUri.forLogging) from \(oldWorkspace?.rootUri?.forLogging) to \(newWorkspace?.rootUri?.forLogging)"
          )
          self.workspaceForUri[docUri] = WeakWorkspace(newWorkspace)
          if let newWorkspace = newWorkspace {
            await self.openDocument(
              DidOpenTextDocumentNotification(
                textDocument: TextDocumentItem(
                  uri: docUri,
                  language: snapshot.language,
                  version: snapshot.version,
                  text: snapshot.text
                )
              ),
              workspace: newWorkspace
            )
          }
        }.valuePropagatingCancellation
      }
      // `indexProgressManager` iterates over all workspaces in the SourceKitLSPServer. Modifying workspaces might thus
      // update the index progress status.
      self.indexProgressManager.indexProgressStatusDidChange()
    }
  }

  /// Execute `notificationHandler` with the request as well as the workspace
  /// and language that handle this document.
  private func withLanguageServiceAndWorkspace<NotificationType: TextDocumentNotification>(
    for notification: NotificationType,
    notificationHandler: @escaping (NotificationType, LanguageService) async -> Void
  ) async {
    let doc = notification.textDocument.uri
    guard let workspace = await self.workspaceForDocument(uri: doc) else {
      return
    }

    // This should be created as soon as we receive an open call, even if the document
    // isn't yet ready.
    guard let languageService = workspace.documentService(for: doc) else {
      return
    }

    await notificationHandler(notification, languageService)
  }

  private func handleRequest<RequestType: TextDocumentRequest>(
    for request: RequestAndReply<RequestType>,
    requestHandler: @Sendable @escaping (
      RequestType, Workspace, LanguageService
    ) async throws ->
      RequestType.Response
  ) async {
    await request.reply {
      let request = request.params
      let doc = request.textDocument.uri
      guard let workspace = await self.workspaceForDocument(uri: request.textDocument.uri) else {
        throw ResponseError.workspaceNotOpen(request.textDocument.uri)
      }
      guard let languageService = workspace.documentService(for: doc) else {
        throw ResponseError.unknown("No language service for '\(request.textDocument.uri)' found")
      }
      return try await requestHandler(request, workspace, languageService)
    }
  }

  /// Send the given notification to the editor.
  package nonisolated func sendNotificationToClient(_ notification: some NotificationType) {
    client.send(notification)
  }

  /// Send the given request to the editor.
  package func sendRequestToClient<R: RequestType>(_ request: R) async throws -> R.Response {
    return try await client.send(request)
  }

  /// After the language service has crashed, send `DidOpenTextDocumentNotification`s to a newly instantiated language service for previously open documents.
  func reopenDocuments(for languageService: LanguageService) async {
    for documentUri in self.documentManager.openDocuments {
      guard let workspace = await self.workspaceForDocument(uri: documentUri) else {
        continue
      }
      guard workspace.documentService(for: documentUri) === languageService else {
        continue
      }
      guard let snapshot = try? self.documentManager.latestSnapshot(documentUri) else {
        // The document has been closed since we retrieved its URI. We don't care about it anymore.
        continue
      }

      // Close the document properly in the document manager and build system manager to start with a clean sheet when re-opening it.
      let closeNotification = DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(documentUri))
      await self.closeDocument(closeNotification, workspace: workspace)

      let textDocument = TextDocumentItem(
        uri: documentUri,
        language: snapshot.language,
        version: snapshot.version,
        text: snapshot.text
      )
      await self.openDocument(DidOpenTextDocumentNotification(textDocument: textDocument), workspace: workspace)
    }
  }

  /// If a language service of type `serverType` that can handle `workspace` has
  /// already been started, return it, otherwise return `nil`.
  private func existingLanguageService(
    _ serverType: LanguageServerType,
    workspace: Workspace
  ) -> LanguageService? {
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
  ) async -> LanguageService? {
    guard let serverType = LanguageServerType(language: language) else {
      return nil
    }
    // Pick the first language service that can handle this workspace.
    if let languageService = existingLanguageService(serverType, workspace: workspace) {
      return languageService
    }

    // Start a new service.
    return await orLog("failed to start language service", level: .error) { [options = workspace.options, testHooks] in
      let service = try await serverType.serverType.init(
        sourceKitLSPServer: self,
        toolchain: toolchain,
        options: options,
        testHooks: testHooks,
        workspace: workspace
      )

      guard let service else {
        return nil
      }

      let pid = Int(ProcessInfo.processInfo.processIdentifier)
      let resp = try await service.initialize(
        InitializeRequest(
          processId: pid,
          rootPath: nil,
          rootURI: workspace.rootUri,
          initializationOptions: nil,
          capabilities: workspace.capabilityRegistry.clientCapabilities,
          trace: .off,
          workspaceFolders: nil
        )
      )
      let languages = languageClass(for: language)
      await self.registerCapabilities(
        for: resp.capabilities,
        languages: languages,
        registry: workspace.capabilityRegistry
      )

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

  package func languageService(
    for uri: DocumentURI,
    _ language: Language,
    in workspace: Workspace
  ) async -> LanguageService? {
    if let service = workspace.documentService(for: uri) {
      return service
    }

    let toolchain = await workspace.buildSystemManager.toolchain(
      for: uri,
      in: workspace.buildSystemManager.canonicalTarget(for: uri),
      language: language
    )
    guard let toolchain else {
      logger.error("Failed to determine toolchain for \(uri)")
      return nil
    }
    guard let service = await languageService(for: toolchain, language, in: workspace) else {
      logger.error("Failed to create language service for \(uri)")
      return nil
    }

    logger.log(
      """
      Using toolchain at \(toolchain.path?.description ?? "<nil>") (\(toolchain.identifier, privacy: .public)) \
      for \(uri.forLogging)
      """
    )

    return workspace.setDocumentService(for: uri, service)
  }
}

// MARK: - MessageHandler

extension SourceKitLSPServer: QueueBasedMessageHandler {
  package nonisolated func didReceive(notification: some NotificationType) {
    let textDocumentUri: DocumentURI
    switch notification {
    case let params as DidChangeTextDocumentNotification:
      textDocumentUri = params.textDocument.uri
    case let params as DidCloseTextDocumentNotification:
      textDocumentUri = params.textDocument.uri
    default:
      return
    }
    textDocumentTrackingQueue.async(priority: .high) {
      await self.cancelTextDocumentRequests(for: textDocumentUri)
    }
  }

  /// Cancel all in-progress text document requests for the given document.
  ///
  /// As a user makes an edit to a file, these requests are most likely no longer relevant. It also makes sure that a
  /// long-running sourcekitd request can't block the entire language server if the client does not cancel all requests.
  /// For example, consider the following sequence of requests:
  ///  - `textDocument/semanticTokens/full` for document A
  ///  - `textDocument/didChange` for document A
  ///  - `textDocument/formatting` for document A
  ///
  /// If the editor is not cancelling the semantic tokens request on edit (like VS Code does), then the `didChange`
  /// notification is blocked on the semantic tokens request finishing. Hence, we also can't run the
  /// `textDocument/formatting` request. Cancelling the semantic tokens on the edit fixes the issue.
  ///
  /// This method is a no-op if `cancelTextDocumentRequestsOnEditAndClose` is disabled.
  ///
  /// - Important: Should be invoked on `textDocumentTrackingQueue` to ensure that new text document requests are
  ///   registered before a notification that triggers cancellation might come in.
  private func cancelTextDocumentRequests(for uri: DocumentURI) {
    guard self.options.cancelTextDocumentRequestsOnEditAndCloseOrDefault else {
      return
    }
    for requestID in self.inProgressTextDocumentRequests[uri, default: []] {
      logger.info("Implicitly cancelling request \(requestID)")
      self.messageHandlingHelper.cancelRequest(id: requestID)
    }
  }

  package func handle(notification: some NotificationType) async {
    logger.log("Received notification: \(notification.forLogging)")

    switch notification {
    case let notification as DidChangeTextDocumentNotification:
      await self.changeDocument(notification)
    case let notification as DidChangeWorkspaceFoldersNotification:
      await self.didChangeWorkspaceFolders(notification)
    case let notification as DidCloseTextDocumentNotification:
      await self.closeDocument(notification)
    case let notification as DidChangeWatchedFilesNotification:
      await self.didChangeWatchedFiles(notification)
    case let notification as DidOpenTextDocumentNotification:
      await self.openDocument(notification)
    case let notification as DidSaveTextDocumentNotification:
      await self.withLanguageServiceAndWorkspace(for: notification, notificationHandler: self.didSaveDocument)
    case let notification as InitializedNotification:
      self.clientInitialized(notification)
    case let notification as ExitNotification:
      await self.exit(notification)
    case let notification as ReopenTextDocumentNotification:
      await self.reopenDocument(notification)
    case let notification as WillSaveTextDocumentNotification:
      await self.withLanguageServiceAndWorkspace(for: notification, notificationHandler: self.willSaveDocument)
    // IMPORTANT: When adding a new entry to this switch, also add it to the `MessageHandlingDependencyTracker` initializer.
    default:
      break
    }
  }

  package nonisolated func didReceive(request: some RequestType, id: RequestID) {
    guard let request = request as? any TextDocumentRequest else {
      return
    }
    textDocumentTrackingQueue.async(priority: .background) {
      await self.registerInProgressTextDocumentRequest(request, id: id)
    }
  }

  /// - Important: Should be invoked on `textDocumentTrackingQueue` to ensure that new text document requests are
  ///   registered before a notification that triggers cancellation might come in.
  private func registerInProgressTextDocumentRequest(_ request: any TextDocumentRequest, id: RequestID) {
    self.inProgressTextDocumentRequests[request.textDocument.uri, default: []].insert(id)
  }

  package func handle<Request: RequestType>(
    request params: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) async {
    defer {
      if let request = params as? any TextDocumentRequest {
        self.inProgressTextDocumentRequests[request.textDocument.uri, default: []].remove(id)
      }
    }

    await self.testHooks.handleRequest?(params)

    let startDate = Date()

    let request = RequestAndReply(params) { result in
      reply(result)
      let endDate = Date()
      Task {
        switch result {
        case .success(let response):
          logger.log(
            """
            Succeeded (took \(endDate.timeIntervalSince(startDate) * 1000, privacy: .public)ms)
            \(Request.method, privacy: .public)
            \(response.forLogging)
            """
          )
        case .failure(let error):
          logger.log(
            """
            Failed (took \(endDate.timeIntervalSince(startDate) * 1000, privacy: .public)ms)
            \(Request.method, privacy: .public)(\(id, privacy: .public))
            \(error.forLogging, privacy: .private)
            """
          )
        }
      }
    }

    logger.log("Received request \(id): \(params.forLogging)")

    if let textDocumentRequest = params as? any TextDocumentRequest {
      // When we are requesting information from a document, poke preparation of its target. We don't want to wait for
      // the preparation to finish because that would cause too big a delay.
      // In practice, while the user is working on a file, we'll get a text document request for it on a regular basis,
      // which prepares the files. For files that are open but aren't being worked on (eg. a different tab), we don't
      // get requests, ensuring that we don't unnecessarily prepare them.
      let workspace = await self.workspaceForDocument(uri: textDocumentRequest.textDocument.uri)
      await workspace?.semanticIndexManager?.schedulePreparationForEditorFunctionality(
        of: textDocumentRequest.textDocument.uri
      )
    }

    switch request {
    case let request as RequestAndReply<BarrierRequest>:
      await request.reply { VoidResponse() }
    case let request as RequestAndReply<CallHierarchyIncomingCallsRequest>:
      await request.reply { try await incomingCalls(request.params) }
    case let request as RequestAndReply<CallHierarchyOutgoingCallsRequest>:
      await request.reply { try await outgoingCalls(request.params) }
    case let request as RequestAndReply<CallHierarchyPrepareRequest>:
      await self.handleRequest(for: request, requestHandler: self.prepareCallHierarchy)
    case let request as RequestAndReply<CodeActionRequest>:
      await self.handleRequest(for: request, requestHandler: self.codeAction)
    case let request as RequestAndReply<CodeLensRequest>:
      await self.handleRequest(for: request, requestHandler: self.codeLens)
    case let request as RequestAndReply<ColorPresentationRequest>:
      await self.handleRequest(for: request, requestHandler: self.colorPresentation)
    case let request as RequestAndReply<CompletionRequest>:
      await self.handleRequest(for: request, requestHandler: self.completion)
    case let request as RequestAndReply<DeclarationRequest>:
      await self.handleRequest(for: request, requestHandler: self.declaration)
    case let request as RequestAndReply<DefinitionRequest>:
      await self.handleRequest(for: request, requestHandler: self.definition)
    case let request as RequestAndReply<DocumentColorRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentColor)
    case let request as RequestAndReply<DocumentDiagnosticsRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentDiagnostic)
    case let request as RequestAndReply<DocumentFormattingRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentFormatting)
    case let request as RequestAndReply<DocumentRangeFormattingRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentRangeFormatting)
    case let request as RequestAndReply<DocumentHighlightRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentSymbolHighlight)
    case let request as RequestAndReply<DocumentSemanticTokensDeltaRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentSemanticTokensDelta)
    case let request as RequestAndReply<DocumentSemanticTokensRangeRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentSemanticTokensRange)
    case let request as RequestAndReply<DocumentSemanticTokensRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentSemanticTokens)
    case let request as RequestAndReply<DocumentSymbolRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentSymbol)
    case let request as RequestAndReply<DocumentTestsRequest>:
      await self.handleRequest(for: request, requestHandler: self.documentTests)
    case let request as RequestAndReply<ExecuteCommandRequest>:
      await request.reply { try await executeCommand(request.params) }
    case let request as RequestAndReply<FoldingRangeRequest>:
      await self.handleRequest(for: request, requestHandler: self.foldingRange)
    case let request as RequestAndReply<GetReferenceDocumentRequest>:
      await request.reply { try await getReferenceDocument(request.params) }
    case let request as RequestAndReply<HoverRequest>:
      await self.handleRequest(for: request, requestHandler: self.hover)
    case let request as RequestAndReply<ImplementationRequest>:
      await self.handleRequest(for: request, requestHandler: self.implementation)
    case let request as RequestAndReply<IndexedRenameRequest>:
      await self.handleRequest(for: request, requestHandler: self.indexedRename)
    case let request as RequestAndReply<InitializeRequest>:
      await request.reply { try await initialize(request.params) }
      // Only set `initialized` to `true` after we have sent the response to the initialize request to the client.
      initialized = true
    case let request as RequestAndReply<InlayHintRequest>:
      await self.handleRequest(for: request, requestHandler: self.inlayHint)
    case let request as RequestAndReply<PollIndexRequest>:
      await request.reply { try await pollIndex(request.params) }
    case let request as RequestAndReply<PrepareRenameRequest>:
      await self.handleRequest(for: request, requestHandler: self.prepareRename)
    case let request as RequestAndReply<ReferencesRequest>:
      await self.handleRequest(for: request, requestHandler: self.references)
    case let request as RequestAndReply<RenameRequest>:
      await request.reply { try await rename(request.params) }
    case let request as RequestAndReply<ShutdownRequest>:
      await request.reply { try await shutdown(request.params) }
    case let request as RequestAndReply<SymbolInfoRequest>:
      await self.handleRequest(for: request, requestHandler: self.symbolInfo)
    case let request as RequestAndReply<TriggerReindexRequest>:
      await request.reply { try await triggerReindex(request.params) }
    case let request as RequestAndReply<TypeHierarchyPrepareRequest>:
      await self.handleRequest(for: request, requestHandler: self.prepareTypeHierarchy)
    case let request as RequestAndReply<TypeHierarchySubtypesRequest>:
      await request.reply { try await subtypes(request.params) }
    case let request as RequestAndReply<TypeHierarchySupertypesRequest>:
      await request.reply { try await supertypes(request.params) }
    case let request as RequestAndReply<WorkspaceSymbolsRequest>:
      await request.reply { try await workspaceSymbols(request.params) }
    case let request as RequestAndReply<WorkspaceTestsRequest>:
      await request.reply { try await workspaceTests(request.params) }
    // IMPORTANT: When adding a new entry to this switch, also add it to the `MessageHandlingDependencyTracker` initializer.
    default:
      await request.reply { throw ResponseError.methodNotFound(Request.method) }
    }
  }
}

extension SourceKitLSPServer {
  nonisolated package func logMessageToIndexLog(taskID: String, message: String) {
    self.sendNotificationToClient(
      LogMessageNotification(
        type: .info,
        message: prefixMessageWithTaskEmoji(taskID: taskID, message: message),
        logName: "SourceKit-LSP: Indexing"
      )
    )
  }

  func fileHandlingCapabilityChanged() {
    logger.log("Scheduling update of URI to workspace because file handling capability of a workspace changed")
    self.scheduleUpdateOfUriToWorkspace()
  }
}

// MARK: - Request and notification handling

extension SourceKitLSPServer {

  // MARK: - General

  /// Creates a workspace at the given `uri`.
  ///
  /// If the build system that was determined for the workspace does not satisfy `condition`, `nil` is returned.
  private func createWorkspace(
    workspaceFolder: DocumentURI,
    buildSystemSpec: BuildSystemSpec?
  ) async throws -> Workspace {
    guard let capabilityRegistry = capabilityRegistry else {
      struct NoCapabilityRegistryError: Error {}
      logger.log("Cannot open workspace before server is initialized")
      throw NoCapabilityRegistryError()
    }
    let testHooks = self.testHooks
    let options = SourceKitLSPOptions.merging(
      base: self.options,
      override: SourceKitLSPOptions(
        path: workspaceFolder.fileURL?
          .appendingPathComponent(".sourcekit-lsp")
          .appendingPathComponent("config.json")
      )
    )
    logger.log("Creating workspace at \(workspaceFolder.forLogging) with options: \(options.forLogging)")
    logger.logFullObjectInMultipleLogMessages(header: "Options for workspace", options.loggingProxy)

    let workspace = await Workspace(
      sourceKitLSPServer: self,
      documentManager: self.documentManager,
      rootUri: workspaceFolder,
      capabilityRegistry: capabilityRegistry,
      buildSystemSpec: buildSystemSpec,
      toolchainRegistry: self.toolchainRegistry,
      options: options,
      testHooks: testHooks,
      indexTaskScheduler: indexTaskScheduler
    )
    if options.backgroundIndexingOrDefault, workspace.semanticIndexManager == nil,
      !self.didSendBackgroundIndexingNotSupportedNotification
    {
      self.sendNotificationToClient(
        ShowMessageNotification(
          type: .info,
          message: """
            Background indexing is currently only supported for SwiftPM projects. \
            For all other project types, please run a build to update the index.
            """
        )
      )
      self.didSendBackgroundIndexingNotSupportedNotification = true
    }
    return workspace
  }

  /// Determines the build system for the given workspace folder and creates a `Workspace` that uses this inferred build
  /// system.
  private func createWorkspaceWithInferredBuildSystem(workspaceFolder: DocumentURI) async throws -> Workspace {
    return try await self.createWorkspace(
      workspaceFolder: workspaceFolder,
      buildSystemSpec: determineBuildSystem(forWorkspaceFolder: workspaceFolder, options: self.options)
    )
  }

  func initialize(_ req: InitializeRequest) async throws -> InitializeResult {
    logger.logFullObjectInMultipleLogMessages(header: "Initialize request", AnyRequestType(request: req))
    // If the client can handle `PeekDocumentsRequest`, they can enable the
    // experimental client capability `"workspace/peekDocuments"` through the `req.capabilities.experimental`.
    //
    // The below is a workaround for the vscode-swift extension since it cannot set client capabilities.
    // It passes "workspace/peekDocuments" through the `initializationOptions`.
    //
    // Similarly, for "workspace/getReferenceDocument".
    var clientCapabilities = req.capabilities
    if case .dictionary(let initializationOptions) = req.initializationOptions {
      if let peekDocuments = initializationOptions["workspace/peekDocuments"] {
        if case .dictionary(var experimentalCapabilities) = clientCapabilities.experimental {
          experimentalCapabilities["workspace/peekDocuments"] = peekDocuments
          clientCapabilities.experimental = .dictionary(experimentalCapabilities)
        } else {
          clientCapabilities.experimental = .dictionary(["workspace/peekDocuments": peekDocuments])
        }
      }

      if let getReferenceDocument = initializationOptions["workspace/getReferenceDocument"] {
        if case .dictionary(var experimentalCapabilities) = clientCapabilities.experimental {
          experimentalCapabilities["workspace/getReferenceDocument"] = getReferenceDocument
          clientCapabilities.experimental = .dictionary(experimentalCapabilities)
        } else {
          clientCapabilities.experimental = .dictionary(["workspace/getReferenceDocument": getReferenceDocument])
        }
      }

      // The client announces what CodeLenses it supports, and the LSP will only return
      // ones found in the supportedCommands dictionary.
      if let codeLens = initializationOptions["textDocument/codeLens"],
        case let .dictionary(codeLensConfig) = codeLens,
        case let .dictionary(supportedCommands) = codeLensConfig["supportedCommands"]
      {
        let commandMap = supportedCommands.compactMap { (key, value) in
          if case let .string(clientCommand) = value {
            return (SupportedCodeLensCommand(rawValue: key), clientCommand)
          }
          return nil
        }

        clientCapabilities.textDocument?.codeLens?.supportedCommands = Dictionary(uniqueKeysWithValues: commandMap)
      }
    }

    capabilityRegistry = CapabilityRegistry(clientCapabilities: clientCapabilities)

    self.options = SourceKitLSPOptions.merging(
      base: self.options,
      override: orLog("Parsing SourceKitLSPOptions", { try SourceKitLSPOptions(fromLSPAny: req.initializationOptions) })
    )

    logger.log("Initialized SourceKit-LSP")
    logger.logFullObjectInMultipleLogMessages(header: "SourceKit-LSP Options", options.loggingProxy)

    await workspaceQueue.async { [testHooks] in
      if let workspaceFolders = req.workspaceFolders {
        self.workspacesAndIsImplicit += await workspaceFolders.asyncCompactMap { workspaceFolder in
          await orLog("Creating workspace from workspaceFolders") {
            return (
              workspace: try await self.createWorkspaceWithInferredBuildSystem(workspaceFolder: workspaceFolder.uri),
              isImplicit: false
            )
          }
        }
      } else if let uri = req.rootURI {
        await orLog("Creating workspace from rootURI") {
          self.workspacesAndIsImplicit.append(
            (workspace: try await self.createWorkspaceWithInferredBuildSystem(workspaceFolder: uri), isImplicit: false)
          )
        }
      } else if let path = req.rootPath {
        let uri = DocumentURI(URL(fileURLWithPath: path))
        await orLog("Creating workspace from rootPath") {
          self.workspacesAndIsImplicit.append(
            (workspace: try await self.createWorkspaceWithInferredBuildSystem(workspaceFolder: uri), isImplicit: false)
          )
        }
      }

      if self.workspaces.isEmpty {
        logger.error("No workspace found")

        let options = self.options
        let workspace = await Workspace(
          sourceKitLSPServer: self,
          documentManager: self.documentManager,
          rootUri: req.rootURI,
          capabilityRegistry: self.capabilityRegistry!,
          buildSystemSpec: nil,
          toolchainRegistry: self.toolchainRegistry,
          options: options,
          testHooks: testHooks,
          indexTaskScheduler: self.indexTaskScheduler
        )

        self.workspacesAndIsImplicit.append((workspace: workspace, isImplicit: false))
      }
    }.value

    assert(!self.workspaces.isEmpty)

    let result = InitializeResult(
      capabilities: await self.serverCapabilities(
        for: req.capabilities,
        registry: self.capabilityRegistry!
      )
    )
    logger.logFullObjectInMultipleLogMessages(header: "Initialize response", AnyRequestType(request: req))
    return result
  }

  func serverCapabilities(
    for client: ClientCapabilities,
    registry: CapabilityRegistry
  ) async -> ServerCapabilities {
    let completionOptions =
      await registry.clientHasDynamicCompletionRegistration
      ? nil
      : LanguageServerProtocol.CompletionOptions(
        resolveProvider: false,
        triggerCharacters: [".", "("]
      )

    let foldingRangeOptions =
      await registry.clientHasDynamicFoldingRangeRegistration
      ? nil
      : ValueOrBool<TextDocumentAndStaticRegistrationOptions>.bool(true)

    let inlayHintOptions =
      await registry.clientHasDynamicInlayHintRegistration
      ? nil
      : ValueOrBool.value(InlayHintOptions(resolveProvider: false))

    let semanticTokensOptions =
      await registry.clientHasDynamicSemanticTokensRegistration
      ? nil
      : SemanticTokensOptions(
        legend: SemanticTokensLegend.sourceKitLSPLegend,
        range: .bool(true),
        full: .bool(true)
      )

    let executeCommandOptions =
      await registry.clientHasDynamicExecuteCommandRegistration
      ? nil
      : ExecuteCommandOptions(commands: builtinSwiftCommands)

    return ServerCapabilities(
      textDocumentSync: .options(
        TextDocumentSyncOptions(
          openClose: true,
          change: .incremental
        )
      ),
      hoverProvider: .bool(true),
      completionProvider: completionOptions,
      definitionProvider: .bool(true),
      implementationProvider: .bool(true),
      referencesProvider: .bool(true),
      documentHighlightProvider: .bool(true),
      documentSymbolProvider: .bool(true),
      workspaceSymbolProvider: .bool(true),
      codeActionProvider: .value(
        CodeActionServerCapabilities(
          clientCapabilities: client.textDocument?.codeAction,
          codeActionOptions: CodeActionOptions(codeActionKinds: nil),
          supportsCodeActions: true
        )
      ),
      codeLensProvider: CodeLensOptions(),
      documentFormattingProvider: .value(DocumentFormattingOptions(workDoneProgress: false)),
      documentRangeFormattingProvider: .value(DocumentRangeFormattingOptions(workDoneProgress: false)),
      renameProvider: .value(RenameOptions(prepareProvider: true)),
      colorProvider: .bool(true),
      foldingRangeProvider: foldingRangeOptions,
      declarationProvider: .bool(true),
      executeCommandProvider: executeCommandOptions,
      workspace: WorkspaceServerCapabilities(
        workspaceFolders: .init(
          supported: true,
          changeNotifications: .bool(true)
        )
      ),
      callHierarchyProvider: .bool(true),
      typeHierarchyProvider: .bool(true),
      semanticTokensProvider: semanticTokensOptions,
      inlayHintProvider: inlayHintOptions,
      experimental: .dictionary([
        "workspace/tests": .dictionary(["version": .int(2)]),
        "textDocument/tests": .dictionary(["version": .int(2)]),
        "workspace/triggerReindex": .dictionary(["version": .int(1)]),
        "workspace/getReferenceDocument": .dictionary(["version": .int(1)]),
      ])
    )
  }

  func registerCapabilities(
    for server: ServerCapabilities,
    languages: [Language],
    registry: CapabilityRegistry
  ) async {
    // IMPORTANT: When adding new capabilities here, also add the value of that capability in `SwiftLanguageService`
    // to SourceKitLSPServer.serverCapabilities. That way the capabilities get registered for all languages in case the
    // client does not support dynamic capability registration.

    if let completionOptions = server.completionProvider {
      await registry.registerCompletionIfNeeded(options: completionOptions, for: languages, server: self)
    }
    if server.foldingRangeProvider?.isSupported == true {
      await registry.registerFoldingRangeIfNeeded(options: FoldingRangeOptions(), for: languages, server: self)
    }
    if let semanticTokensOptions = server.semanticTokensProvider {
      await registry.registerSemanticTokensIfNeeded(options: semanticTokensOptions, for: languages, server: self)
    }
    if let inlayHintProvider = server.inlayHintProvider, inlayHintProvider.isSupported {
      let options: InlayHintOptions
      switch inlayHintProvider {
      case .bool(true):
        options = InlayHintOptions()
      case .bool(false):
        return
      case .value(let opts):
        options = opts
      }
      await registry.registerInlayHintIfNeeded(options: options, for: languages, server: self)
    }
    // We use the registration for the diagnostics provider to decide whether to enable pull-diagnostics (see comment
    // on `CapabilityRegistry.clientSupportPullDiagnostics`.
    // Thus, we can't statically register this capability in the server options. We need the client's reply to decide
    // whether it supports pull diagnostics.
    if let diagnosticOptions = server.diagnosticProvider {
      await registry.registerDiagnosticIfNeeded(options: diagnosticOptions, for: languages, server: self)
    }
    if let commandOptions = server.executeCommandProvider {
      await registry.registerExecuteCommandIfNeeded(commands: commandOptions.commands, server: self)
    }
  }

  func clientInitialized(_: InitializedNotification) {
    // Nothing to do.
  }

  /// The server is about to exit, and the server should flush any buffered state.
  ///
  /// The server shall not be used to handle more requests (other than possibly
  /// `shutdown` and `exit`) and should attempt to flush any buffered state
  /// immediately, such as sending index changes to disk.
  package func prepareForExit() async {
    // Note: this method should be safe to call multiple times, since we want to
    // be resilient against multiple possible shutdown sequences, including
    // pipe failure.

    // Theoretically, new workspaces could be added while we are awaiting inside
    // the loop. But since we are currently exiting, it doesn't make sense for
    // the client to open new workspaces.
    for workspace in self.workspaces {
      await workspace.buildSystemManager.setMainFilesProvider(nil)
      workspace.closeIndex()
    }
  }

  func shutdown(_ request: ShutdownRequest) async throws -> VoidResponse {
    await prepareForExit()

    await withTaskGroup(of: Void.self) { taskGroup in
      for service in languageServices.values.flatMap({ $0 }) {
        taskGroup.addTask {
          await service.shutdown()
        }
      }
      for workspace in workspaces {
        taskGroup.addTask {
          await orLog("Shutting down build server") {
            // If the build server doesn't shut down in 1 second, don't delay SourceKit-LSP's shutdown because of it.
            try await withTimeout(.seconds(2)) {
              await workspace.buildSystemManager.shutdown()
            }
          }
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
    return VoidResponse()
  }

  func exit(_ notification: ExitNotification) async {
    // Should have been called in shutdown, but allow misbehaving clients.
    await prepareForExit()

    // Call onExit only once, and hop off queue to allow the handler to call us back.
    self.onExit()
  }

  /// Start watching for changes with the given patterns.
  func watchFiles(_ fileWatchers: [FileSystemWatcher]) async {
    await self.waitUntilInitialized()
    if fileWatchers.allSatisfy({ self.watchers.contains($0) }) {
      // All watchers already registered. Nothing to do.
      return
    }
    self.watchers.formUnion(fileWatchers)
    await self.capabilityRegistry?.registerDidChangeWatchedFiles(
      watchers: self.watchers.sorted { $0.globPattern < $1.globPattern },
      server: self
    )
  }

  // MARK: - Text synchronization

  func openDocument(_ notification: DidOpenTextDocumentNotification) async {
    let uri = notification.textDocument.uri
    guard let workspace = await workspaceForDocument(uri: uri) else {
      logger.error(
        "Received open notification for file '\(uri.forLogging)' without a corresponding workspace, ignoring..."
      )
      return
    }
    await workspace.semanticIndexManager?.schedulePreparationForEditorFunctionality(of: uri)
    await openDocument(notification, workspace: workspace)
  }

  private func openDocument(_ notification: DidOpenTextDocumentNotification, workspace: Workspace) async {
    // Immediately open the document even if the build system isn't ready. This is important since
    // we check that the document is open when we receive messages from the build system.
    let snapshot = orLog("Opening document") {
      try documentManager.open(
        notification.textDocument.uri,
        language: notification.textDocument.language,
        version: notification.textDocument.version,
        text: notification.textDocument.text
      )
    }
    guard let snapshot else {
      // Already logged failure
      return
    }

    let textDocument = notification.textDocument
    let uri = textDocument.uri
    let language = textDocument.language

    // If we can't create a service, this document is unsupported and we can bail here.
    guard let service = await languageService(for: uri, language, in: workspace) else {
      return
    }

    await workspace.buildSystemManager.registerForChangeNotifications(for: uri, language: language)

    // If the document is ready, we can immediately send the notification.
    await service.openDocument(notification, snapshot: snapshot)
  }

  func closeDocument(_ notification: DidCloseTextDocumentNotification) async {
    let uri = notification.textDocument.uri
    guard let workspace = await workspaceForDocument(uri: uri) else {
      logger.error(
        "Received close notification for file '\(uri.forLogging)' without a corresponding workspace, ignoring..."
      )
      return
    }
    await self.closeDocument(notification, workspace: workspace)
  }

  func reopenDocument(_ notification: ReopenTextDocumentNotification) async {
    let uri = notification.textDocument.uri
    guard let workspace = await workspaceForDocument(uri: uri) else {
      logger.error(
        "Received reopen notification for file '\(uri.forLogging)' without a corresponding workspace, ignoring..."
      )
      return
    }
    await workspace.documentService(for: uri)?.reopenDocument(notification)
  }

  func closeDocument(_ notification: DidCloseTextDocumentNotification, workspace: Workspace) async {
    // Immediately close the document. We need to be sure to clear our pending work queue in case
    // the build system still isn't ready.
    orLog("failed to close document", level: .error) {
      try documentManager.close(notification.textDocument.uri)
    }

    let uri = notification.textDocument.uri

    await workspace.buildSystemManager.unregisterForChangeNotifications(for: uri)

    await workspace.documentService(for: uri)?.closeDocument(notification)

    workspaceQueue.async {
      self.workspaceForUri[notification.textDocument.uri] = nil
    }
  }

  func changeDocument(_ notification: DidChangeTextDocumentNotification) async {
    let uri = notification.textDocument.uri

    guard let workspace = await workspaceForDocument(uri: uri) else {
      logger.error(
        "Received change notification for file '\(uri.forLogging)' without a corresponding workspace, ignoring..."
      )
      return
    }
    await workspace.semanticIndexManager?.schedulePreparationForEditorFunctionality(of: uri)

    // If the document is ready, we can handle the change right now.
    let editResult = orLog("Editing document") {
      try documentManager.edit(
        notification.textDocument.uri,
        newVersion: notification.textDocument.version,
        edits: notification.contentChanges
      )
    }
    guard let (preEditSnapshot, postEditSnapshot, edits) = editResult else {
      // Already logged failure
      return
    }
    await workspace.documentService(for: uri)?.changeDocument(
      notification,
      preEditSnapshot: preEditSnapshot,
      postEditSnapshot: postEditSnapshot,
      edits: edits
    )
  }

  func willSaveDocument(
    _ notification: WillSaveTextDocumentNotification,
    languageService: LanguageService
  ) async {
    await languageService.willSaveDocument(notification)
  }

  func didSaveDocument(
    _ notification: DidSaveTextDocumentNotification,
    languageService: LanguageService
  ) async {
    await languageService.didSaveDocument(notification)
  }

  func didChangeWorkspaceFolders(_ notification: DidChangeWorkspaceFoldersNotification) async {
    // There is a theoretical race condition here: While we await in this function,
    // the open documents or workspaces could have changed. Because of this,
    // we might close a document in a workspace that is no longer responsible
    // for it.
    // In practice, it is fine: sourcekit-lsp will not handle any new messages
    // while we are executing this function and thus there's no risk of
    // documents or workspaces changing. To hit the race condition, you need
    // to invoke the API of `SourceKitLSPServer` directly and open documents
    // while this function is executing. Even in such an API use case, hitting
    // that race condition seems very unlikely.
    var preChangeWorkspaces: [DocumentURI: Workspace] = [:]
    for docUri in self.documentManager.openDocuments {
      preChangeWorkspaces[docUri] = await self.workspaceForDocument(uri: docUri)
    }
    await workspaceQueue.async {
      if let removed = notification.event.removed {
        self.workspacesAndIsImplicit.removeAll { workspace in
          // Close all implicit workspaces as well because we could have opened a new explicit workspace that now contains
          // files from a previous implicit workspace.
          return workspace.isImplicit
            || removed.contains(where: { workspaceFolder in workspace.workspace.rootUri == workspaceFolder.uri })
        }
      }
      if let added = notification.event.added {
        let newWorkspaces = await added.asyncCompactMap { workspaceFolder in
          await orLog("Creating workspace after workspace folder change") {
            try await self.createWorkspaceWithInferredBuildSystem(workspaceFolder: workspaceFolder.uri)
          }
        }
        self.workspacesAndIsImplicit += newWorkspaces.map { (workspace: $0, isImplicit: false) }
      }
    }.value
  }

  func didChangeWatchedFiles(_ notification: DidChangeWatchedFilesNotification) async {
    // We can't make any assumptions about which file changes a particular build
    // system is interested in. Just because it doesn't have build settings for
    // a file doesn't mean a file can't affect the build system's build settings
    // (e.g. Package.swift doesn't have build settings but affects build
    // settings). Inform the build system about all file changes.
    for workspace in workspaces {
      await workspace.filesDidChange(notification.changes)
    }
  }

  // MARK: - Language features

  func completion(
    _ req: CompletionRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> CompletionList {
    return try await languageService.completion(req)
  }

  func hover(
    _ req: HoverRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> HoverResponse? {
    return try await languageService.hover(req)
  }

  func openGeneratedInterface(
    document: DocumentURI,
    moduleName: String,
    groupName: String?,
    symbolUSR symbol: String?,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> GeneratedInterfaceDetails? {
    return try await languageService.openGeneratedInterface(
      document: document,
      moduleName: moduleName,
      groupName: groupName,
      symbolUSR: symbol
    )
  }

  /// Handle a workspace/symbol request, returning the SymbolInformation.
  /// - returns: An array with SymbolInformation for each matching symbol in the workspace.
  func workspaceSymbols(_ req: WorkspaceSymbolsRequest) async throws -> [WorkspaceSymbolItem]? {
    // Ignore short queries since they are:
    // - noisy and slow, since they can match many symbols
    // - normally unintentional, triggered when the user types slowly or if the editor doesn't
    //   debounce events while the user is typing
    guard req.query.count >= minWorkspaceSymbolPatternLength else {
      return []
    }
    var symbolsAndIndex: [(symbol: SymbolOccurrence, index: CheckedIndex)] = []
    for workspace in workspaces {
      guard let index = workspace.index(checkedFor: .deletedFiles) else {
        continue
      }
      var symbolOccurrences: [SymbolOccurrence] = []
      index.forEachCanonicalSymbolOccurrence(
        containing: req.query,
        anchorStart: false,
        anchorEnd: false,
        subsequence: true,
        ignoreCase: true
      ) { symbol in
        if Task.isCancelled {
          return false
        }
        guard !symbol.location.isSystem && !symbol.roles.contains(.accessorOf) else {
          return true
        }
        symbolOccurrences.append(symbol)
        return true
      }
      try Task.checkCancellation()
      symbolsAndIndex += symbolOccurrences.map {
        return ($0, index)
      }
    }
    return symbolsAndIndex.sorted(by: { $0.symbol < $1.symbol }).map { symbolOccurrence, index in
      let symbolPosition = Position(
        line: symbolOccurrence.location.line - 1,  // 1-based -> 0-based
        // Technically we would need to convert the UTF-8 column to a UTF-16 column. This would require reading the
        // file. In practice they almost always coincide, so we accept the incorrectness here to avoid the file read.
        utf16index: symbolOccurrence.location.utf8Column - 1
      )

      let symbolLocation = Location(
        uri: symbolOccurrence.location.documentUri,
        range: Range(symbolPosition)
      )

      return WorkspaceSymbolItem.symbolInformation(
        SymbolInformation(
          name: symbolOccurrence.symbol.name,
          kind: symbolOccurrence.symbol.kind.asLspSymbolKind(),
          deprecated: nil,
          location: symbolLocation,
          containerName: index.containerName(of: symbolOccurrence)
        )
      )
    }
  }

  /// Forwards a SymbolInfoRequest to the appropriate toolchain service for this document.
  func symbolInfo(
    _ req: SymbolInfoRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [SymbolDetails] {
    return try await languageService.symbolInfo(req)
  }

  func documentSymbolHighlight(
    _ req: DocumentHighlightRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [DocumentHighlight]? {
    return try await languageService.documentSymbolHighlight(req)
  }

  func foldingRange(
    _ req: FoldingRangeRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [FoldingRange]? {
    return try await languageService.foldingRange(req)
  }

  func documentSymbol(
    _ req: DocumentSymbolRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> DocumentSymbolResponse? {
    return try await languageService.documentSymbol(req)
  }

  func documentColor(
    _ req: DocumentColorRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [ColorInformation] {
    return try await languageService.documentColor(req)
  }

  func documentSemanticTokens(
    _ req: DocumentSemanticTokensRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> DocumentSemanticTokensResponse? {
    return try await languageService.documentSemanticTokens(req)
  }

  func documentSemanticTokensDelta(
    _ req: DocumentSemanticTokensDeltaRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> DocumentSemanticTokensDeltaResponse? {
    return try await languageService.documentSemanticTokensDelta(req)
  }

  func documentSemanticTokensRange(
    _ req: DocumentSemanticTokensRangeRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> DocumentSemanticTokensResponse? {
    return try await languageService.documentSemanticTokensRange(req)
  }

  func documentFormatting(
    _ req: DocumentFormattingRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [TextEdit]? {
    return try await languageService.documentFormatting(req)
  }

  func documentRangeFormatting(
    _ req: DocumentRangeFormattingRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [TextEdit]? {
    return try await languageService.documentRangeFormatting(req)
  }

  func colorPresentation(
    _ req: ColorPresentationRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [ColorPresentation] {
    return try await languageService.colorPresentation(req)
  }

  func executeCommand(_ req: ExecuteCommandRequest) async throws -> LSPAny? {
    guard let uri = req.textDocument?.uri else {
      logger.error("Attempted to perform executeCommand request without an URL")
      return nil
    }
    guard let workspace = await workspaceForDocument(uri: uri) else {
      throw ResponseError.workspaceNotOpen(uri)
    }
    guard let languageService = workspace.documentService(for: uri) else {
      return nil
    }

    let executeCommand = ExecuteCommandRequest(
      command: req.command,
      arguments: req.argumentsWithoutSourceKitMetadata
    )
    return try await languageService.executeCommand(executeCommand)
  }

  func getReferenceDocument(_ req: GetReferenceDocumentRequest) async throws -> GetReferenceDocumentResponse {
    let primaryFileURI = try ReferenceDocumentURL(from: req.uri).primaryFile

    guard let workspace = await workspaceForDocument(uri: primaryFileURI) else {
      throw ResponseError.workspaceNotOpen(primaryFileURI)
    }

    guard let languageService = workspace.documentService(for: primaryFileURI) else {
      throw ResponseError.unknown("No Language Service for URI: \(primaryFileURI)")
    }

    return try await languageService.getReferenceDocument(req)
  }

  func codeAction(
    _ req: CodeActionRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> CodeActionRequestResponse? {
    let response = try await languageService.codeAction(req)
    return req.injectMetadata(toResponse: response)
  }

  func codeLens(
    _ req: CodeLensRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [CodeLens] {
    return try await languageService.codeLens(req)
  }

  func inlayHint(
    _ req: InlayHintRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [InlayHint] {
    return try await languageService.inlayHint(req)
  }

  func documentDiagnostic(
    _ req: DocumentDiagnosticsRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> DocumentDiagnosticReport {
    return try await languageService.documentDiagnostic(req)
  }

  /// Converts a location from the symbol index to an LSP location.
  ///
  /// - Parameter location: The symbol index location
  /// - Returns: The LSP location
  private nonisolated func indexToLSPLocation(_ location: SymbolLocation) -> Location? {
    guard !location.path.isEmpty else { return nil }
    return Location(
      uri: location.documentUri,
      range: Range(
        Position(
          // 1-based -> 0-based
          // Note that we still use max(0, ...) as a fallback if the location is zero.
          line: max(0, location.line - 1),
          // Technically we would need to convert the UTF-8 column to a UTF-16 column. This would require reading the
          // file. In practice they almost always coincide, so we accept the incorrectness here to avoid the file read.
          utf16index: max(0, location.utf8Column - 1)
        )
      )
    )
  }

  func declaration(
    _ req: DeclarationRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> LocationsOrLocationLinksResponse? {
    return try await languageService.declaration(req)
  }

  /// Return the locations for jump to definition from the given `SymbolDetails`.
  private func definitionLocations(
    for symbol: SymbolDetails,
    in uri: DocumentURI,
    languageService: LanguageService
  ) async throws -> [Location] {
    // If this symbol is a module then generate a textual interface
    if symbol.kind == .module, let name = symbol.name {
      let interfaceLocation = try await self.definitionInInterface(
        moduleName: name,
        groupName: nil,
        symbolUSR: nil,
        originatorUri: uri,
        languageService: languageService
      )
      return [interfaceLocation]
    }

    if symbol.isSystem ?? false, let systemModule = symbol.systemModule {
      let location = try await self.definitionInInterface(
        moduleName: systemModule.moduleName,
        groupName: systemModule.groupName,
        symbolUSR: symbol.usr,
        originatorUri: uri,
        languageService: languageService
      )
      return [location]
    }

    guard let index = await self.workspaceForDocument(uri: uri)?.index(checkedFor: .deletedFiles) else {
      if let bestLocalDeclaration = symbol.bestLocalDeclaration {
        return [bestLocalDeclaration]
      } else {
        return []
      }
    }
    guard let usr = symbol.usr else { return [] }
    logger.info("Performing indexed jump-to-definition with USR \(usr)")
    var occurrences = index.definitionOrDeclarationOccurrences(ofUSR: usr)
    if symbol.isDynamic ?? true {
      lazy var transitiveReceiverUsrs: [String]? = {
        if let receiverUsrs = symbol.receiverUsrs {
          return transitiveSubtypeClosure(
            ofUsrs: receiverUsrs,
            index: index
          )
        } else {
          return nil
        }
      }()
      occurrences += occurrences.flatMap {
        let overriddenUsrs = index.occurrences(relatedToUSR: $0.symbol.usr, roles: .overrideOf).map(\.symbol.usr)
        let overriddenSymbolDefinitions = overriddenUsrs.compactMap {
          index.primaryDefinitionOrDeclarationOccurrence(ofUSR: $0)
        }
        // Only contain overrides that are children of one of the receiver types or their subtypes or extensions.
        return overriddenSymbolDefinitions.filter { override in
          override.relations.contains(where: {
            guard $0.roles.contains(.childOf) else {
              return false
            }
            if let transitiveReceiverUsrs, !transitiveReceiverUsrs.contains($0.symbol.usr) {
              return false
            }
            return true
          })
        }
      }
    }

    if occurrences.isEmpty, let bestLocalDeclaration = symbol.bestLocalDeclaration {
      return [bestLocalDeclaration]
    }

    return occurrences.compactMap { indexToLSPLocation($0.location) }.sorted()
  }

  /// Returns the result of a `DefinitionRequest` by running a `SymbolInfoRequest`, inspecting
  /// its result and doing index lookups, if necessary.
  ///
  /// In contrast to `definition`, this does not fall back to sending a `DefinitionRequest` to the
  /// toolchain language server.
  private func indexBasedDefinition(
    _ req: DefinitionRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [Location] {
    let symbols = try await languageService.symbolInfo(
      SymbolInfoRequest(
        textDocument: req.textDocument,
        position: req.position
      )
    )

    let canonicalOriginatorLocation = await languageService.canonicalDeclarationPosition(
      of: req.position,
      in: req.textDocument.uri
    )

    // Returns `true` if `location` points to the same declaration that the definition request was initiated from.
    @Sendable func isAtCanonicalOriginatorLocation(_ location: Location) async -> Bool {
      guard location.uri == req.textDocument.uri, let canonicalOriginatorLocation else {
        return false
      }
      return await languageService.canonicalDeclarationPosition(of: location.range.lowerBound, in: location.uri)
        == canonicalOriginatorLocation
    }

    var locations = try await symbols.asyncFlatMap { (symbol) -> [Location] in
      var locations: [Location]
      if let bestLocalDeclaration = symbol.bestLocalDeclaration,
        !(symbol.isDynamic ?? true),
        symbol.usr?.hasPrefix("s:") ?? false /* Swift symbols have USRs starting with s: */
      {
        // If we have a known non-dynamic symbol within Swift, we don't need to do an index lookup.
        // For non-Swift symbols, we need to perform an index lookup because the best local declaration will point to
        // a header file but jump-to-definition should prefer the implementation (there's the declaration request to
        // jump to the function's declaration).
        locations = [bestLocalDeclaration]
      } else {
        locations = try await self.definitionLocations(
          for: symbol,
          in: req.textDocument.uri,
          languageService: languageService
        )
      }

      // If the symbol's location is is where we initiated rename from, also show the declarations that the symbol
      // overrides.
      if let location = locations.only,
        let usr = symbol.usr,
        let index = workspace.index(checkedFor: .deletedFiles),
        await isAtCanonicalOriginatorLocation(location)
      {
        let baseUSRs = index.occurrences(ofUSR: usr, roles: .overrideOf).flatMap {
          $0.relations.filter { $0.roles.contains(.overrideOf) }.map(\.symbol.usr)
        }
        locations += baseUSRs.compactMap {
          guard let baseDeclOccurrence = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: $0) else {
            return nil
          }
          return indexToLSPLocation(baseDeclOccurrence.location)
        }
      }

      return locations
    }

    // Remove any duplicate locations. We might end up with duplicate locations when performing a definition request
    // on eg. `MyStruct()` when no explicit initializer is declared. In this case we get two symbol infos, one for the
    // declaration of the `MyStruct` type and one for the initializer, which is implicit and thus has the location of
    // the `MyStruct` declaration itself.
    locations = locations.unique

    // Try removing any results that would point back to the location we are currently at. This ensures that eg. in the
    // following case we only show line 2 when performing jump-to-definition on `TestImpl.doThing`.
    //
    // ```
    // protocol TestProtocol {
    //   func doThing()
    // }
    // struct TestImpl: TestProtocol {
    //   func doThing() { }
    // }
    // ```
    //
    // If this would result in no locations, don't apply the filter. This way, performing jump-to-definition in the
    // middle of a function's base name takes us to the base name start, indicating that jump-to-definition was able to
    // resolve the location and didn't fail.
    let nonOriginatorLocations = await locations.asyncFilter { await !isAtCanonicalOriginatorLocation($0) }
    if !nonOriginatorLocations.isEmpty {
      locations = nonOriginatorLocations
    }
    return locations
  }

  func definition(
    _ req: DefinitionRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> LocationsOrLocationLinksResponse? {
    let indexBasedResponse = try await indexBasedDefinition(req, workspace: workspace, languageService: languageService)
    // If we're unable to handle the definition request using our index, see if the
    // language service can handle it (e.g. clangd can provide AST based definitions).
    // We are on only calling the language service's `definition` function if your index-based lookup failed.
    // If this fallback request fails, its error is usually not very enlightening. For example the
    // `SwiftLanguageService` will always respond with `unsupported method`. Thus, only log such a failure instead of
    // returning it to the client.
    if indexBasedResponse.isEmpty {
      return await orLog("Fallback definition request", level: .info) {
        return try await languageService.definition(req)
      }
    }
    return .locations(indexBasedResponse)
  }

  /// Generate the generated interface for the given module, write it to disk and return the location to which to jump
  /// to get to the definition of `symbolUSR`.
  ///
  /// `originatorUri` is the URI of the file from which the definition request is performed. It is used to determine the
  /// compiler arguments to generate the generated interface.
  func definitionInInterface(
    moduleName: String,
    groupName: String?,
    symbolUSR: String?,
    originatorUri: DocumentURI,
    languageService: LanguageService
  ) async throws -> Location {
    guard
      let interfaceDetails = try await languageService.openGeneratedInterface(
        document: originatorUri,
        moduleName: moduleName,
        groupName: groupName,
        symbolUSR: symbolUSR
      )
    else {
      throw ResponseError.unknown("Could not generate Swift Interface for \(moduleName)")
    }
    let position = interfaceDetails.position ?? Position(line: 0, utf16index: 0)
    let loc = Location(uri: interfaceDetails.uri, range: Range(position))
    return loc
  }

  func implementation(
    _ req: ImplementationRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> LocationsOrLocationLinksResponse? {
    let symbols = try await languageService.symbolInfo(
      SymbolInfoRequest(
        textDocument: req.textDocument,
        position: req.position
      )
    )
    guard let index = await workspaceForDocument(uri: req.textDocument.uri)?.index(checkedFor: .deletedFiles) else {
      return nil
    }
    let locations = symbols.flatMap { (symbol) -> [Location] in
      guard let usr = symbol.usr else { return [] }
      var occurrences = index.occurrences(ofUSR: usr, roles: .baseOf)
      if occurrences.isEmpty {
        occurrences = index.occurrences(relatedToUSR: usr, roles: .overrideOf)
      }

      return occurrences.compactMap { indexToLSPLocation($0.location) }
    }
    return .locations(locations.sorted())
  }

  func references(
    _ req: ReferencesRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [Location] {
    let symbols = try await languageService.symbolInfo(
      SymbolInfoRequest(
        textDocument: req.textDocument,
        position: req.position
      )
    )
    guard let index = await workspaceForDocument(uri: req.textDocument.uri)?.index(checkedFor: .deletedFiles) else {
      return []
    }
    let locations = symbols.flatMap { (symbol) -> [Location] in
      guard let usr = symbol.usr else { return [] }
      logger.info("Finding references for USR \(usr)")
      var roles: SymbolRole = [.reference]
      if req.context.includeDeclaration {
        roles.formUnion([.declaration, .definition])
      }
      return index.occurrences(ofUSR: usr, roles: roles).compactMap { indexToLSPLocation($0.location) }
    }
    return locations.unique.sorted()
  }

  private func indexToLSPCallHierarchyItem(
    symbol: Symbol,
    containerName: String?,
    location: Location
  ) -> CallHierarchyItem {
    let name: String
    if let containerName {
      switch symbol.language {
      case .objc where symbol.kind == .instanceMethod || symbol.kind == .instanceProperty:
        name = "-[\(containerName) \(symbol.name)]"
      case .objc where symbol.kind == .classMethod || symbol.kind == .classProperty:
        name = "+[\(containerName) \(symbol.name)]"
      case .cxx, .c, .objc:
        // C shouldn't have container names for call hierarchy and Objective-C should be covered above.
        // Fall back to using the C++ notation using `::`.
        name = "\(containerName)::\(symbol.name)"
      case .swift:
        name = "\(containerName).\(symbol.name)"
      }
    } else {
      name = symbol.name
    }
    return CallHierarchyItem(
      name: name,
      kind: symbol.kind.asLspSymbolKind(),
      tags: nil,
      detail: nil,
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
    _ req: CallHierarchyPrepareRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [CallHierarchyItem]? {
    let symbols = try await languageService.symbolInfo(
      SymbolInfoRequest(
        textDocument: req.textDocument,
        position: req.position
      )
    )
    guard let index = await workspaceForDocument(uri: req.textDocument.uri)?.index(checkedFor: .deletedFiles) else {
      return nil
    }
    // For call hierarchy preparation we only locate the definition
    let usrs = symbols.compactMap(\.usr)

    // Only return a single call hierarchy item. Returning multiple doesn't make sense because they will all have the
    // same USR (because we query them by USR) and will thus expand to the exact same call hierarchy.
    let callHierarchyItems = usrs.compactMap { (usr) -> CallHierarchyItem? in
      guard let definition = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr) else {
        return nil
      }
      guard let location = indexToLSPLocation(definition.location) else {
        return nil
      }
      return self.indexToLSPCallHierarchyItem(
        symbol: definition.symbol,
        containerName: index.containerName(of: definition),
        location: location
      )
    }.sorted(by: { Location(uri: $0.uri, range: $0.range) < Location(uri: $1.uri, range: $1.range) })

    // Ideally, we should show multiple symbols. But VS Code fails to display call hierarchies with multiple root items,
    // failing with `Cannot read properties of undefined (reading 'map')`. Pick the first one.
    return Array(callHierarchyItems.prefix(1))
  }

  /// Extracts our implementation-specific data about a call hierarchy
  /// item as encoded in `indexToLSPCallHierarchyItem`.
  ///
  /// - Parameter data: The opaque data structure to extract
  /// - Returns: The extracted data if successful or nil otherwise
  private nonisolated func extractCallHierarchyItemData(_ rawData: LSPAny?) -> (uri: DocumentURI, usr: String)? {
    guard case let .dictionary(data) = rawData,
      case let .string(uriString) = data["uri"],
      case let .string(usr) = data["usr"],
      let uri = orLog("DocumentURI for call hierarchy item", { try DocumentURI(string: uriString) })
    else {
      return nil
    }
    return (uri: uri, usr: usr)
  }

  func incomingCalls(_ req: CallHierarchyIncomingCallsRequest) async throws -> [CallHierarchyIncomingCall]? {
    guard let data = extractCallHierarchyItemData(req.item.data),
      let index = await self.workspaceForDocument(uri: data.uri)?.index(checkedFor: .deletedFiles)
    else {
      return []
    }
    var callableUsrs = [data.usr]
    // Also show calls to the functions that this method overrides. This includes overridden class methods and
    // satisfied protocol requirements.
    callableUsrs += index.occurrences(ofUSR: data.usr, roles: .overrideOf).flatMap { occurrence in
      occurrence.relations.filter { $0.roles.contains(.overrideOf) }.map(\.symbol.usr)
    }
    // callOccurrences are all the places that any of the USRs in callableUsrs is called.
    // We also load the `calledBy` roles to get the method that contains the reference to this call.
    let callOccurrences = callableUsrs.flatMap { index.occurrences(ofUSR: $0, roles: .containedBy) }

    // Maps functions that call a USR in `callableUSRs` to all the called occurrences of `callableUSRs` within the
    // function. If a function `foo` calls `bar` multiple times, `callersToCalls[foo]` will contain two call
    // `SymbolOccurrence`s.
    // This way, we can group multiple calls to `bar` within `foo` to a single item with multiple `fromRanges`.
    var callersToCalls: [Symbol: [SymbolOccurrence]] = [:]

    for call in callOccurrences {
      // Callers are all `calledBy` relations of a call to a USR in `callableUsrs`, ie. all the functions that contain a
      // call to a USR in callableUSRs. In practice, this should always be a single item.
      let callers = call.relations.filter { $0.roles.contains(.containedBy) }.map(\.symbol)
      for caller in callers {
        callersToCalls[caller, default: []].append(call)
      }
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPLocation2(_ location: SymbolLocation) -> Location? {
      return self.indexToLSPLocation(location)
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPCallHierarchyItem2(
      symbol: Symbol,
      containerName: String?,
      location: Location
    ) -> CallHierarchyItem {
      return self.indexToLSPCallHierarchyItem(symbol: symbol, containerName: containerName, location: location)
    }

    let calls = callersToCalls.compactMap { (caller: Symbol, calls: [SymbolOccurrence]) -> CallHierarchyIncomingCall? in
      // Resolve the caller's definition to find its location
      let definition = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: caller.usr)
      let definitionSymbolLocation = definition?.location
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation2)
      let containerName: String? =
        if let definition {
          index.containerName(of: definition)
        } else {
          nil
        }

      let locations = calls.compactMap { indexToLSPLocation2($0.location) }.sorted()
      guard !locations.isEmpty else {
        return nil
      }

      return CallHierarchyIncomingCall(
        from: indexToLSPCallHierarchyItem2(
          symbol: caller,
          containerName: containerName,
          location: definitionLocation ?? locations.first!
        ),
        fromRanges: locations.map(\.range)
      )
    }
    return calls.sorted(by: { $0.from.name < $1.from.name })
  }

  func outgoingCalls(_ req: CallHierarchyOutgoingCallsRequest) async throws -> [CallHierarchyOutgoingCall]? {
    guard let data = extractCallHierarchyItemData(req.item.data),
      let index = await self.workspaceForDocument(uri: data.uri)?.index(checkedFor: .deletedFiles)
    else {
      return []
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPLocation2(_ location: SymbolLocation) -> Location? {
      return self.indexToLSPLocation(location)
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPCallHierarchyItem2(
      symbol: Symbol,
      containerName: String?,
      location: Location
    ) -> CallHierarchyItem {
      return self.indexToLSPCallHierarchyItem(symbol: symbol, containerName: containerName, location: location)
    }

    let callableUsrs = [data.usr] + index.occurrences(relatedToUSR: data.usr, roles: .accessorOf).map(\.symbol.usr)
    let callOccurrences = callableUsrs.flatMap { index.occurrences(relatedToUSR: $0, roles: .containedBy) }
    let calls = callOccurrences.compactMap { occurrence -> CallHierarchyOutgoingCall? in
      guard occurrence.symbol.kind.isCallable else {
        return nil
      }
      guard let location = indexToLSPLocation2(occurrence.location) else {
        return nil
      }

      // Resolve the callee's definition to find its location
      let definition = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: occurrence.symbol.usr)
      let definitionSymbolLocation = definition?.location
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation2)
      let containerName: String? =
        if let definition {
          index.containerName(of: definition)
        } else {
          nil
        }

      return CallHierarchyOutgoingCall(
        to: indexToLSPCallHierarchyItem2(
          symbol: occurrence.symbol,
          containerName: containerName,
          location: definitionLocation ?? location  // Use occurrence location as fallback
        ),
        fromRanges: [location.range]
      )
    }
    return calls.sorted(by: { $0.to.name < $1.to.name })
  }

  private func indexToLSPTypeHierarchyItem(
    symbol: Symbol,
    moduleName: String?,
    location: Location,
    index: CheckedIndex
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
        name = "\(symbol.name): \(conformances.map(\.symbol.name).sorted().joined(separator: ", "))"
      }
      // Add the file name and line to the detail string
      if let url = location.uri.fileURL,
        let basename = (try? AbsolutePath(validating: url.filePath))?.basename
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
    _ req: TypeHierarchyPrepareRequest,
    workspace: Workspace,
    languageService: LanguageService
  ) async throws -> [TypeHierarchyItem]? {
    let symbols = try await languageService.symbolInfo(
      SymbolInfoRequest(
        textDocument: req.textDocument,
        position: req.position
      )
    )
    guard !symbols.isEmpty else {
      return nil
    }
    guard let index = await workspaceForDocument(uri: req.textDocument.uri)?.index(checkedFor: .deletedFiles) else {
      return nil
    }
    let usrs =
      symbols
      .filter {
        // Only include references to type. For example, we don't want to find the type hierarchy of a constructor when
        // starting the type hierarchy on `Foo()``.
        switch $0.kind {
        case .class, .enum, .interface, .struct: return true
        default: return false
        }
      }
      .compactMap(\.usr)
    let typeHierarchyItems = usrs.compactMap { (usr) -> TypeHierarchyItem? in
      guard
        let info = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: usr),
        let location = indexToLSPLocation(info.location)
      else {
        return nil
      }
      return self.indexToLSPTypeHierarchyItem(
        symbol: info.symbol,
        moduleName: info.location.moduleName,
        location: location,
        index: index
      )
    }
    .sorted(by: { $0.name < $1.name })

    if typeHierarchyItems.isEmpty {
      // When returning an empty array, VS Code fails with the following two errors. Returning `nil` works around those
      // VS Code-internal errors showing up
      //  - MISSING provider
      //  - Cannot read properties of null (reading 'kind')
      return nil
    }
    // Ideally, we should show multiple symbols. But VS Code fails to display type hierarchies with multiple root items,
    // failing with `Cannot read properties of undefined (reading 'map')`. Pick the first one.
    return Array(typeHierarchyItems.prefix(1))
  }

  /// Extracts our implementation-specific data about a type hierarchy
  /// item as encoded in `indexToLSPTypeHierarchyItem`.
  ///
  /// - Parameter data: The opaque data structure to extract
  /// - Returns: The extracted data if successful or nil otherwise
  private nonisolated func extractTypeHierarchyItemData(_ rawData: LSPAny?) -> (uri: DocumentURI, usr: String)? {
    guard case let .dictionary(data) = rawData,
      case let .string(uriString) = data["uri"],
      case let .string(usr) = data["usr"],
      let uri = orLog("DocumentURI for type hierarchy item", { try DocumentURI(string: uriString) })
    else {
      return nil
    }
    return (uri: uri, usr: usr)
  }

  func supertypes(_ req: TypeHierarchySupertypesRequest) async throws -> [TypeHierarchyItem]? {
    guard let data = extractTypeHierarchyItemData(req.item.data),
      let index = await self.workspaceForDocument(uri: data.uri)?.index(checkedFor: .deletedFiles)
    else {
      return []
    }

    // Resolve base types
    let baseOccurs = index.occurrences(relatedToUSR: data.usr, roles: .baseOf)

    // Resolve retroactive conformances via the extensions
    let extensions = index.occurrences(ofUSR: data.usr, roles: .extendedBy)
    let retroactiveConformanceOccurs = extensions.flatMap { occurrence -> [SymbolOccurrence] in
      if occurrence.relations.count > 1 {
        // When the occurrence has an `extendedBy` relation, it's an extension declaration. An extension can only extend
        // a single type, so there can only be a single relation here.
        logger.fault("Expected at most extendedBy relation but got \(occurrence.relations.count)")
      }
      guard let related = occurrence.relations.sorted().first else {
        return []
      }
      return index.occurrences(relatedToUSR: related.symbol.usr, roles: .baseOf)
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPLocation2(_ location: SymbolLocation) -> Location? {
      return self.indexToLSPLocation(location)
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPTypeHierarchyItem2(
      symbol: Symbol,
      moduleName: String?,
      location: Location,
      index: CheckedIndex
    ) -> TypeHierarchyItem {
      return self.indexToLSPTypeHierarchyItem(symbol: symbol, moduleName: moduleName, location: location, index: index)
    }

    // Convert occurrences to type hierarchy items
    let occurs = baseOccurs + retroactiveConformanceOccurs
    let types = occurs.compactMap { occurrence -> TypeHierarchyItem? in
      guard let location = indexToLSPLocation2(occurrence.location) else {
        return nil
      }

      // Resolve the supertype's definition to find its location
      let definition = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: occurrence.symbol.usr)
      let definitionSymbolLocation = definition?.location
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation2)

      return indexToLSPTypeHierarchyItem2(
        symbol: occurrence.symbol,
        moduleName: definitionSymbolLocation?.moduleName,
        location: definitionLocation ?? location,  // Use occurrence location as fallback
        index: index
      )
    }
    return types.sorted(by: { $0.name < $1.name })
  }

  func subtypes(_ req: TypeHierarchySubtypesRequest) async throws -> [TypeHierarchyItem]? {
    guard let data = extractTypeHierarchyItemData(req.item.data),
      let index = await self.workspaceForDocument(uri: data.uri)?.index(checkedFor: .deletedFiles)
    else {
      return []
    }

    // Resolve child types and extensions
    let occurs = index.occurrences(ofUSR: data.usr, roles: [.baseOf, .extendedBy])

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPLocation2(_ location: SymbolLocation) -> Location? {
      return self.indexToLSPLocation(location)
    }

    // TODO: Remove this workaround once https://github.com/swiftlang/swift/issues/75600 is fixed
    func indexToLSPTypeHierarchyItem2(
      symbol: Symbol,
      moduleName: String?,
      location: Location,
      index: CheckedIndex
    ) -> TypeHierarchyItem {
      return self.indexToLSPTypeHierarchyItem(symbol: symbol, moduleName: moduleName, location: location, index: index)
    }

    // Convert occurrences to type hierarchy items
    let types = occurs.compactMap { occurrence -> TypeHierarchyItem? in
      if occurrence.relations.count > 1 {
        // An occurrence with a `baseOf` or `extendedBy` relation is an occurrence inside an inheritance clause.
        // Such an occurrence can only be the source of a single type, namely the one that the inheritance clause belongs
        // to.
        logger.fault("Expected at most extendedBy or baseOf relation but got \(occurrence.relations.count)")
      }
      guard let related = occurrence.relations.sorted().first, let location = indexToLSPLocation2(occurrence.location)
      else {
        return nil
      }

      // Resolve the subtype's definition to find its location
      let definition = index.primaryDefinitionOrDeclarationOccurrence(ofUSR: related.symbol.usr)
      let definitionSymbolLocation = definition.map(\.location)
      let definitionLocation = definitionSymbolLocation.flatMap(indexToLSPLocation2)

      return indexToLSPTypeHierarchyItem2(
        symbol: related.symbol,
        moduleName: definitionSymbolLocation?.moduleName,
        location: definitionLocation ?? location,  // Use occurrence location as fallback
        index: index
      )
    }
    return types.sorted { $0.name < $1.name }
  }

  func pollIndex(_ req: PollIndexRequest) async throws -> VoidResponse {
    for workspace in workspaces {
      await workspace.buildSystemManager.waitForUpToDateBuildGraph()
      await workspace.semanticIndexManager?.waitForUpToDateIndex()
      workspace.uncheckedIndex?.pollForUnitChangesAndWait()
    }
    return VoidResponse()
  }

  func triggerReindex(_ req: TriggerReindexRequest) async throws -> VoidResponse {
    for workspace in workspaces {
      await workspace.semanticIndexManager?.scheduleReindex()
    }
    return VoidResponse()
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

package typealias Diagnostic = LanguageServerProtocol.Diagnostic

fileprivate extension CheckedIndex {
  /// Get the name of the symbol that is a parent of this symbol, if one exists
  func containerName(of symbol: SymbolOccurrence) -> String? {
    // The container name of accessors is the container of the surrounding variable.
    let accessorOf = symbol.relations.filter { $0.roles.contains(.accessorOf) }
    if let primaryVariable = accessorOf.sorted().first {
      if accessorOf.count > 1 {
        logger.fault("Expected an occurrence to an accessor of at most one symbol, not multiple")
      }
      if let primaryVariable = primaryDefinitionOrDeclarationOccurrence(ofUSR: primaryVariable.symbol.usr) {
        return containerName(of: primaryVariable)
      }
    }

    let containers = symbol.relations.filter { $0.roles.contains(.childOf) }
    if containers.count > 1 {
      logger.fault("Expected an occurrence to a child of at most one symbol, not multiple")
    }
    return containers.filter {
      switch $0.symbol.kind {
      case .module, .namespace, .enum, .struct, .class, .protocol, .extension, .union:
        return true
      case .unknown, .namespaceAlias, .macro, .typealias, .function, .variable, .field, .enumConstant,
        .instanceMethod, .classMethod, .staticMethod, .instanceProperty, .classProperty, .staticProperty, .constructor,
        .destructor, .conversionFunction, .parameter, .using, .concept, .commentTag:
        return false
      }
    }.sorted().first?.symbol.name
  }
}

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
    case .module, .namespace:
      return .namespace
    case .field:
      return .property
    case .constructor:
      return .constructor
    case .destructor:
      return .null
    case .commentTag, .concept, .extension, .macro, .namespaceAlias, .typealias, .union, .unknown, .using:
      return .null
    }
  }

  var isCallable: Bool {
    switch self {
    case .function, .instanceMethod, .classMethod, .staticMethod, .constructor, .destructor, .conversionFunction:
      return true
    case .unknown, .module, .namespace, .namespaceAlias, .macro, .enum, .struct, .protocol, .extension, .union,
      .typealias, .field, .enumConstant, .parameter, .using, .concept, .commentTag, .variable, .instanceProperty,
      .class, .staticProperty, .classProperty:
      return false
    }
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
/// Note: This is not thread safe. Must be called from the `SourceKitLSPServer.queue`.
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

/// Returns the USRs of the subtypes of `usrs` as well as their subtypes and extensions, transitively.
fileprivate func transitiveSubtypeClosure(ofUsrs usrs: [String], index: CheckedIndex) -> [String] {
  var result: [String] = []
  for usr in usrs {
    result.append(usr)
    let directSubtypes = index.occurrences(ofUSR: usr, roles: [.baseOf, .extendedBy]).flatMap { occurrence in
      occurrence.relations.filter { $0.roles.contains(.baseOf) || $0.roles.contains(.extendedBy) }.map(\.symbol.usr)
    }
    let transitiveSubtypes = transitiveSubtypeClosure(ofUsrs: directSubtypes, index: index)
    result += transitiveSubtypes
  }
  return result
}

fileprivate extension Sequence where Element: Hashable {
  /// Removes all duplicate elements from the sequence, maintaining order.
  var unique: [Element] {
    var set = Set<Element>()
    return self.filter { set.insert($0).inserted }
  }
}

fileprivate extension URL {
  func isPrefix(of other: URL) -> Bool {
    guard self.pathComponents.count < other.pathComponents.count else {
      return false
    }
    return other.pathComponents[0..<self.pathComponents.count] == self.pathComponents[...]
  }
}

extension SourceKitLSPOptions {
  /// We can't conform `SourceKitLSPOptions` to `CustomLogStringConvertible` because that would require a public import
  /// of `SKLogging`. Instead, define an internal type that performs the logging of `SourceKitLSPOptions`.
  struct LoggingProxy: CustomLogStringConvertible {
    let options: SourceKitLSPOptions

    var description: String {
      options.prettyPrintedJSON
    }

    var redactedDescription: String {
      options.prettyPrintedRedactedJSON
    }
  }

  var loggingProxy: LoggingProxy {
    LoggingProxy(options: self)
  }

  var forLogging: CustomLogStringConvertibleWrapper {
    return self.loggingProxy.forLogging
  }
}
