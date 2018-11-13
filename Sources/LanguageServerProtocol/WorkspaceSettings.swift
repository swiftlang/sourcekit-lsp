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

/// The `settings` field of a `workspace/didChangeConfiguration`. This is typed as `Any` in the protocol, and this enum contains the formats we support.
public enum WorkspaceSettingsChange: Codable, Hashable {

  case clangd(ClangWorkspaceSettings)
  case unknown

  public init(from decoder: Decoder) throws {
    // FIXME: doing trial deserialization only works if we have at least one non-optional unique key, which we don't yet.  For now, assume that if we add another kind of workspace settings it will rectify this issue.
    if let settings = try? ClangWorkspaceSettings(from: decoder) {
      self = .clangd(settings)
    } else {
      self = .unknown
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .clangd(let settings):
      try settings.encode(to: encoder)
    case .unknown:
      break // Nothing to do.
    }
  }
}

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

public struct ClangCompileCommand: Codable, Hashable {

  public var compilationCommand: [String]

  public var workingDirectory: String

  public init(compilationCommand: [String], workingDirectory: String) {
    self.compilationCommand = compilationCommand
    self.workingDirectory = workingDirectory
  }
}
