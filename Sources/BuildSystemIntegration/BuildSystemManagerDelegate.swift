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

#if compiler(>=6)
package import BuildServerProtocol
package import LanguageServerProtocol
#else
import BuildServerProtocol
import LanguageServerProtocol
#endif

/// Handles build system events, such as file build settings changes.
package protocol BuildSystemManagerDelegate: AnyObject, Sendable {
  /// Notify the delegate that the result of `BuildSystemManager.buildSettingsInferredFromMainFile` might have changed
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
  func buildTargetsChanged(_ changes: [BuildTargetEvent]?) async
}

/// Methods with which the `BuildSystemManager` can send messages to the client (aka. editor).
///
/// This is distinct from `BuildSystemManagerDelegate` because the delegate only gets set on the build system after the
/// workspace that created it has been initialized (see `BuildSystemManager.setDelegate`). But the `BuildSystemManager`
/// can send notifications to the client immediately.
package protocol BuildSystemManagerConnectionToClient: Sendable, Connection {
  /// Whether the client can handle `WorkDoneProgress` requests.
  var clientSupportsWorkDoneProgress: Bool { get async }

  /// Wait until the connection to the client has been initialized.
  ///
  /// No messages should be sent on this connection before this returns.
  func waitUntilInitialized() async

  /// Start watching for file changes with the given glob patterns.
  func watchFiles(_ fileWatchers: [FileSystemWatcher]) async
}
