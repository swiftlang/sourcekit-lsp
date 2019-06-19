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

import Basic

/// The set of known requests.
///
/// All requests from LSP as well as any extensions provided by the server should be listed here.
/// If you are adding a message for testing only, you can register it dynamically using
/// `MessageRegistry._register()` which allows you to avoid bloating the real server implementation.
public let builtinRequests: [_RequestType.Type] = [
  InitializeRequest.self,
  Shutdown.self,
  WorkspaceFoldersRequest.self,
  CompletionRequest.self,
  HoverRequest.self,
  DefinitionRequest.self,
  ReferencesRequest.self,
  DocumentHighlightRequest.self,
  DocumentFormatting.self,
  DocumentRangeFormatting.self,
  DocumentOnTypeFormatting.self,
  FoldingRangeRequest.self,
  DocumentSymbolRequest.self,
  DocumentColorRequest.self,
  ColorPresentationRequest.self,
  CodeActionRequest.self,
  ExecuteCommandRequest.self,

  // MARK: LSP Extension Requests

  SymbolInfoRequest.self,
]

/// The set of known notifications.
///
/// All notifications from LSP as well as any extensions provided by the server should be listed
/// here. If you are adding a message for testing only, you can register it dynamically using
/// `MessageRegistry._register()` which allows you to avoid bloating the real server implementation.
public let builtinNotifications: [NotificationType.Type] = [
  InitializedNotification.self,
  Exit.self,
  CancelRequest.self,
  LogMessage.self,
  DidChangeConfiguration.self,
  DidChangeWorkspaceFolders.self,
  DidOpenTextDocument.self,
  DidCloseTextDocument.self,
  DidChangeTextDocument.self,
  DidSaveTextDocument.self,
  WillSaveTextDocument.self,
  PublishDiagnostics.self,
]

// MARK: Miscellaneous Message Types

public struct VoidResponse: ResponseType, Hashable {
  public init() {}
}

extension Optional: MessageType where Wrapped: MessageType {}
extension Optional: ResponseType where Wrapped: ResponseType {}

extension Array: MessageType where Element: MessageType {}
extension Array: ResponseType where Element: ResponseType {}
