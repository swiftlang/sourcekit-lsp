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

import Foundation
import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import ToolchainRegistry

#if compiler(>=6)
package import BuildServerProtocol
package import LanguageServerProtocol
#else
import BuildServerProtocol
import LanguageServerProtocol
#endif

/// Build system to be used for testing BuildSystem and BuildSystemDelegate functionality with SourceKitLSPServer
/// and other components.
package actor TestBuildSystem: MessageHandler {
  private let connectionToSourceKitLSP: any Connection

  /// Build settings by file.
  private var buildSettingsByFile: [DocumentURI: TextDocumentSourceKitOptionsResponse] = [:]

  package func setBuildSettings(for uri: DocumentURI, to buildSettings: TextDocumentSourceKitOptionsResponse?) {
    buildSettingsByFile[uri] = buildSettings
    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  private let initializeData: SourceKitInitializeBuildResponseData

  package init(
    initializeData: SourceKitInitializeBuildResponseData = SourceKitInitializeBuildResponseData(
      sourceKitOptionsProvider: true
    ),
    connectionToSourceKitLSP: any Connection
  ) {
    self.initializeData = initializeData
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
  }

  package nonisolated func handle(_ notification: some NotificationType) {
    do {
      switch notification {
      case let notification as CancelRequestNotification:
        try self.cancelRequest(notification)
      case let notification as OnBuildExitNotification:
        try self.onBuildExit(notification)
      case let notification as OnBuildInitializedNotification:
        try self.onBuildInitialized(notification)
      case let notification as OnWatchedFilesDidChangeNotification:
        try self.onWatchedFilesDidChange(notification)
      default:
        throw ResponseError.methodNotFound(type(of: notification).method)
      }
    } catch {
      logger.error("Error while handling BSP notification")
    }
  }

  package nonisolated func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    func handle<R: RequestType>(_ request: R, using handler: @Sendable @escaping (R) async throws -> R.Response) {
      Task {
        do {
          reply(.success(try await handler(request) as! Request.Response))
        } catch {
          reply(.failure(ResponseError(error)))
        }
      }
    }

    switch request {
    case let request as BuildShutdownRequest:
      handle(request, using: self.buildShutdown(_:))
    case let request as BuildTargetSourcesRequest:
      handle(request, using: self.buildTargetSourcesRequest)
    case let request as InitializeBuildRequest:
      handle(request, using: self.initializeBuildRequest)
    case let request as TextDocumentSourceKitOptionsRequest:
      handle(request, using: self.textDocumentSourceKitOptionsRequest)
    case let request as WorkspaceBuildTargetsRequest:
      handle(request, using: self.workspaceBuildTargetsRequest)
    case let request as WorkspaceWaitForBuildSystemUpdatesRequest:
      handle(request, using: self.workspaceWaitForBuildSystemUpdatesRequest)
    case let request as BuildTargetPrepareRequest:
      handle(request, using: self.prepareTarget)
    default:
      reply(.failure(ResponseError.methodNotFound(type(of: request).method)))
    }
  }

  func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
    return InitializeBuildResponse(
      displayName: "TestBuildSystem",
      version: "",
      bspVersion: "2.2.0",
      capabilities: BuildServerCapabilities(),
      dataKind: .sourceKit,
      data: initializeData.encodeToLSPAny()
    )
  }

  nonisolated func onBuildInitialized(_ notification: OnBuildInitializedNotification) throws {
    // Nothing to do
  }

  func buildShutdown(_ request: BuildShutdownRequest) async throws -> VoidResponse {
    return VoidResponse()
  }

  nonisolated func onBuildExit(_ notification: OnBuildExitNotification) throws {
    // Nothing to do
  }

  func workspaceBuildTargetsRequest(
    _ request: WorkspaceBuildTargetsRequest
  ) async throws -> WorkspaceBuildTargetsResponse {
    return WorkspaceBuildTargetsResponse(targets: [
      BuildTarget(
        id: .dummy,
        displayName: nil,
        baseDirectory: nil,
        tags: [],
        capabilities: BuildTargetCapabilities(),
        languageIds: [],
        dependencies: []
      )
    ])
  }

  func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
    return BuildTargetSourcesResponse(items: [
      SourcesItem(
        target: .dummy,
        sources: buildSettingsByFile.keys.map { SourceItem(uri: $0, kind: .file, generated: false) }
      )
    ])
  }

  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }

  func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    return VoidResponse()
  }

  package func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }

  nonisolated func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws {
    // Not watching any files
  }

  func workspaceWaitForBuildSystemUpdatesRequest(
    _ request: WorkspaceWaitForBuildSystemUpdatesRequest
  ) async throws -> VoidResponse {
    return VoidResponse()
  }

  nonisolated func cancelRequest(_ notification: CancelRequestNotification) throws {}
}
