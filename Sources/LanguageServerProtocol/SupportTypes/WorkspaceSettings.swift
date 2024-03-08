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
public enum WorkspaceSettingsChange: Codable, Hashable, Sendable {

  case clangd(ClangWorkspaceSettings)
  case unknown(LSPAny)

  public init(from decoder: Decoder) throws {
    if let settings = try? ClangWorkspaceSettings(from: decoder), settings.isValid {
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
    case .unknown(let settings):
      try settings.encode(to: encoder)
    }
  }
}

/// Workspace settings for clangd, represented by a compilation database.
///
/// Clangd will accept *either* a path to a compilation database on disk, or the contents of a
/// compilation database to be managed in-memory, but they cannot be mixed.
public struct ClangWorkspaceSettings: Codable, Hashable, Sendable {

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

  var isValid: Bool {
    switch (compilationDatabasePath, compilationDatabaseChanges) {
    case (nil, .some), (.some, nil): return true
    default: return false
    }
  }
}

/// A single compile command for use in a clangd workspace settings.
public struct ClangCompileCommand: Codable, Hashable, Sendable {

  /// The command (executable + compiler arguments).
  public var compilationCommand: [String]

  /// The directory to perform the compilation in.
  public var workingDirectory: String

  public init(compilationCommand: [String], workingDirectory: String) {
    self.compilationCommand = compilationCommand
    self.workingDirectory = workingDirectory
  }
}
