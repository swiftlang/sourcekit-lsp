//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SKCore
import TSCBasic

public struct SwiftPMTestWorkspace {
  /// The location of a file within a package, ie. its module and its filename.
  public struct FileSpec: Hashable, ExpressibleByStringLiteral {
    fileprivate let moduleName: String
    fileprivate let fileName: String

    public init(module: String = "MyLibrary", _ fileName: String) {
      self.moduleName = module
      self.fileName = fileName
    }

    public init(stringLiteral value: String) {
      self.init(value)
    }
  }

  /// Information necessary to open a file in the LSP server by its filename.
  private struct FileData {
    /// The URI at which the file is stored on disk.
    let uri: DocumentURI

    /// The contents of the file including location markers.
    let markedText: String
  }

  enum Error: Swift.Error {
    /// The `swift` executable could not be found.
    case swiftNotFound

    /// No file with the given filename is known to the `SwiftPMTestWorkspace`.
    case fileNotFound
  }

  public let testClient: TestSourceKitLSPClient

  /// Information necessary to open a file in the LSP server by its filename.
  private let fileData: [String: FileData]

  public static let defaultPackageManifest: String = """
    // swift-tools-version: 5.7

    import PackageDescription

    let package = Package(
      name: "MyLibrary",
      targets: [.target(name: "MyLibrary")]
    )
    """

  /// Create a new SwiftPM package with the given files.
  ///
  /// If `index` is `true`, then the package will be built, indexing all modules within the package.
  public init(
    files: [FileSpec: String],
    manifest: String = Self.defaultPackageManifest,
    index: Bool = false,
    testName: String = #function
  ) async throws {
    let packageDirectory = try testScratchDirName(testName)

    guard let swift = ToolchainRegistry.shared.default?.swift?.asURL else {
      throw Error.swiftNotFound
    }

    var fileData: [String: FileData] = [:]
    for (fileSpec, markedText) in files {
      let fileURL =
        packageDirectory
        .appendingPathComponent("Sources")
        .appendingPathComponent(fileSpec.moduleName)
        .appendingPathComponent(fileSpec.fileName)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try extractMarkers(markedText).textWithoutMarkers.write(
        to: fileURL,
        atomically: false,
        encoding: .utf8
      )

      fileData[fileSpec.fileName] = FileData(
        uri: DocumentURI(fileURL),
        markedText: markedText
      )
    }
    self.fileData = fileData

    try manifest.write(
      to: packageDirectory.appendingPathComponent("Package.swift"),
      atomically: false,
      encoding: .utf8
    )

    if index {
      /// Running `swift build` might fail if the package contains syntax errors. That's intentional
      try await Process.checkNonZeroExit(arguments: [swift.path, "build", "--package-path", packageDirectory.path])
    }

    self.testClient = try await TestSourceKitLSPClient(
      workspaceFolders: [
        WorkspaceFolder(uri: DocumentURI(packageDirectory))
      ],
      cleanUp: {
        try? FileManager.default.removeItem(at: packageDirectory)
      }
    )

    // Wait for the indexstore-db to finish indexing
    _ = try await testClient.send(PollIndexRequest())
  }

  public func openDocument(_ fileName: String) throws -> (uri: DocumentURI, positions: DocumentPositions) {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound
    }
    let positions = testClient.openDocument(fileData.markedText, uri: fileData.uri)
    return (fileData.uri, positions)
  }
}
