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

/// Wait for SourceKit-LSP to handle all ongoing requests and, optionally, wait for background activity to finish.
///
/// **LSP Extension, For Testing**.
public struct SynchronizeRequest: RequestType {
  public static let method: String = "workspace/_synchronize"
  public typealias Response = VoidResponse

  /// Wait for the build server to have an up-to-date build graph by sending a `workspace/waitForBuildSystemUpdates` to
  /// it.
  public var buildServerUpdates: Bool?

  /// Wait for background indexing to finish and all index unit files to be loaded into indexstore-db.
  ///
  /// Implies `buildServerUpdates = true`.
  public var index: Bool?

  public init(buildServerUpdates: Bool? = nil, index: Bool? = nil) {
    self.buildServerUpdates = buildServerUpdates
    self.index = index
  }
}
