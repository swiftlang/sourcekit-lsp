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

import BuildServerIntegration
@_spi(SourceKitLSP) package import BuildServerProtocol
package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
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
  func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> BuildTargetPrepareResponse
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
    initializeData: SourceKitInitializeBuildResponseData = .init(sourceKitOptionsProvider: true)
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

  func initializationResponseSupportingBackgroundIndexing(
    projectRoot: URL,
    outputPathsProvider: Bool
  ) throws -> InitializeBuildResponse {
    return initializationResponse(
      initializeData: SourceKitInitializeBuildResponseData(
        indexDatabasePath: try projectRoot.appending(component: "index-db").filePath,
        indexStorePath: try projectRoot.appending(component: "index-store").filePath,
        outputPathsProvider: outputPathsProvider,
        prepareProvider: true,
        sourceKitOptionsProvider: true
      )
    )
  }

  /// Returns a fake path that is unique to this target and file combination and can be used to identify this
  /// combination in a unit's output path.
  func fakeOutputPath(for file: String, in target: String) -> String {
    #if os(Windows)
    return #"C:\"# + target + #"\"# + file + ".o"
    #else
    return "/" + target + "/" + file + ".o"
    #endif
  }

  func sourceItem(for url: URL, outputPath: String) -> SourceItem {
    SourceItem(
      uri: URI(url),
      kind: .file,
      generated: false,
      dataKind: .sourceKit,
      data: SourceKitSourceItemData(outputPath: outputPath).encodeToLSPAny()
    )
  }

  func dummyTargetSourcesResponse(files: some Sequence<DocumentURI>) -> BuildTargetSourcesResponse {
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
        capabilities: BuildTargetCapabilities(),
        languageIds: [],
        dependencies: []
      )
    ])
  }

  func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> BuildTargetPrepareResponse {
    return BuildTargetPrepareResponse()
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
/// In contrast to `ExternalBuildServerTestProject`, the custom build server runs in-process and is implemented in
/// Swift.
package final class CustomBuildServerTestProject<BuildServer: CustomBuildServer>: MultiFileTestProject {
  private let buildServerBox = ThreadSafeBox<BuildServer?>(initialValue: nil)

  package init(
    files: [RelativeFileLocation: String],
    buildServer buildServerType: BuildServer.Type,
    capabilities: ClientCapabilities = ClientCapabilities(),
    options: SourceKitLSPOptions? = nil,
    hooks: Hooks = Hooks(),
    enableBackgroundIndexing: Bool = false,
    usePullDiagnostics: Bool = true,
    pollIndex: Bool = true,
    preInitialization: ((TestSourceKitLSPClient) -> Void)? = nil,
    testScratchDir: URL? = nil,
    testName: String = #function
  ) async throws {
    var hooks = hooks
    XCTAssertNil(hooks.buildServerHooks.injectBuildServer)
    hooks.buildServerHooks.injectBuildServer = { [buildServerBox] projectRoot, connectionToSourceKitLSP in
      let buildServer = BuildServer(projectRoot: projectRoot, connectionToSourceKitLSP: connectionToSourceKitLSP)
      buildServerBox.value = buildServer
      return LocalConnection(receiverName: "TestBuildServer", handler: buildServer)
    }
    try await super.init(
      files: files,
      capabilities: capabilities,
      options: options,
      hooks: hooks,
      enableBackgroundIndexing: enableBackgroundIndexing,
      usePullDiagnostics: usePullDiagnostics,
      preInitialization: preInitialization,
      testScratchDir: testScratchDir,
      testName: testName
    )

    if pollIndex {
      // Wait for the indexstore-db to finish indexing
      try await testClient.send(SynchronizeRequest(index: true))
    }
  }

  package func buildServer(file: StaticString = #filePath, line: UInt = #line) throws -> BuildServer {
    try XCTUnwrap(buildServerBox.value, "Accessing build server before it has been created", file: file, line: line)
  }
}
