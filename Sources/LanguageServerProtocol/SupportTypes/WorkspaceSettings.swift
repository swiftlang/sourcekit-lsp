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

/// The `settings` field of a `workspace/didChangeConfiguration`.
///
/// This is typed as `Any` in the protocol, and this enum contains the formats we support.
public enum WorkspaceSettingsChange: Codable, Hashable {
  
  private enum CodingKeys: String, CodingKey {
    case sourcekitlsp = "sourcekit-lsp"
  }

  case clangd(ClangWorkspaceSettings)
  case sourcekitlsp(SourceKitLSPWorkspaceSettings)
  case unknown(LSPAny)

  public init(from decoder: Decoder) throws {
    // FIXME: doing trial deserialization only works if we have at least one non-optional unique
    // key, which we don't yet.  For now, assume that if we add another kind of workspace settings
    // it will rectify this issue.
    if let container = try? decoder.container(keyedBy: CodingKeys.self),
       let settings = try? container.decode(SourceKitLSPWorkspaceSettings.self, forKey: .sourcekitlsp) {
      self = .sourcekitlsp(settings)
    } else if let settings = try? ClangWorkspaceSettings(from: decoder) {
      self = .clangd(settings)
    } else {
      let settings = try LSPAny(from: decoder)
      self = .unknown(settings)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .clangd(let settings):
      try settings.encode(to: encoder)
    case .sourcekitlsp(let settings):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(settings, forKey: .sourcekitlsp)
    case .unknown(let settings):
      try settings.encode(to: encoder)
    }
  }
}

/// Workspace settings for clangd, represented by a compilation database.
///
/// Clangd will accept *either* a path to a compilation database on disk, or the contents of a
/// compilation database to be managed in-memory, but they cannot be mixed.
public struct ClangWorkspaceSettings: Codable, Hashable {

  /// The path to a json compilation database.
  public var compilationDatabasePath: String?

  /// Mapping from file name to compilation command.
  public var compilationDatabaseChanges: [String: ClangCompileCommand]?

  public init(
    compilationDatabasePath: String? = nil,
    compilationDatabaseChanges: [String: ClangCompileCommand]? = nil
  ) {
    self.compilationDatabasePath = compilationDatabasePath
    self.compilationDatabaseChanges = compilationDatabaseChanges
  }
}

/// A single compile command for use in a clangd workspace settings.
public struct ClangCompileCommand: Codable, Hashable {

  /// The command (executable + compiler arguments).
  public var compilationCommand: [String]

  /// The directory to perform the compilation in.
  public var workingDirectory: String

  public init(compilationCommand: [String], workingDirectory: String) {
    self.compilationCommand = compilationCommand
    self.workingDirectory = workingDirectory
  }
}

public struct SourceKitLSPWorkspaceSettings: Codable, Hashable {
  
  /// Index visibility setting
  /// This affects indexing scope when explicit index visibility is enabled
  public var indexVisibility: IndexVisibility? = nil

  public init(indexVisibility: IndexVisibility?) {
    if let indexVisibility = indexVisibility {
      self.indexVisibility = indexVisibility
    } else {
      // nil is equivalent to no index visibility
      self.indexVisibility = IndexVisibility(targets: [], includeTargetDependencies: false)
    }
  }
}

/// Index visibility setting, represented by a list of target identifiers and whether the index of transparent target dependencies should be visibile
public struct IndexVisibility: Codable, Hashable {

  /// all targets included in the scheme
  public var targets: [BuildTargetIdentifier]
  public var includeTargetDependencies: Bool
  
  public init(targets: [BuildTargetIdentifier], includeTargetDependencies: Bool) {
    self.targets = targets
    self.includeTargetDependencies = includeTargetDependencies
  }
}

public struct BuildTargetIdentifier: Codable, Hashable {
  public var uri: DocumentURI

  public init(uri: DocumentURI) {
    self.uri = uri
  }
}
