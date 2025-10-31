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

/// Request from the client to the server to wait for SourceKit-LSP to handle all ongoing requests and, optionally, wait
/// for background activity to finish.
///
/// This method is intended to be used in automated environments which need to wait for background activity to finish
/// before executing requests that rely on that background activity to finish. Examples of such cases are:
/// - Automated tests that need to wait for background indexing to finish and then checking the result of request
///   results
/// - Automated tests that need to wait for requests like file changes to be handled and checking behavior after those
///   have been processed
/// - Code analysis tools that want to use SourceKit-LSP to gather information about the project but can only do so
///   after the index has been loaded
///
/// Because this request waits for all other SourceKit-LSP requests to finish, it limits parallel request handling and
/// is ill-suited for any kind of interactive environment. In those environments, it is preferable to quickly give the
/// user a result based on the data that is available and (let the user) re-perform the action if the underlying index
/// data has changed.
public struct SynchronizeRequest: LSPRequest {
  public static let method: String = "workspace/synchronize"
  public typealias Response = VoidResponse

  /// Wait for the build server to have an up-to-date build graph by sending a `workspace/waitForBuildSystemUpdates` to
  /// it.
  /// This is implied by `index = true`.
  ///
  /// This option is experimental, guarded behind the `synchronize-for-build-system-updates` experimental feature, and
  /// may be modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.
  public var buildServerUpdates: Bool?

  /// Wait for the build server to update its internal mapping of copied files to their original location.
  ///
  /// This option is experimental, guarded behind the `synchronize-copy-file-map` experimental feature, and may be
  /// modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.
  public var copyFileMap: Bool?

  /// Wait for background indexing to finish and all index unit files to be loaded into indexstore-db.
  public var index: Bool?

  public init(buildServerUpdates: Bool? = nil, copyFileMap: Bool? = nil, index: Bool? = nil) {
    self.buildServerUpdates = buildServerUpdates
    self.copyFileMap = copyFileMap
    self.index = index
  }
}
