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

import SourceKit
import LanguageServerProtocol
import SKCore
import IndexStoreDB
import ISDBTibs
import ISDBTestSupport
import TSCBasic
import TSCUtility
import XCTest
import Foundation
import LSPTestSupport

public typealias URL = Foundation.URL

public final class SKTibsTestWorkspace {

  public let tibsWorkspace: TibsTestWorkspace
  public let testServer = TestSourceKitServer(connectionKind: .local)

  public var index: IndexStoreDB { tibsWorkspace.index }
  public var builder: TibsBuilder { tibsWorkspace.builder }
  public var sources: TestSources { tibsWorkspace.sources }
  public var sk: TestClient { testServer.client }

  public init(
    immutableProjectDir: URL,
    persistentBuildDir: URL,
    tmpDir: URL,
    removeTmpDir: Bool,
    toolchain: Toolchain,
    clientCapabilities: ClientCapabilities) throws
  {
    self.tibsWorkspace = try TibsTestWorkspace(
      immutableProjectDir: immutableProjectDir,
      persistentBuildDir: persistentBuildDir,
      tmpDir: tmpDir,
      removeTmpDir: removeTmpDir,
      toolchain: TibsToolchain(toolchain))

    initWorkspace(clientCapabilities: clientCapabilities)
  }

  public init(projectDir: URL, tmpDir: URL, toolchain: Toolchain, clientCapabilities: ClientCapabilities) throws {
    self.tibsWorkspace = try TibsTestWorkspace(
      projectDir: projectDir,
      tmpDir: tmpDir,
      toolchain: TibsToolchain(toolchain))

    initWorkspace(clientCapabilities: clientCapabilities)
  }

  func initWorkspace(clientCapabilities: ClientCapabilities) {
    let buildPath = AbsolutePath(builder.buildRoot.path)
    let buildSystem = CompilationDatabaseBuildSystem(projectRoot: buildPath)
    let indexDelegate = SourceKitIndexDelegate()
    tibsWorkspace.delegate = indexDelegate

    testServer.server!.workspace = Workspace(
      rootUri: DocumentURI(sources.rootDirectory),
      clientCapabilities: clientCapabilities,
      toolchainRegistry: ToolchainRegistry.shared,
      buildSetup: BuildSetup(configuration: .debug, path: buildPath, flags: BuildFlags()),
      underlyingBuildSystem: buildSystem,
      index: index,
      indexDelegate: indexDelegate)

    testServer.server!.workspace!.buildSettings.delegate = testServer.server!
  }
}

extension SKTibsTestWorkspace {

  public func testLoc(_ name: String) -> TestLocation { sources.locations[name]! }

  public func buildAndIndex() throws {
    try tibsWorkspace.buildAndIndex()
  }

  /// Perform a group of edits to the project sources and optionally rebuild.
  public func edit(
    rebuild: Bool = false,
    _ block: (inout TestSources.ChangeBuilder, _ current: SourceFileCache) throws -> ()) throws
  {
    try tibsWorkspace.edit(rebuild: rebuild, block)
  }
}

extension SKTibsTestWorkspace {
  public func openDocument(_ url: URL, language: Language) throws {
    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: DocumentURI(url),
      language: language,
      version: 1,
      text: try sources.sourceCache.get(url))))
  }
}

extension XCTestCase {

  public func staticSourceKitTibsWorkspace(
    name: String,
    clientCapabilities: ClientCapabilities = .init(),
    tmpDir: URL? = nil,
    removeTmpDir: Bool = true,
    testFile: String = #file
  ) throws -> SKTibsTestWorkspace? {
    let testDirName = testDirectoryName
    let workspace = try SKTibsTestWorkspace(
      immutableProjectDir: inputsDirectory(testFile: testFile)
        .appendingPathComponent(name, isDirectory: true),
      persistentBuildDir: XCTestCase.productsDirectory
        .appendingPathComponent("sk-tests/\(testDirName)", isDirectory: true),
      tmpDir: tmpDir ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sk-test-data/\(testDirName)", isDirectory: true),
      removeTmpDir: removeTmpDir,
      toolchain: ToolchainRegistry.shared.default!,
      clientCapabilities: clientCapabilities)

    if workspace.builder.targets.contains(where: { target in !target.clangTUs.isEmpty })
      && !workspace.builder.toolchain.clangHasIndexSupport {
      fputs("warning: skipping test because '\(workspace.builder.toolchain.clang.path)' does not " +
            "have indexstore support; use swift-clang\n", stderr)
      return nil
    }

    return workspace
  }

  /// Constructs a mutable SKTibsTestWorkspace for the given test from INPUTS.
  ///
  /// The resulting workspace allow edits and is not persistent.
  public func mutableSourceKitTibsTestWorkspace(
    name: String,
    clientCapabilities: ClientCapabilities = .init(),
    tmpDir: URL? = nil,
    testFile: String = #file
  ) throws -> SKTibsTestWorkspace? {
    let testDirName = testDirectoryName
    let workspace = try SKTibsTestWorkspace(
      projectDir: inputsDirectory(testFile: testFile)
        .appendingPathComponent(name, isDirectory: true),
      tmpDir: tmpDir ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sk-test-data/\(testDirName)", isDirectory: true),
      toolchain: ToolchainRegistry.shared.default!,
      clientCapabilities: clientCapabilities)

    if workspace.builder.targets.contains(where: { target in !target.clangTUs.isEmpty })
      && !workspace.builder.toolchain.clangHasIndexSupport {
      fputs("warning: skipping test because '\(workspace.builder.toolchain.clang.path)' does not " +
            "have indexstore support; use swift-clang\n", stderr)
      return nil
    }

    return workspace
  }
}

extension TestLocation {
  public var position: Position {
    Position(self)
  }
}

extension Position {
  public init(_ loc: TestLocation) {
    self.init(line: loc.line - 1, utf16index: loc.utf16Column - 1)
  }

  /// Incorrectly use the UTF-8 column index in place of the UTF-16 one, to match the incorrect
  /// implementation in SourceKitServer when using the index.
  public init(badUTF16 loc: TestLocation) {
    self.init(line: loc.line - 1, utf16index: loc.utf8Column - 1)
  }
}

extension Location {
  public init(_ loc: TestLocation) {
    self.init(uri: DocumentURI(loc.url), range: Range(Position(loc)))
  }

  /// Incorrectly use the UTF-8 column index in place of the UTF-16 one, to match the incorrect
  /// implementation in SourceKitServer when using the index.
  public init(badUTF16 loc: TestLocation) {
    self.init(uri: DocumentURI(loc.url), range: Range(Position(badUTF16: loc)))
  }
}

extension TibsToolchain {
  public convenience init(_ sktc: Toolchain) {
    let ninja: URL?
    if let ninjaPath = ProcessInfo.processInfo.environment["NINJA_BIN"] {
      ninja = URL(fileURLWithPath: ninjaPath, isDirectory: false)
    } else {
      ninja = findTool(name: "ninja")
    }
    self.init(
      swiftc: sktc.swiftc!.asURL,
      clang: sktc.clang!.asURL,
      libIndexStore: sktc.libIndexStore!.asURL,
      tibs: XCTestCase.productsDirectory.appendingPathComponent("tibs", isDirectory: false),
      ninja: ninja)
  }
}

extension TestLocation {
  public var docIdentifier: TextDocumentIdentifier { TextDocumentIdentifier(url) }
}
