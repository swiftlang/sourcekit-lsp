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

@_spi(SourceKitLSP) package import BuildServerProtocol
@_spi(SourceKitLSP) package import LanguageServerProtocol

/// Handles build server events, such as file build settings changes.
package protocol BuildServerManagerDelegate: AnyObject, Sendable {
  /// Notify the delegate that the result of `BuildServerManager.buildSettingsInferredFromMainFile` might have changed
  /// for the given files.
  func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async

  /// Notify the delegate that the dependencies of the given files have changed
  /// and that ASTs may need to be refreshed. If the given set is empty, assume
  /// that all watched files are affected.
  ///
  /// The callee should refresh ASTs unless it is able to determine that a
  /// refresh is not necessary.
  func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) async

  /// Notify the delegate that some information about the given build targets has changed and that it should recompute
  /// any information based on top of it.
  func buildTargetsChanged(_ changedTargets: Set<BuildTargetIdentifier>?) async

  func addBuiltTargetListener(_ listener: any BuildTargetListener)

  func removeBuiltTargetListener(_ listener: any BuildTargetListener)
}

package protocol BuildTargetListener: AnyObject, Sendable {
  /// Notify the listener that some information about the given build targets has changed and that it should recompute
  /// any information based on top of it.
  func buildTargetsChanged(_ changedTargets: Set<BuildTargetIdentifier>?) async
}

/// Methods with which the `BuildServerManager` can send messages to the client (aka. editor).
///
/// This is distinct from `BuildServerManagerDelegate` because the delegate only gets set on the build server after the
/// workspace that created it has been initialized (see `BuildServerManager.setDelegate`). But the `BuildServerManager`
/// can send notifications to the client immediately.
package protocol BuildServerManagerConnectionToClient: Sendable, Connection {
  /// Whether the client can handle `WorkDoneProgress` requests.
  var clientSupportsWorkDoneProgress: Bool { get async }

  /// Wait until the connection to the client has been initialized.
  ///
  /// No messages should be sent on this connection before this returns.
  func waitUntilInitialized() async

  /// Start watching for file changes with the given glob patterns.
  func watchFiles(_ fileWatchers: [FileSystemWatcher]) async

  /// Log a message in the client's index log.
  func logMessageToIndexLog(
    message: String,
    type: WindowMessageType,
    structure: LanguageServerProtocol.StructuredLogKind?
  )
}
