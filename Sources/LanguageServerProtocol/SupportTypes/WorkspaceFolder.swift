//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The configuration to build a workspace in.
///
/// **(LSP Extension)**
public enum BuildConfiguration: Hashable, Codable, Sendable {
  case debug
  case release
}

/// The type of workspace; default workspace type selection logic can be overridden.
///
/// **(LSP Extension)**
public enum WorkspaceType: Hashable, Codable, Sendable {
  case buildServer, compilationDatabase, swiftPM
}

/// Build settings that should be used for a workspace.
///
/// **(LSP Extension)**
public struct WorkspaceBuildSetup: Hashable, Codable, Sendable {
  /// The configuration that the workspace should be built in.
  public let buildConfiguration: BuildConfiguration?

  /// The default workspace type to use for this workspace.
  public let defaultWorkspaceType: WorkspaceType?

  /// The build directory for the workspace.
  public let scratchPath: DocumentURI?

  /// Arguments to be passed to any C compiler invocations.
  public let cFlags: [String]?

  /// Arguments to be passed to any C++ compiler invocations.
  public let cxxFlags: [String]?

  /// Arguments to be passed to any linker invocations.
  public let linkerFlags: [String]?

  /// Arguments to be passed to any Swift compiler invocations.
  public let swiftFlags: [String]?

  public init(
    buildConfiguration: BuildConfiguration? = nil,
    defaultWorkspaceType: WorkspaceType? = nil,
    scratchPath: DocumentURI? = nil,
    cFlags: [String]? = nil,
    cxxFlags: [String]? = nil,
    linkerFlags: [String]? = nil,
    swiftFlags: [String]? = nil
  ) {
    self.buildConfiguration = buildConfiguration
    self.defaultWorkspaceType = defaultWorkspaceType
    self.scratchPath = scratchPath
    self.cFlags = cFlags
    self.cxxFlags = cxxFlags
    self.linkerFlags = linkerFlags
    self.swiftFlags = swiftFlags
  }
}

/// Unique identifier for a document.
public struct WorkspaceFolder: ResponseType, Hashable, Codable, Sendable {

  /// A URI that uniquely identifies the workspace.
  public var uri: DocumentURI

  /// The name of the workspace (default: basename of url).
  public var name: String

  /// Build settings that should be used for this workspace.
  ///
  /// For arguments that have a single value (like the build configuration), this takes precedence over the global
  /// options set when launching sourcekit-lsp. For all other options, the values specified in the workspace-specific
  /// build setup are appended to the global options.
  ///
  /// **(LSP Extension)**
  public var buildSetup: WorkspaceBuildSetup?

  public init(
    uri: DocumentURI,
    name: String? = nil,
    buildSetup: WorkspaceBuildSetup? = nil
  ) {
    self.uri = uri

    self.name = name ?? uri.fileURL?.lastPathComponent ?? "unknown_workspace"

    if self.name.isEmpty {
      self.name = "unknown_workspace"
    }
    self.buildSetup = buildSetup
  }
}
