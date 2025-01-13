//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if compiler(>=6)
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
package import SwiftExtensions
#else
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions
#endif

/// A lightweight way of describing tasks that are created from handling LSP
/// requests or notifications for the purpose of dependency tracking.
package enum MessageHandlingDependencyTracker: QueueBasedMessageHandlerDependencyTracker {
  /// A task that changes the global configuration of sourcekit-lsp in any way.
  ///
  /// No other tasks must execute simultaneously with this task since they
  /// might be relying on this task to take effect.
  case globalConfigurationChange

  /// A request that depends on the state of all documents.
  ///
  /// These requests wait for `documentUpdate` tasks for all documents to finish before being executed.
  ///
  /// Requests that only read the semantic index and are not affected by changes to the in-memory file contents should
  /// `freestanding` requests.
  case workspaceRequest

  /// Changes the contents of the document with the given URI.
  ///
  /// Any other updates or requests to this document must wait for the
  /// document update to finish before being executed
  case documentUpdate(DocumentURI)

  /// A request that concerns one document.
  ///
  /// Any updates to this document must be processed before the document
  /// request can be handled. Multiple requests to the same document can be
  /// handled simultaneously.
  case documentRequest(DocumentURI)

  /// A request that doesn't have any dependencies other than global
  /// configuration changes.
  case freestanding

  /// Whether this request needs to finish before `other` can start executing.
  package func isDependency(of other: MessageHandlingDependencyTracker) -> Bool {
    switch (self, other) {
    // globalConfigurationChange
    case (.globalConfigurationChange, _): return true
    case (_, .globalConfigurationChange): return true

    // globalDocumentState
    case (.workspaceRequest, .workspaceRequest): return false
    case (.documentUpdate, .workspaceRequest): return true
    case (.workspaceRequest, .documentUpdate): return true
    case (.workspaceRequest, .documentRequest): return false
    case (.documentRequest, .workspaceRequest): return false

    // documentUpdate
    case (.documentUpdate(let selfUri), .documentUpdate(let otherUri)):
      return selfUri == otherUri
    case (.documentUpdate(let selfUri), .documentRequest(let otherUri)):
      return selfUri.buildSettingsFile == otherUri.buildSettingsFile
    case (.documentRequest(let selfUri), .documentUpdate(let otherUri)):
      return selfUri.buildSettingsFile == otherUri.buildSettingsFile

    // documentRequest
    case (.documentRequest, .documentRequest):
      return false

    // freestanding
    case (.freestanding, _):
      return false
    case (_, .freestanding):
      return false
    }
  }

  package func dependencies(in pendingTasks: [PendingTask<Self>]) -> [PendingTask<Self>] {
    return pendingTasks.filter { $0.metadata.isDependency(of: self) }
  }

  package init(_ notification: some NotificationType) {
    switch notification {
    case is CancelRequestNotification:
      self = .freestanding
    case is CancelWorkDoneProgressNotification:
      self = .freestanding
    case is DidChangeConfigurationNotification:
      self = .globalConfigurationChange
    case let notification as DidChangeNotebookDocumentNotification:
      self = .documentUpdate(notification.notebookDocument.uri)
    case let notification as DidChangeTextDocumentNotification:
      self = .documentUpdate(notification.textDocument.uri)
    case is DidChangeWatchedFilesNotification:
      self = .globalConfigurationChange
    case is DidChangeWorkspaceFoldersNotification:
      self = .globalConfigurationChange
    case let notification as DidCloseNotebookDocumentNotification:
      self = .documentUpdate(notification.notebookDocument.uri)
    case let notification as DidCloseTextDocumentNotification:
      self = .documentUpdate(notification.textDocument.uri)
    case is DidCreateFilesNotification:
      self = .freestanding
    case is DidDeleteFilesNotification:
      self = .freestanding
    case let notification as DidOpenNotebookDocumentNotification:
      self = .documentUpdate(notification.notebookDocument.uri)
    case let notification as DidOpenTextDocumentNotification:
      self = .documentUpdate(notification.textDocument.uri)
    case is DidRenameFilesNotification:
      self = .freestanding
    case let notification as DidSaveNotebookDocumentNotification:
      self = .documentUpdate(notification.notebookDocument.uri)
    case let notification as DidSaveTextDocumentNotification:
      self = .documentUpdate(notification.textDocument.uri)
    case is ExitNotification:
      self = .globalConfigurationChange
    case is InitializedNotification:
      self = .globalConfigurationChange
    case is LogMessageNotification:
      self = .freestanding
    case is LogTraceNotification:
      self = .freestanding
    case is PublishDiagnosticsNotification:
      self = .freestanding
    case let notification as ReopenTextDocumentNotification:
      self = .documentUpdate(notification.textDocument.uri)
    case is SetTraceNotification:
      // `$/setTrace` changes a global configuration setting but it doesn't affect the result of any other request. To
      // avoid blocking other requests on a `$/setTrace` notification the client might send during launch, we treat it
      // as a freestanding message.
      // Also, we don't do anything with this notification at the moment, so it doesn't matter.
      self = .freestanding
    case is ShowMessageNotification:
      self = .freestanding
    case let notification as WillSaveTextDocumentNotification:
      self = .documentUpdate(notification.textDocument.uri)
    case is WorkDoneProgress:
      self = .freestanding
    default:
      logger.error(
        """
        Unknown notification \(type(of: notification)). Treating as a freestanding notification. \
        This might lead to out-of-order request handling
        """
      )
      self = .freestanding
    }
  }

  package init(_ request: some RequestType) {
    switch request {
    case let request as any TextDocumentRequest: self = .documentRequest(request.textDocument.uri)
    case is ApplyEditRequest:
      self = .freestanding
    case is BarrierRequest:
      self = .globalConfigurationChange
    case is CallHierarchyIncomingCallsRequest:
      self = .freestanding
    case is CallHierarchyOutgoingCallsRequest:
      self = .freestanding
    case is CodeActionResolveRequest:
      self = .freestanding
    case is CodeLensRefreshRequest:
      self = .freestanding
    case is CodeLensResolveRequest:
      self = .freestanding
    case is CompletionItemResolveRequest:
      self = .freestanding
    case is CreateWorkDoneProgressRequest:
      self = .freestanding
    case is DiagnosticsRefreshRequest:
      self = .freestanding
    case is DocumentLinkResolveRequest:
      self = .freestanding
    case let request as ExecuteCommandRequest:
      if let uri = request.textDocument?.uri {
        self = .documentRequest(uri)
      } else {
        self = .freestanding
      }
    case let request as GetReferenceDocumentRequest:
      self = .documentRequest(request.uri)
    case is InitializeRequest:
      self = .globalConfigurationChange
    case is InlayHintRefreshRequest:
      self = .freestanding
    case is InlayHintResolveRequest:
      self = .freestanding
    case is InlineValueRefreshRequest:
      self = .freestanding
    case is PollIndexRequest:
      self = .globalConfigurationChange
    case is RenameRequest:
      // Rename might touch multiple files. Make it a global configuration change so that edits to all files that might
      // be affected have been processed.
      self = .globalConfigurationChange
    case is RegisterCapabilityRequest:
      self = .globalConfigurationChange
    case is ShowMessageRequest:
      self = .freestanding
    case is ShutdownRequest:
      self = .globalConfigurationChange
    case is TriggerReindexRequest:
      self = .globalConfigurationChange
    case is TypeHierarchySubtypesRequest:
      self = .freestanding
    case is TypeHierarchySupertypesRequest:
      self = .freestanding
    case is UnregisterCapabilityRequest:
      self = .globalConfigurationChange
    case is WillCreateFilesRequest:
      self = .freestanding
    case is WillDeleteFilesRequest:
      self = .freestanding
    case is WillRenameFilesRequest:
      self = .freestanding
    case is WorkspaceDiagnosticsRequest:
      self = .freestanding
    case is WorkspaceFoldersRequest:
      self = .freestanding
    case is WorkspaceSemanticTokensRefreshRequest:
      self = .freestanding
    case is WorkspaceSymbolResolveRequest:
      self = .freestanding
    case is WorkspaceSymbolsRequest:
      self = .freestanding
    case is WorkspaceTestsRequest:
      self = .workspaceRequest
    default:
      logger.error(
        """
        Unknown request \(type(of: request)). Treating as a freestanding request. \
        This might lead to out-of-order request handling
        """
      )
      self = .freestanding
    }
  }
}
