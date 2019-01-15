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
import Utility
import SKSwiftPMWorkspace

/// Represents the configuration and sate of a project or combination of projects being worked on
/// together.
///
/// In LSP, this represents the per-workspace state that is typically only available after the
/// "initialize" request has been made.
///
/// Typically a workspace is contained in a root directory.
public final class Workspace {

  /// The root directory of the workspace.
  public let rootPath: AbsolutePath?

  public let clientCapabilities: ClientCapabilities

  /// The build settings provider to use for documents in this workspace.
  public let buildSettings: BuildSystem

  /// Build setup
  public let buildSetup: BuildSetup

  /// The source code index, if available.
  public var index: IndexStoreDB? = nil

  /// Open documents.
  let documentManager: DocumentManager = DocumentManager()

  /// Language service for an open document, if available.
  var documentService: [URL: Connection] = [:]

  public init(
    rootPath: AbsolutePath?,
    clientCapabilities: ClientCapabilities,
    buildSettings: BuildSystem,
    index: IndexStoreDB?,
    buildSetup: BuildSetup)
  {
    self.rootPath = rootPath
    self.clientCapabilities = clientCapabilities
    self.buildSettings = buildSettings
    self.index = index
    self.buildSetup = buildSetup
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
    toolchainRegistry: ToolchainRegistry,
    buildSetup: BuildSetup
  ) throws {

    self.buildSetup = buildSetup

    self.rootPath = try AbsolutePath(validating: url.path)
    self.clientCapabilities = clientCapabilities
    let settings = BuildSystemList()
    self.buildSettings = settings

    settings.providers.insert(CompilationDatabaseBuildSystem(projectRoot: rootPath), at: 0)

    if let swiftpm = SwiftPMWorkspace(url: url,
                                      toolchainRegistry: toolchainRegistry,
                                      buildSetup: buildSetup
      ) {
      settings.providers.insert(swiftpm, at: 0)
    }

    if let storePath = buildSettings.indexStorePath,
       let dbPath = buildSettings.indexDatabasePath,
       let libPath = toolchainRegistry.default?.libIndexStore
    {
      do {
        let lib = try IndexStoreLibrary(dylibPath: libPath.asString)
        self.index = try IndexStoreDB(storePath: storePath.asString, databasePath: dbPath.asString, library: lib)
        log("opened IndexStoreDB at \(dbPath.asString) with store path \(storePath.asString)")
      } catch {
        log("failed to open IndexStoreDB: \(error.localizedDescription)", level: .error)
      }
    }
  }
}
