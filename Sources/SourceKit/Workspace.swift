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

import LanguageServerProtocol
import SKCore
import SKSupport
import IndexStoreDB
import Basic
import SKSwiftPMWorkspace

/// Represents the configuration and sate of a project or combination of projects being worked on
/// together.
///
/// In LSP, this represents the per-workspace state that is typically only available after the
/// "initialize" request has been made.
///
/// Typically a workspace is contained in a root directory.
public final class Workspace {

  /// Workspace configuration per root path
  public struct Configuration {

    /// The root directory of the workspace.
    public var rootPath: AbsolutePath? = nil

    /// The build settings provider to use for documents in this workspace.
    public var buildSettings: BuildSystem

    /// The index to use for documents in this worspace.
    public var index: IndexStoreDB? = nil

    init(rootPath: AbsolutePath? = nil, buildSettings: BuildSystem, index: IndexStoreDB? = nil) {
      self.rootPath = rootPath
      self.buildSettings = buildSettings
      self.index = index
    }
  }

  public let configuration: Configuration

  public let clientCapabilities: ClientCapabilities

  /// Open documents.
  let documentManager: DocumentManager = DocumentManager()

  /// Language service for an open document, if available.
  var documentService: [URL: Connection] = [:]

  public init(
    rootPath: AbsolutePath?,
    clientCapabilities: ClientCapabilities,
    buildSettings: BuildSystem,
    index: IndexStoreDB?)
  {
    self.configuration = Configuration(rootPath: rootPath, buildSettings: buildSettings, index: index)
    self.clientCapabilities = clientCapabilities
  }

  /// Creates a workspace for a given root `URL`, inferring the `ExternalWorkspace` if possible.
  ///
  /// - Parameters:
  ///   - url: The root directory of the workspace, which must be a valid path.
  ///   - clientCapabilities: The client capabilities provided during server initialization.
  ///   - toolchainRegistry: The toolchain registry.
  public init(
    url: URL,
    clientCapabilities: ClientCapabilities,
    toolchainRegistry: ToolchainRegistry
  ) throws {
    self.clientCapabilities = clientCapabilities

    let rootPath = try AbsolutePath(validating: url.path)
    let settings = BuildSystemList()

    settings.providers.insert(CompilationDatabaseBuildSystem(projectRoot: rootPath), at: 0)

    if let swiftpm = SwiftPMWorkspace(url: url, toolchainRegistry: toolchainRegistry) {
      settings.providers.insert(swiftpm, at: 0)
    }

    var index: IndexStoreDB? = nil
    if let storePath = settings.indexStorePath,
       let dbPath = settings.indexDatabasePath,
       let libPath = toolchainRegistry.default?.libIndexStore
    {
      do {
        let lib = try IndexStoreLibrary(dylibPath: libPath.asString)
        index = try IndexStoreDB(storePath: storePath.asString, databasePath: dbPath.asString, library: lib)
        log("opened IndexStoreDB at \(dbPath.asString) with store path \(storePath.asString)")
      } catch {
        log("failed to open IndexStoreDB: \(error.localizedDescription)", level: .error)
      }
    }

    self.configuration = Configuration(rootPath: rootPath, buildSettings: settings, index: index)
  }
}
