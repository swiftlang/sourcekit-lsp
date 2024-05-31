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

import LSPLogging
import LanguageServerProtocol
import SKSupport

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

  /// A queue so we can have synchronous `startProgress` and `endProgress` functions that don't need to wait for the
  /// work done progress to be started or ended.
  private let queue = AsyncQueue<Serial>()

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
  nonisolated func startProgress(server: SourceKitLSPServer) {
    queue.async {
      await self.startProgressImpl(server: server)
    }
  }

  func startProgressImpl(server: SourceKitLSPServer) async {
    await server.waitUntilInitialized()
    activeTasks += 1
    guard await server.capabilityRegistry?.clientCapabilities.window?.workDoneProgress ?? false else {
      return
    }
    if state == .noProgress {
      state = .creating
      // Discard the handle. We don't support cancellation of the creation of a work done progress.
      _ = server.client.send(CreateWorkDoneProgressRequest(token: token)) { result in
        Task {
          await self.handleCreateWorkDoneProgressResponse(result, server: server)
        }
      }
    }
  }

  private func handleCreateWorkDoneProgressResponse(
    _ result: Result<VoidResponse, ResponseError>,
    server: SourceKitLSPServer
  ) {
    if result.success != nil {
      if self.activeTasks == 0 {
        // ActiveTasks might have been decreased while we created the `WorkDoneProgress`
        self.state = .noProgress
        server.client.send(WorkDoneProgress(token: self.token, value: .end(WorkDoneProgressEnd())))
      } else {
        self.state = .created
        server.client.send(
          WorkDoneProgress(token: self.token, value: .begin(WorkDoneProgressBegin(title: self.title)))
        )
      }
    } else {
      self.state = .progressCreationFailed
    }
  }

  /// End a new task stated using `startProgress`.
  ///
  /// If this drops the active task count to 0, the work done progress is ended on the client.
  ///
  /// - Parameter server: The server that is used to send and update of the `WorkDoneProgress` to the client
  nonisolated func endProgress(server: SourceKitLSPServer) {
    queue.async {
      await self.endProgressImpl(server: server)
    }
  }

  func endProgressImpl(server: SourceKitLSPServer) async {
    guard activeTasks > 0 else {
      logger.fault("Unbalanced startProgress/endProgress calls")
      return
    }
    activeTasks -= 1
    guard await server.capabilityRegistry?.clientCapabilities.window?.workDoneProgress ?? false else {
      return
    }
    if state == .created && activeTasks == 0 {
      server.client.send(WorkDoneProgress(token: token, value: .end(WorkDoneProgressEnd())))
      self.state = .noProgress
    }
  }
}
