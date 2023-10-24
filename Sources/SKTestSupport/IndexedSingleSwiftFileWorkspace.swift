//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import ISDBTibs
import LanguageServerProtocol
import SKCore
import SourceKitLSP
import TSCBasic

public struct IndexedSingleSwiftFileWorkspace {
  enum Error: Swift.Error {
    case swiftcNotFound
  }

  public let testClient: TestSourceKitLSPClient
  public let fileURI: DocumentURI
  public let positions: DocumentPositions

  public init(
    _ markedText: String,
    testName: String = #function
  ) async throws {
    let testWorkspaceDirectory = try testScratchDir(testName: testName)

    let testFileURL = testWorkspaceDirectory.appendingPathComponent("test.swift")
    let indexURL = testWorkspaceDirectory.appendingPathComponent("index")
    let indexDBURL = testWorkspaceDirectory.appendingPathComponent("index-db")
    guard let swiftc = ToolchainRegistry.shared.default?.swiftc?.asURL else {
      throw Error.swiftcNotFound
    }

    // Create workspace with source file and compile_commands.json

    try extractMarkers(markedText).textWithoutMarkers.write(to: testFileURL, atomically: false, encoding: .utf8)

    var compilerArguments: [String] = [
      testFileURL.path,
      "-index-store-path", indexURL.path,
      "-index-ignore-system-modules",
      "-typecheck",
      "-o", testWorkspaceDirectory.appendingPathComponent("test.o").path,
    ]
    if let sdk = TibsBuilder.defaultSDKPath {
      compilerArguments += ["-sdk", sdk]
    }

    let compilationDatabase = JSONCompilationDatabase(
      [
        JSONCompilationDatabase.Command(
          directory: testWorkspaceDirectory.path,
          filename: testFileURL.path,
          commandLine: [swiftc.path] + compilerArguments
        )
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    try encoder.encode(compilationDatabase).write(
      to: testWorkspaceDirectory.appendingPathComponent("compile_commands.json")
    )

    // Run swiftc to build the index store
    try await Process.checkNonZeroExit(arguments: [swiftc.path] + compilerArguments)

    // Create the test client
    var options = SourceKitServer.Options.testDefault
    options.indexOptions = IndexOptions(
      indexStorePath: try AbsolutePath(validating: indexURL.path),
      indexDatabasePath: try AbsolutePath(validating: indexDBURL.path)
    )
    self.testClient = try await TestSourceKitLSPClient(
      serverOptions: options,
      workspaceFolders: [
        WorkspaceFolder(uri: DocumentURI(testWorkspaceDirectory))
      ],
      cleanUp: {
        try? FileManager.default.removeItem(at: testWorkspaceDirectory)
      }
    )

    // Wait for the indexstore-db to finish indexing
    _ = try await testClient.send(PollIndexRequest())

    // Open the document
    self.fileURI = DocumentURI(testFileURL)
    self.positions = testClient.openDocument(markedText, uri: fileURI)
  }
}
