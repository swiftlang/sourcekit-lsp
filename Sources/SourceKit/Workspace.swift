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
import LSPLogging
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
  public let rootUri: DocumentURI?

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
  var documentService: [DocumentURI: ToolchainLanguageServer] = [:]

  public init(
    rootUri: DocumentURI?,
    clientCapabilities: ClientCapabilities,
    toolchainRegistry: ToolchainRegistry,
    buildSetup: BuildSetup,
    underlyingBuildSystem: BuildSystem,
    index: IndexStoreDB?,
    indexDelegate: SourceKitIndexDelegate?)
  {
    self.buildSetup = buildSetup
    self.rootUri = rootUri
    self.clientCapabilities = clientCapabilities
    self.index = index
    let bsm = BuildSystemManager(buildSystem: underlyingBuildSystem, mainFilesProvider: index)
    indexDelegate?.registerMainFileChanged(bsm)
    self.buildSettings = bsm
  }

  /// Creates a workspace for a given root `URL`, inferring the `ExternalWorkspace` if possible.
  ///
  /// - Parameters:
  ///   - url: The root directory of the workspace, which must be a valid path.
  ///   - clientCapabilities: The client capabilities provided during server initialization.
  ///   - toolchainRegistry: The toolchain registry.
  convenience public init(
    rootUri: DocumentURI,
    clientCapabilities: ClientCapabilities,
    toolchainRegistry: ToolchainRegistry,
    buildSetup: BuildSetup,
    indexOptions: IndexOptions = IndexOptions()
  ) throws {

    let settings = BuildSystemList()
    if let rootUrl = rootUri.fileURL, let rootPath = try? AbsolutePath(validating: rootUrl.path) {
      if let buildServer = BuildServerBuildSystem(projectRoot: rootPath, buildSetup: buildSetup) {
        settings.providers.insert(buildServer, at: 0)
      } else {
        settings.providers.insert(CompilationDatabaseBuildSystem(projectRoot: rootPath), at: 0)
        if let swiftpm = SwiftPMWorkspace(url: rootUrl,
                                          toolchainRegistry: toolchainRegistry,
                                          buildSetup: buildSetup) {
          settings.providers.insert(swiftpm, at: 0)
        }
      }
    } else {
      // We assume that workspaces are directories. This is only true for URLs not for URIs in general.
      // Simply skip setting up the build integration in this case.
      log("cannot setup build integration for workspace at URI \(rootUri) because the URI it is not a valid file URL")
    }

    var index: IndexStoreDB? = nil
    var indexDelegate: SourceKitIndexDelegate? = nil

    if let storePath = indexOptions.indexStorePath ?? settings.indexStorePath,
       let dbPath = indexOptions.indexDatabasePath ?? settings.indexDatabasePath,
       let libPath = toolchainRegistry.default?.libIndexStore
    {
      do {
        let lib = try IndexStoreLibrary(dylibPath: libPath.pathString)
        indexDelegate = SourceKitIndexDelegate()
        index = try IndexStoreDB(
          storePath: storePath.pathString,
          databasePath: dbPath.pathString,
          library: lib,
          delegate: indexDelegate,
          listenToUnitEvents: indexOptions.listenToUnitEvents)
        log("opened IndexStoreDB at \(dbPath) with store path \(storePath)")
      } catch {
        log("failed to open IndexStoreDB: \(error.localizedDescription)", level: .error)
      }
    }

    self.init(
      rootUri: rootUri,
      clientCapabilities: clientCapabilities,
      toolchainRegistry: toolchainRegistry,
      buildSetup: buildSetup,
      underlyingBuildSystem: settings,
      index: index,
      indexDelegate: indexDelegate)
  }
}

public struct IndexOptions {

  /// Override the index-store-path provided by the build system.
  public var indexStorePath: AbsolutePath?

  /// Override the index-database-path provided by the build system.
  public var indexDatabasePath: AbsolutePath?

  /// *For Testing* Whether the index should listen to unit events, or wait for
  /// explicit calls to pollForUnitChangesAndWait().
  public var listenToUnitEvents: Bool

  public init(indexStorePath: AbsolutePath? = nil, indexDatabasePath: AbsolutePath? = nil, listenToUnitEvents: Bool = true) {
    self.listenToUnitEvents = listenToUnitEvents
  }
}
