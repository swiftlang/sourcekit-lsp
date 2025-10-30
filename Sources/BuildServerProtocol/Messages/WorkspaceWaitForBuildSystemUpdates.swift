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

public import LanguageServerProtocol

/// This request is a no-op and doesn't have any effects.
///
/// If the build server is currently updating the build graph, this request should return after those updates have
/// finished processing.
public struct WorkspaceWaitForBuildSystemUpdatesRequest: BSPRequest, Hashable {
  public typealias Response = VoidResponse

  public static let method: String = "workspace/waitForBuildSystemUpdates"

  public init() {}
}
