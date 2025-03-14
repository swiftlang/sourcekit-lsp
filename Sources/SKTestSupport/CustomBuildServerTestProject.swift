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

package import BuildServerProtocol
import BuildSystemIntegration
package import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry
import XCTest

// MARK: - CustomBuildServer

package actor CustomBuildServerInProgressRequestTracker {
  private var inProgressRequests: [RequestID: Task<Void, Never>] = [:]
  private let queue = AsyncQueue<Serial>()

  package init() {}

  private func setInProgressRequestImpl(_ id: RequestID, task: Task<Void, Never>) {
    guard inProgressRequests[id] == nil else {
      logger.fault("Received duplicate request for id: \(id, privacy: .public)")
      return
    }
    inProgressRequests[id] = task
  }

  fileprivate nonisolated func setInProgressRequest(_ id: RequestID, task: Task<Void, Never>) {
    queue.async {
      await self.setInProgressRequestImpl(id, task: task)
    }
  }

  private func markTaskAsFinishedImpl(_ id: RequestID) {
    guard inProgressRequests[id] != nil else {
      logger.fault("Cannot mark request \(id, privacy: .public) as finished because it is not being tracked.")
      return
    }
    inProgressRequests[id] = nil
  }

  fileprivate nonisolated func markTaskAsFinished(_ id: RequestID) {
    queue.async {
      await self.markTaskAsFinishedImpl(id)
    }
  }

  private func cancelTaskImpl(_ id: RequestID) {
    guard let task = inProgressRequests[id] else {
      logger.fault("Cannot cancel task \(id, privacy: .public) because it isn't tracked")
      return
    }
    task.cancel()
  }

  fileprivate nonisolated func cancelTask(_ id: RequestID) {
    queue.async {
      await self.cancelTaskImpl(id)
    }
  }
}

/// A build server that can be injected into `CustomBuildServerTestProject`.
package protocol CustomBuildServer: MessageHandler {
  var inProgressRequestsTracker: CustomBuildServerInProgressRequestTracker { get }

  init(projectRoot: URL, connectionToSourceKitLSP: any Connection)

  func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse
  func onBuildInitialized(_ notification: OnBuildInitializedNotification) throws
  func buildShutdown(_ request: BuildShutdownRequest) async throws -> VoidResponse
  func onBuildExit(_ notification: OnBuildExitNotification) throws
  func workspaceBuildTargetsRequest(
    _ request: WorkspaceBuildTargetsRequest
  ) async throws -> WorkspaceBuildTargetsResponse
  func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse
  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse?
  func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> VoidResponse
  func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse
  nonisolated func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws
  func workspaceWaitForBuildSystemUpdatesRequest(
    _ request: WorkspaceWaitForBuildSystemUpdatesRequest
  ) async throws -> VoidResponse
  nonisolated func cancelRequest(_ notification: CancelRequestNotification) throws
}

extension CustomBuildServer {
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
      logger.error("Error while handling BSP notification: \(error.forLogging)")
    }
  }

  package nonisolated func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    func handle<R: RequestType>(_ request: R, using handler: @Sendable @escaping (R) async throws -> R.Response) {
      let task = Task {
        defer { inProgressRequestsTracker.markTaskAsFinished(id) }
        do {
          reply(.success(try await handler(request) as! Request.Response))
        } catch {
          reply(.failure(ResponseError(error)))
        }
      }
      inProgressRequestsTracker.setInProgressRequest(id, task: task)
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
}

package extension CustomBuildServer {
  // MARK: Helper functions for the implementation of BSP methods

  func initializationResponse(
    initializeData: SourceKitInitializeBuildResponseData = SourceKitInitializeBuildResponseData(
      sourceKitOptionsProvider: true
    )
  ) -> InitializeBuildResponse {
    InitializeBuildResponse(
      displayName: "\(type(of: self))",
      version: "",
      bspVersion: "2.2.0",
      capabilities: BuildServerCapabilities(),
      dataKind: .sourceKit,
      data: initializeData.encodeToLSPAny()
    )
  }

  func dummyTargetSourcesResponse(_ files: some Sequence<DocumentURI>) -> BuildTargetSourcesResponse {
    return BuildTargetSourcesResponse(items: [
      SourcesItem(target: .dummy, sources: files.map { SourceItem(uri: $0, kind: .file, generated: false) })
    ])
  }

  // MARK: Default implementation for all build server methods that usually don't need customization.

  func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
    return initializationResponse()
  }

  nonisolated func onBuildInitialized(_ notification: OnBuildInitializedNotification) throws {}

  func buildShutdown(_ request: BuildShutdownRequest) async throws -> VoidResponse {
    return VoidResponse()
  }

  nonisolated func onBuildExit(_ notification: OnBuildExitNotification) throws {}

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

  func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> VoidResponse {
    return VoidResponse()
  }

  func waitForBuildSystemUpdates(request: WorkspaceWaitForBuildSystemUpdatesRequest) async -> VoidResponse {
    return VoidResponse()
  }

  nonisolated func onWatchedFilesDidChange(_ notification: OnWatchedFilesDidChangeNotification) throws {}

  func workspaceWaitForBuildSystemUpdatesRequest(
    _ request: WorkspaceWaitForBuildSystemUpdatesRequest
  ) async throws -> VoidResponse {
    return VoidResponse()
  }

  nonisolated func cancelRequest(_ notification: CancelRequestNotification) throws {
    inProgressRequestsTracker.cancelTask(notification.id)
  }
}

// MARK: - CustomBuildServerTestProject

/// A test project that launches a custom build server in-process.
///
/// In contrast to `ExternalBuildServerTestProject`, the custom build system runs in-process and is implemented in
/// Swift.
package final class CustomBuildServerTestProject<BuildServer: CustomBuildServer>: MultiFileTestProject {
  private let buildServerBox = ThreadSafeBox<BuildServer?>(initialValue: nil)

  package init(
    files: [RelativeFileLocation: String],
    buildServer buildServerType: BuildServer.Type,
    options: SourceKitLSPOptions? = nil,
    hooks: Hooks = Hooks(),
    enableBackgroundIndexing: Bool = false,
    testScratchDir: URL? = nil,
    testName: String = #function
  ) async throws {
    var hooks = hooks
    XCTAssertNil(hooks.buildSystemHooks.injectBuildServer)
    hooks.buildSystemHooks.injectBuildServer = { [buildServerBox] projectRoot, connectionToSourceKitLSP in
      let buildServer = BuildServer(projectRoot: projectRoot, connectionToSourceKitLSP: connectionToSourceKitLSP)
      buildServerBox.value = buildServer
      return LocalConnection(receiverName: "TestBuildSystem", handler: buildServer)
    }
    try await super.init(
      files: files,
      options: options,
      hooks: hooks,
      enableBackgroundIndexing: enableBackgroundIndexing,
      testScratchDir: testScratchDir,
      testName: testName
    )
  }

  package func buildServer(file: StaticString = #filePath, line: UInt = #line) throws -> BuildServer {
    try XCTUnwrap(buildServerBox.value, "Accessing build server before it has been created", file: file, line: line)
  }
}
