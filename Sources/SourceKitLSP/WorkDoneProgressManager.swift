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
import LanguageServerProtocol
import SKSupport
import SwiftExtensions

/// Represents a single `WorkDoneProgress` task that gets communicated with the client.
///
/// The work done progress is started when the object is created and ended when the object is destroyed.
/// In between, updates can be sent to the client.
final class WorkDoneProgressManager {
  private let token: ProgressToken
  private let queue = AsyncQueue<Serial>()
  private let server: SourceKitLSPServer
  /// `true` if the client returned without an error from the `CreateWorkDoneProgressRequest`.
  ///
  /// Since all work done progress reports are being sent on `queue`, we never access it in a state where the
  /// `CreateWorkDoneProgressRequest` is still in progress.
  ///
  /// Must be a reference because `deinit` captures it and wants to observe changes to it from `init` eg. in the
  /// following:
  ///  - `init` is called
  ///  - `deinit` is called
  ///  - The task from `init` gets executed
  ///  - The task from `deinit` gets executed
  ///    - This should have `workDoneProgressCreated == true` so that it can send the work progress end.
  private let workDoneProgressCreated: ThreadSafeBox<Bool> & AnyObject = ThreadSafeBox<Bool>(initialValue: false)

  /// The last message and percentage so we don't send a new report notification to the client if `update` is called
  /// without any actual change.
  private var lastStatus: (message: String?, percentage: Int?)

  convenience init?(server: SourceKitLSPServer, title: String, message: String? = nil, percentage: Int? = nil) async {
    guard let capabilityRegistry = await server.capabilityRegistry else {
      return nil
    }
    self.init(server: server, capabilityRegistry: capabilityRegistry, title: title, message: message)
  }

  init?(
    server: SourceKitLSPServer,
    capabilityRegistry: CapabilityRegistry,
    title: String,
    message: String? = nil,
    percentage: Int? = nil
  ) {
    guard capabilityRegistry.clientCapabilities.window?.workDoneProgress ?? false else {
      return nil
    }
    self.token = .string("WorkDoneProgress-\(UUID())")
    self.server = server
    queue.async { [server, token, workDoneProgressCreated] in
      await server.waitUntilInitialized()
      do {
        _ = try await server.client.send(CreateWorkDoneProgressRequest(token: token))
      } catch {
        return
      }
      server.sendNotificationToClient(
        WorkDoneProgress(
          token: token,
          value: .begin(WorkDoneProgressBegin(title: title, message: message, percentage: percentage))
        )
      )
      workDoneProgressCreated.value = true
      self.lastStatus = (message, percentage)
    }
  }

  func update(message: String? = nil, percentage: Int? = nil) {
    queue.async { [server, token, workDoneProgressCreated] in
      guard workDoneProgressCreated.value else {
        return
      }
      guard (message, percentage) != self.lastStatus else {
        return
      }
      self.lastStatus = (message, percentage)
      server.sendNotificationToClient(
        WorkDoneProgress(
          token: token,
          value: .report(WorkDoneProgressReport(cancellable: false, message: message, percentage: percentage))
        )
      )
    }
  }

  deinit {
    queue.async { [server, token, workDoneProgressCreated] in
      guard workDoneProgressCreated.value else {
        return
      }
      server.sendNotificationToClient(WorkDoneProgress(token: token, value: .end(WorkDoneProgressEnd())))
    }
  }
}
