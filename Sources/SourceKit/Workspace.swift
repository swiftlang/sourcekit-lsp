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

import IndexStoreDB
import LanguageServerProtocol
import LSPSupport
import SKCore
import SKSupport
import SKSwiftPMWorkspace
import TSCBasic
import TSCUtility

/// Represents the configuration and state of a project or combination of projects being worked on
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
  public let documentManager: DocumentManager = DocumentManager()

  /// Language service for an open document, if available.
  var documentService: [URL: ToolchainLanguageServer] = [:]

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
    buildSetup: BuildSetup,
    indexOptions: IndexOptions = IndexOptions()
  ) throws {

    self.buildSetup = buildSetup

    self.rootPath = try AbsolutePath(validating: url.path)
    self.clientCapabilities = clientCapabilities
    let settings = BuildSystemList()
    self.buildSettings = settings

    if let buildServer = BuildServerBuildSystem(projectRoot: rootPath, buildSetup: buildSetup) {
      settings.providers.insert(buildServer, at: 0)
    } else {
      settings.providers.insert(CompilationDatabaseBuildSystem(projectRoot: rootPath), at: 0)
      if let swiftpm = SwiftPMWorkspace(url: url,
                                        toolchainRegistry: toolchainRegistry,
                                        buildSetup: buildSetup) {
        settings.providers.insert(swiftpm, at: 0)
      }
    }

    if let storePath = buildSettings.indexStorePath,
       let dbPath = buildSettings.indexDatabasePath,
       let libPath = toolchainRegistry.default?.libIndexStore
    {
      do {
        let lib = try IndexStoreLibrary(dylibPath: libPath.pathString)
        self.index = try IndexStoreDB(
          storePath: storePath.pathString,
          databasePath: dbPath.pathString,
          library: lib,
          listenToUnitEvents: indexOptions.listenToUnitEvents)
        log("opened IndexStoreDB at \(dbPath) with store path \(storePath)")
      } catch {
        log("failed to open IndexStoreDB: \(error.localizedDescription)", level: .error)
      }
    }
  }
}

public struct IndexOptions {

  /// *For Testing* Whether the index should listen to unit events, or wait for
  /// explicit calls to pollForUnitChangesAndWait().
  public var listenToUnitEvents: Bool

  public init(listenToUnitEvents: Bool = true) {
    self.listenToUnitEvents = listenToUnitEvents
  }
}
