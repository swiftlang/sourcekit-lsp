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
import Basic
import SPMUtility
import XCTest
import Foundation

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
    toolchain: Toolchain) throws
  {
    self.tibsWorkspace = try TibsTestWorkspace(
      immutableProjectDir: immutableProjectDir,
      persistentBuildDir: persistentBuildDir,
      tmpDir: tmpDir,
      toolchain: TibsToolchain(toolchain))

    sk.allowUnexpectedNotification = true
    initWorkspace()
  }

  public init(projectDir: URL, tmpDir: URL, toolchain: Toolchain) throws {
    self.tibsWorkspace = try TibsTestWorkspace(
      projectDir: projectDir,
      tmpDir: tmpDir,
      toolchain: TibsToolchain(toolchain))

    sk.allowUnexpectedNotification = true
    initWorkspace()
  }

  func initWorkspace() {
    let buildPath = AbsolutePath(builder.buildRoot.path)
    testServer.server!.workspace = Workspace(
      rootPath: AbsolutePath(sources.rootDirectory.path),
      clientCapabilities: ClientCapabilities(),
      buildSettings: CompilationDatabaseBuildSystem(projectRoot: buildPath),
      index: index,
      buildSetup: BuildSetup(configuration: .debug, path: buildPath, flags: BuildFlags()))
  }
}

extension SKTibsTestWorkspace {

  public func testLoc(_ name: String) -> TestLocation { sources.locations[name]! }

  public func buildAndIndex() throws {
    try tibsWorkspace.buildAndIndex()
  }
}

extension SKTibsTestWorkspace {
  public func openDocument(_ url: URL, language: Language) throws {
    sk.send(DidOpenTextDocument(textDocument: TextDocumentItem(
      url: url,
      language: language,
      version: 1,
      text: try sources.sourceCache.get(url))))
  }
}

extension XCTestCase {

  public func staticSourceKitTibsWorkspace(name: String, testFile: String = #file) throws -> SKTibsTestWorkspace? {
    let testDirName = testDirectoryName
    let workspace = try SKTibsTestWorkspace(
      immutableProjectDir: inputsDirectory(testFile: testFile)
        .appendingPathComponent(name, isDirectory: true),
      persistentBuildDir: XCTestCase.productsDirectory
        .appendingPathComponent("sk-tests/\(testDirName)", isDirectory: true),
      tmpDir: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sk-test-data/\(testDirName)", isDirectory: true),
      toolchain: ToolchainRegistry.shared.default!)

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
    // FIXME: utf16 vfs utf8 column
    self.init(line: loc.line - 1, utf16index: loc.column - 1)
  }
}

extension Location {
  public init(_ loc: TestLocation) {
    self.init(url: loc.url, range: Range(Position(loc)))
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
