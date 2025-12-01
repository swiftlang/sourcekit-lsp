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

package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SKOptions
package import SourceKitLSP
import SwiftExtensions
package import ToolchainRegistry

/// The location of a test file within test workspace.
package struct RelativeFileLocation: Hashable, ExpressibleByStringLiteral {
  /// The subdirectories in which the file is located.
  package let directories: [String]

  /// The file's name.
  package let fileName: String

  package init(directories: [String] = [], _ fileName: String) {
    self.directories = directories
    self.fileName = fileName
  }

  package init(stringLiteral value: String) {
    let components = value.components(separatedBy: "/")
    self.init(directories: components.dropLast(), components.last!)
  }

  package func url(relativeTo: URL) -> URL {
    var url = relativeTo
    for directory in directories {
      url = url.appending(component: directory)
    }
    url = url.appending(component: fileName)
    return url
  }
}

/// A test project that writes multiple files to disk and opens a `TestSourceKitLSPClient` client with a workspace
/// pointing to a temporary directory containing those files.
///
/// The temporary files will be deleted when the `TestSourceKitLSPClient` is destructed.
package class MultiFileTestProject {
  /// Information necessary to open a file in the LSP server by its filename.
  package struct FileData {
    /// The URI at which the file is stored on disk.
    package let uri: DocumentURI

    /// The contents of the file including location markers.
    package let markedText: String
  }

  package let testClient: TestSourceKitLSPClient

  /// Information necessary to open a file in the LSP server by its filename.
  private let fileData: [String: FileData]

  enum Error: Swift.Error {
    /// No file with the given filename is known to the `MultiFileTestProject`.
    case fileNotFound(name: String)

    /// Trying to delete a file in `changeDocument` that doesn't exist.
    case deleteNonExistentFile
  }

  /// The directory in which the temporary files are being placed.
  package let scratchDirectory: URL

  package static func writeFilesToDisk(
    files: [RelativeFileLocation: String],
    scratchDirectory: URL
  ) throws -> [String: FileData] {
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

    var fileData: [String: FileData] = [:]
    for (fileLocation, markedText) in files {
      // Drop trailing slashes from the test dir URL, so tests can write `$TEST_DIR_URL/someFile.swift` without ending
      // up with double slashes.
      var testDirUrl = scratchDirectory.absoluteString
      while testDirUrl.hasSuffix("/") {
        testDirUrl = String(testDirUrl.dropLast())
      }
      let markedText =
        markedText
        .replacingOccurrences(of: "$TEST_DIR_URL", with: testDirUrl)
        .replacingOccurrences(
          of: "$TEST_DIR_BACKSLASH_ESCAPED",
          with: try scratchDirectory.filePath.replacing(#"\"#, with: #"\\"#)
        )
        .replacingOccurrences(of: "$TEST_DIR", with: try scratchDirectory.filePath)
      let fileURL = fileLocation.url(relativeTo: scratchDirectory)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try extractMarkers(markedText).textWithoutMarkers.write(to: fileURL, atomically: false, encoding: .utf8)

      if fileData[fileLocation.fileName] != nil {
        // If we already have a file with this name, remove its data. That way we can't reference any of the two
        // conflicting documents and will throw when trying to open them, instead of non-deterministically picking one.
        fileData[fileLocation.fileName] = nil
      } else {
        fileData[fileLocation.fileName] = FileData(
          uri: DocumentURI(fileURL),
          markedText: markedText
        )
      }
    }
    return fileData
  }

  /// Writes the specified files to a temporary directory on disk and creates a `TestSourceKitLSPClient` for that
  /// temporary directory.
  ///
  /// The file contents can contain location markers, which are returned when opening a document using
  /// ``openDocument(_:)``.
  ///
  /// File contents can also contain `$TEST_DIR`, which gets replaced by the temporary directory.
  package init(
    files: [RelativeFileLocation: String],
    workspaces: (_ scratchDirectory: URL) async throws -> [WorkspaceFolder] = {
      [WorkspaceFolder(uri: DocumentURI($0))]
    },
    initializationOptions: LSPAny? = nil,
    capabilities: ClientCapabilities = ClientCapabilities(),
    options: SourceKitLSPOptions? = nil,
    toolchainRegistry: ToolchainRegistry = .forTesting,
    hooks: Hooks = Hooks(),
    enableBackgroundIndexing: Bool = false,
    usePullDiagnostics: Bool = true,
    preInitialization: ((TestSourceKitLSPClient) -> Void)? = nil,
    testScratchDir overrideTestScratchDir: URL? = nil,
    cleanUp: (@Sendable () -> Void)? = nil,
    testName: String = #function
  ) async throws {
    scratchDirectory = try overrideTestScratchDir ?? testScratchDir(testName: testName)
    self.fileData = try Self.writeFilesToDisk(files: files, scratchDirectory: scratchDirectory)

    self.testClient = try await TestSourceKitLSPClient(
      options: options,
      hooks: hooks,
      initializationOptions: initializationOptions,
      capabilities: capabilities,
      toolchainRegistry: toolchainRegistry,
      usePullDiagnostics: usePullDiagnostics,
      enableBackgroundIndexing: enableBackgroundIndexing,
      workspaceFolders: workspaces(scratchDirectory),
      preInitialization: preInitialization,
      cleanUp: { [scratchDirectory] in
        if cleanScratchDirectories {
          try? FileManager.default.removeItem(at: scratchDirectory)
        }
        cleanUp?()
      }
    )
  }

  /// Opens the document with the given file name in the SourceKit-LSP server.
  ///
  /// - Returns: The URI for the opened document and the positions of the location markers.
  package func openDocument(
    _ fileName: String,
    language: Language? = nil
  ) throws -> (uri: DocumentURI, positions: DocumentPositions) {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound(name: fileName)
    }
    let positions = testClient.openDocument(fileData.markedText, uri: fileData.uri, language: language)
    return (fileData.uri, positions)
  }

  /// Returns the URI of the file with the given name.
  package func uri(for fileName: String) throws -> DocumentURI {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound(name: fileName)
    }
    return fileData.uri
  }

  /// Returns the position of the given marker in the given file.
  package func position(of marker: String, in fileName: String) throws -> Position {
    guard let fileData = self.fileData[fileName] else {
      throw Error.fileNotFound(name: fileName)
    }
    return DocumentPositions(markedText: fileData.markedText)[marker]
  }

  package func range(from fromMarker: String, to toMarker: String, in fileName: String) throws -> Range<Position> {
    return try position(of: fromMarker, in: fileName)..<position(of: toMarker, in: fileName)
  }

  package func location(from fromMarker: String, to toMarker: String, in fileName: String) throws -> Location {
    let range = try self.range(from: fromMarker, to: toMarker, in: fileName)
    return Location(uri: try self.uri(for: fileName), range: range)
  }

  /// Modify the given file on disk, send a watched files did change notification to SourceKit-LSP and wait for that
  /// notification to get handled.
  ///
  /// When `newMarkedContents` is `nil`, the file is deleted.
  ///
  /// Returns the URI and the document positions of the new document.
  @discardableResult
  package func changeFileOnDisk(
    _ fileName: String,
    newMarkedContents: String?
  ) async throws -> (uri: DocumentURI, positions: DocumentPositions) {
    let uri = try self.uri(for: fileName)
    guard let url = uri.fileURL else {
      throw Error.fileNotFound(name: fileName)
    }
    let positions: DocumentPositions
    let newContents: String?
    if let newMarkedContents {
      (positions, newContents) = DocumentPositions.extract(from: newMarkedContents)
    } else {
      positions = DocumentPositions(markedText: "")
      newContents = nil
    }

    let fileExists = FileManager.default.fileExists(at: url)
    let changeType: FileChangeType
    switch (fileExists, newContents) {
    case (false, let newContents?):
      try await newContents.writeWithRetry(to: url)
      changeType = .created
    case (false, nil):
      throw Error.deleteNonExistentFile
    case (true, let newContents?):
      try await newContents.writeWithRetry(to: url)
      changeType = .changed
    case (true, nil):
      try FileManager.default.removeItem(at: url)
      changeType = .deleted
    }
    testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: uri, type: changeType)]))
    // Ensure that we handle the `DidChangeWatchedFilesNotification`.
    try await testClient.send(SynchronizeRequest())

    return (uri, positions)
  }
}
