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

public import LanguageServerProtocol

/// The workspace build targets request is sent from the client to the server to
/// ask for the list of all available build targets in the workspace.
public struct WorkspaceBuildTargetsRequest: BSPRequest, Hashable {
  public static let method: String = "workspace/buildTargets"
  public typealias Response = WorkspaceBuildTargetsResponse

  public init() {}
}

public struct WorkspaceBuildTargetsResponse: ResponseType, Hashable {
  /// The build targets in this workspace that contain sources with the given language ids.
  public var targets: [BuildTarget]

  public init(targets: [BuildTarget]) {
    self.targets = targets
  }
}
