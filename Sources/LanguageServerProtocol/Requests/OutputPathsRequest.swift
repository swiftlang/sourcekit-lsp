//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request from the client to the server to retrieve the output paths of a target (see the `buildTarget/outputPaths`
/// BSP request).
///
/// **(LSP Extension)**.
public struct OutputPathsRequest: LSPRequest, Hashable {
  public static let method: String = "workspace/_outputPaths"
  public typealias Response = OutputPathsResponse

  /// The target whose output file paths to get.
  public var target: DocumentURI

  /// The URI of the workspace to which the target belongs.
  public var workspace: DocumentURI

  public init(target: DocumentURI, workspace: DocumentURI) {
    self.target = target
    self.workspace = workspace
  }
}
public struct OutputPathsResponse: ResponseType, Hashable {
  /// The output paths for all source files in the target
  public var outputPaths: [String]

  public init(outputPaths: [String]) {
    self.outputPaths = outputPaths
  }
}
