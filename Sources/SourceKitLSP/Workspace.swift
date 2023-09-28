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

import struct TSCBasic.AbsolutePath

/// Same as `??` but allows the right-hand side of the operator to 'await'.
fileprivate func firstNonNil<T>(_ optional: T?, _ defaultValue: @autoclosure () async throws -> T) async rethrows -> T {
  if let optional {
    return optional
  }
  return try await defaultValue()
}


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

  /// Tracks dynamically registered server capabilities as well as the client's capabilities.
  public let capabilityRegistry: CapabilityRegistry

  /// The build system manager to use for documents in this workspace.
  public let buildSystemManager: BuildSystemManager

  /// Build setup
  public let buildSetup: BuildSetup

  /// The source code index, if available.
  public var index: IndexStoreDB? = nil

  /// Documents open in the SourceKitServer. This may include open documents from other workspaces.
  private let documentManager: DocumentManager

  /// Language service for an open document, if available.
  var documentService: [DocumentURI: ToolchainLanguageServer] = [:]

  public init(
    documentManager: DocumentManager,
    rootUri: DocumentURI?,
    capabilityRegistry: CapabilityRegistry,
    toolchainRegistry: ToolchainRegistry,
    buildSetup: BuildSetup,
    underlyingBuildSystem: BuildSystem?,
    index: IndexStoreDB?,
    indexDelegate: SourceKitIndexDelegate?
  ) async {
    self.documentManager = documentManager
    self.buildSetup = buildSetup
    self.rootUri = rootUri
    self.capabilityRegistry = capabilityRegistry
    self.index = index
    self.buildSystemManager = await BuildSystemManager(
      buildSystem: underlyingBuildSystem,
      fallbackBuildSystem: FallbackBuildSystem(buildSetup: buildSetup),
      mainFilesProvider: index)
    indexDelegate?.registerMainFileChanged(buildSystemManager)
  }

  /// Creates a workspace for a given root `URL`, inferring the `ExternalWorkspace` if possible.
  ///
  /// - Parameters:
  ///   - url: The root directory of the workspace, which must be a valid path.
  ///   - clientCapabilities: The client capabilities provided during server initialization.
  ///   - toolchainRegistry: The toolchain registry.
  convenience public init(
    documentManager: DocumentManager,
    rootUri: DocumentURI,
    capabilityRegistry: CapabilityRegistry,
    toolchainRegistry: ToolchainRegistry,
    buildSetup: BuildSetup,
    indexOptions: IndexOptions = IndexOptions(),
    reloadPackageStatusCallback: @escaping (ReloadPackageStatus) -> Void
  ) async throws {
    var buildSystem: BuildSystem? = nil
    if let rootUrl = rootUri.fileURL, let rootPath = try? AbsolutePath(validating: rootUrl.path) {
      if let buildServer = BuildServerBuildSystem(projectRoot: rootPath, buildSetup: buildSetup) {
        buildSystem = buildServer
      } else if let swiftpm = await SwiftPMWorkspace(
        url: rootUrl,
        toolchainRegistry: toolchainRegistry,
        buildSetup: buildSetup,
        reloadPackageStatusCallback: reloadPackageStatusCallback
      ) {
        buildSystem = swiftpm
      } else {
        buildSystem = CompilationDatabaseBuildSystem(projectRoot: rootPath)
      }
    } else {
      // We assume that workspaces are directories. This is only true for URLs not for URIs in general.
      // Simply skip setting up the build integration in this case.
      log("cannot setup build integration for workspace at URI \(rootUri) because the URI it is not a valid file URL")
    }

    var index: IndexStoreDB? = nil
    var indexDelegate: SourceKitIndexDelegate? = nil

    if let storePath = await firstNonNil(indexOptions.indexStorePath, await buildSystem?.indexStorePath),
       let dbPath = await firstNonNil(indexOptions.indexDatabasePath, await buildSystem?.indexDatabasePath),
       let libPath = toolchainRegistry.default?.libIndexStore
    {
      do {
        let lib = try IndexStoreLibrary(dylibPath: libPath.pathString)
        indexDelegate = SourceKitIndexDelegate()
        let prefixMappings = await firstNonNil(indexOptions.indexPrefixMappings, await buildSystem?.indexPrefixMappings) ?? []
        index = try IndexStoreDB(
          storePath: storePath.pathString,
          databasePath: dbPath.pathString,
          library: lib,
          delegate: indexDelegate,
          listenToUnitEvents: indexOptions.listenToUnitEvents,
          prefixMappings: prefixMappings.map { PathMapping(original: $0.original, replacement: $0.replacement) })
        log("opened IndexStoreDB at \(dbPath) with store path \(storePath)")
      } catch {
        log("failed to open IndexStoreDB: \(error.localizedDescription)", level: .error)
      }
    }

    await self.init(
      documentManager: documentManager,
      rootUri: rootUri,
      capabilityRegistry: capabilityRegistry,
      toolchainRegistry: toolchainRegistry,
      buildSetup: buildSetup,
      underlyingBuildSystem: buildSystem,
      index: index,
      indexDelegate: indexDelegate)
  }
}

/// Wrapper around a workspace that isn't being retained.
struct WeakWorkspace {
  weak var value: Workspace?

  init(_ value: Workspace? = nil) {
    self.value = value
  }
}

public struct IndexOptions {

  /// Override the index-store-path provided by the build system.
  public var indexStorePath: AbsolutePath?

  /// Override the index-database-path provided by the build system.
  public var indexDatabasePath: AbsolutePath?

  /// Override the index prefix mappings provided by the build system.
  public var indexPrefixMappings: [PathPrefixMapping]?

  /// *For Testing* Whether the index should listen to unit events, or wait for
  /// explicit calls to pollForUnitChangesAndWait().
  public var listenToUnitEvents: Bool

  public init(
    indexStorePath: AbsolutePath? = nil,
    indexDatabasePath: AbsolutePath? = nil,
    indexPrefixMappings: [PathPrefixMapping]? = nil,
    listenToUnitEvents: Bool = true
  ) {
    self.indexStorePath = indexStorePath
    self.indexDatabasePath = indexDatabasePath
    self.indexPrefixMappings = indexPrefixMappings
    self.listenToUnitEvents = listenToUnitEvents
  }
}
