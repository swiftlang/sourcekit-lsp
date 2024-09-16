//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

fileprivate let requestTypes: [_RequestType.Type] = [
  BuildShutdownRequest.self,
  BuildTargetPrepareRequest.self,
  BuildTargetSourcesRequest.self,
  CreateWorkDoneProgressRequest.self,
  InitializeBuildRequest.self,
  RegisterForChanges.self,
  TextDocumentSourceKitOptionsRequest.self,
  WorkspaceWaitForBuildSystemUpdatesRequest.self,
  WorkspaceBuildTargetsRequest.self,
]

fileprivate let notificationTypes: [NotificationType.Type] = [
  OnBuildExitNotification.self,
  FileOptionsChangedNotification.self,
  OnBuildInitializedNotification.self,
  OnBuildLogMessageNotification.self,
  OnBuildTargetDidChangeNotification.self,
  OnWatchedFilesDidChangeNotification.self,
]

public let bspRegistry = MessageRegistry(requests: requestTypes, notifications: notificationTypes)
