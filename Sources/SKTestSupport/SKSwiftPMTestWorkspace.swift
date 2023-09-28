//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKitLSP
import SKSwiftPMWorkspace
import LanguageServerProtocol
import SKCore
import IndexStoreDB
import ISDBTibs
import ISDBTestSupport
import XCTest
import Foundation
import LSPTestSupport

import class TSCBasic.Process
import func TSCBasic.resolveSymlinks
import struct TSCBasic.AbsolutePath
import struct PackageModel.BuildFlags

fileprivate extension SourceKitServer {
  func addWorkspace(_ workspace: Workspace) {
    self._workspaces.append(workspace)
  }
}

public final class SKSwiftPMTestWorkspace {

  /// The directory containing the original, unmodified project.
  public let projectDir: URL

  /// A test-specific directory that we can put temporary files into.
  public let tmpDir: URL

  /// The build directory.
  public let buildDir: URL

  /// The source files used by the test.
  public let sources: TestSources

  /// The source code index.
  public var index: IndexStoreDB

  /// The toolchain.
  public let toolchain: Toolchain

  /// Connection to the language server.
  public let testServer: TestSourceKitServer

  public var sk: TestClient { testServer.client }

  /// When `testServer` is not `nil`, the workspace will be opened in that server, otherwise a new server will be created for the workspace
  public init(projectDir: URL, tmpDir: URL, toolchain: Toolchain, testServer: TestSourceKitServer? = nil) async throws {
    self.testServer = testServer ?? TestSourceKitServer(connectionKind: .local)

    self.projectDir = URL(
      fileURLWithPath: try resolveSymlinks(AbsolutePath(validating: projectDir.path)).pathString
    )
    self.tmpDir = URL(
      fileURLWithPath: try resolveSymlinks(AbsolutePath(validating: tmpDir.path)).pathString
    )
    self.toolchain = toolchain

    let fm = FileManager.default
    _ = try? fm.removeItem(at: tmpDir)

    buildDir = tmpDir.appendingPathComponent("build", isDirectory: true)
    try fm.createDirectory(at: buildDir, withIntermediateDirectories: true, attributes: nil)
    let sourceDir = tmpDir.appendingPathComponent("src", isDirectory: true)
    try fm.copyItem(at: projectDir, to: sourceDir)
    let databaseDir = tmpDir.appendingPathComponent("db", isDirectory: true)
    try fm.createDirectory(at: databaseDir, withIntermediateDirectories: true, attributes: nil)

    self.sources = try TestSources(rootDirectory: sourceDir)

    let sourcePath = try AbsolutePath(validating: sources.rootDirectory.path)
    let buildPath = try AbsolutePath(validating: buildDir.path)
    let buildSetup = BuildSetup(configuration: .debug, path: buildPath, flags: BuildFlags())

    let swiftpm = try SwiftPMWorkspace(
      workspacePath: sourcePath,
      toolchainRegistry: ToolchainRegistry.shared,
      buildSetup: buildSetup)

    let libIndexStore = try IndexStoreLibrary(dylibPath: toolchain.libIndexStore!.pathString)

    try fm.createDirectory(atPath: swiftpm.indexStorePath!.pathString, withIntermediateDirectories: true)

    let indexDelegate = SourceKitIndexDelegate()

    self.index = try IndexStoreDB(
      storePath: swiftpm.indexStorePath!.pathString,
      databasePath: tmpDir.path,
      library: libIndexStore,
      delegate: indexDelegate,
      listenToUnitEvents: false)

    let server = self.testServer.server!
    let workspace = Workspace(
      documentManager: DocumentManager(),
      rootUri: DocumentURI(sources.rootDirectory),
      capabilityRegistry: CapabilityRegistry(clientCapabilities: ClientCapabilities()),
      toolchainRegistry: ToolchainRegistry.shared,
      buildSetup: buildSetup,
      underlyingBuildSystem: swiftpm,
      index: index,
      indexDelegate: indexDelegate)
    await workspace.buildSystemManager.setDelegate(server)
    await server.addWorkspace(workspace)
  }

  deinit {
    _ = try? FileManager.default.removeItem(atPath: tmpDir.path)
  }
}

extension SKSwiftPMTestWorkspace {

  public func testLoc(_ name: String) -> TestLocation { sources.locations[name]! }

  public func buildAndIndex(withSystemSymbols: Bool = false) throws {
    try build(withSystemSymbols: withSystemSymbols)
    index.pollForUnitChangesAndWait()
  }

  func build(withSystemSymbols: Bool = false) throws {
    var arguments = [
      toolchain.swift!.pathString,
      "build",
      "--package-path", sources.rootDirectory.path,
      "--scratch-path", buildDir.path,
    ]
    if !withSystemSymbols {
      arguments.append(contentsOf: [
        "-Xswiftc", "-index-ignore-system-modules",
        "-Xcc", "-index-ignore-system-symbols",
      ])
    }
    try TSCBasic.Process.checkNonZeroExit(arguments: arguments)
  }
}

extension SKSwiftPMTestWorkspace {
  public func openDocument(_ url: URL, language: Language) throws {
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: language,
      version: 1,
      text: try sources.sourceCache.get(url))))
  }

  public func closeDocument(_ url: URL) {
    sk.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(DocumentURI(url))))
  }
}

extension XCTestCase {

  public func staticSourceKitSwiftPMWorkspace(name: String, server: TestSourceKitServer? = nil) async throws -> SKSwiftPMTestWorkspace? {
    let testDirName = testDirectoryName
    let toolchain = ToolchainRegistry.shared.default!
    let workspace = try await SKSwiftPMTestWorkspace(
      projectDir: XCTestCase.sklspInputsDirectory.appendingPathComponent(name, isDirectory: true),
      tmpDir: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sk-test-data/\(testDirName)/\(name)", isDirectory: true),
      toolchain: toolchain,
      testServer: server
    )

    let hasClangFile: Bool = workspace.sources.locations.contains { _, loc in
      loc.url.pathExtension != "swift"
    }

    if hasClangFile {
      if toolchain.libIndexStore == nil {
        fputs("warning: skipping test because libIndexStore is missing;" +
              "install Clang's IndexStore component\n", stderr)
        return nil
      }
      if !TibsToolchain(toolchain).clangHasIndexSupport {
        fputs("warning: skipping test because '\(toolchain.clang!)' does not " +
              "have indexstore support; use swift-clang\n", stderr)
        return nil
      }
    }

    return workspace
  }
}
