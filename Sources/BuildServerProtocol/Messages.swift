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
  BuildTargetOutputPaths.self,
  BuildTargetsRequest.self,
  BuildTargetSourcesRequest.self,
  BuildServerProtocol.CreateWorkDoneProgressRequest.self,
  InitializeBuildRequest.self,
  PrepareTargetsRequest.self,
  RegisterForChanges.self,
  ShutdownBuild.self,
  SourceKitOptionsRequest.self,
  WaitForBuildSystemUpdatesRequest.self,
]

fileprivate let notificationTypes: [NotificationType.Type] = [
  DidChangeBuildTargetNotification.self,
  BuildServerProtocol.DidChangeWatchedFilesNotification.self,
  ExitBuildNotification.self,
  FileOptionsChangedNotification.self,
  InitializedBuildNotification.self,
  BuildServerProtocol.LogMessageNotification.self,
]

public let bspRegistry = MessageRegistry(requests: requestTypes, notifications: notificationTypes)
