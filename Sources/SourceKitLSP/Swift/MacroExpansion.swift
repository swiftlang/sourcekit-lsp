//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Crypto
import Csourcekitd
import Foundation
import LanguageServerProtocol
import SKLogging
import SKOptions
import SKUtilities
import SourceKitD
import SwiftExtensions

/// Caches the contents of macro expansions that were recently requested by the user.
actor MacroExpansionManager {
  private struct CacheEntry {
    // Key
    let snapshotID: DocumentSnapshot.ID
    let range: Range<Position>
    let buildSettings: SwiftCompileCommand?

    // Value
    let value: [RefactoringEdit]

    fileprivate init(
      snapshot: DocumentSnapshot,
      range: Range<Position>,
      buildSettings: SwiftCompileCommand?,
      value: [RefactoringEdit]
    ) {
      self.snapshotID = snapshot.id
      self.range = range
      self.buildSettings = buildSettings
      self.value = value
    }
  }

  init(swiftLanguageService: SwiftLanguageService?) {
    self.swiftLanguageService = swiftLanguageService
  }

  private weak var swiftLanguageService: SwiftLanguageService?

  /// The number of macro expansions to cache.
  ///
  /// - Note: This should be bigger than the maximum expansion depth of macros a user might do to avoid re-generating
  ///   all parent macros to a nested macro expansion's buffer. 10 seems to be big enough for that because it's
  ///   unlikely that a macro will expand to more than 10 levels.
  private let cacheSize = 10

  /// The cache that stores reportTasks for a combination of uri, range and build settings.
  ///
  /// Conceptually, this is a dictionary. To prevent excessive memory usage we
  /// only keep `cacheSize` entries within the array. Older entries are at the
  /// end of the list, newer entries at the front.
  private var cache: [CacheEntry] = []

  /// Return the text of the macro expansion referenced by `macroExpansionURLData`.
  func macroExpansion(
    for macroExpansionURLData: MacroExpansionReferenceDocumentURLData
  ) async throws -> String {
    let expansions = try await macroExpansions(
      in: macroExpansionURLData.parent,
      at: macroExpansionURLData.parentSelectionRange
    )
    guard let expansion = expansions.filter({ $0.bufferName == macroExpansionURLData.bufferName }).only else {
      throw ResponseError.unknown("Failed to find macro expansion for \(macroExpansionURLData.bufferName).")
    }
    return expansion.newText
  }

  func macroExpansions(
    in uri: DocumentURI,
    at range: Range<Position>
  ) async throws -> [RefactoringEdit] {
    guard let swiftLanguageService else {
      // `SwiftLanguageService` has been destructed. We are tearing down the language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let snapshot = try await swiftLanguageService.latestSnapshot(for: uri)
    let buildSettings = await swiftLanguageService.buildSettings(for: uri, fallbackAfterTimeout: false)

    if let cacheEntry = cache.first(where: {
      $0.snapshotID == snapshot.id && $0.range == range && $0.buildSettings == buildSettings
    }) {
      return cacheEntry.value
    }
    let macroExpansions = try await macroExpansionsImpl(in: snapshot, at: range, buildSettings: buildSettings)
    cache.insert(
      CacheEntry(snapshot: snapshot, range: range, buildSettings: buildSettings, value: macroExpansions),
      at: 0
    )

    while cache.count > cacheSize {
      cache.removeLast()
    }

    return macroExpansions
  }

  private func macroExpansionsImpl(
    in snapshot: DocumentSnapshot,
    at range: Range<Position>,
    buildSettings: SwiftCompileCommand?
  ) async throws -> [RefactoringEdit] {
    guard let swiftLanguageService else {
      // `SwiftLanguageService` has been destructed. We are tearing down the language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }
    let keys = swiftLanguageService.keys

    let line = range.lowerBound.line
    let utf16Column = range.lowerBound.utf16index
    let utf8Column = snapshot.lineTable.utf8ColumnAt(line: line, utf16Column: utf16Column)
    let length = snapshot.utf8OffsetRange(of: range).count

    let skreq = swiftLanguageService.sourcekitd.dictionary([
      keys.request: swiftLanguageService.requests.semanticRefactoring,
      // Preferred name for e.g. an extracted variable.
      // Empty string means sourcekitd chooses a name automatically.
      keys.name: "",
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      // LSP is zero based, but this request is 1 based.
      keys.line: line + 1,
      keys.column: utf8Column + 1,
      keys.length: length,
      keys.actionUID: swiftLanguageService.sourcekitd.api.uid_get_from_cstr("source.refactoring.kind.expand.macro")!,
      keys.compilerArgs: buildSettings?.compilerArgs as [SKDRequestValue]?,
    ])

    let dict = try await swiftLanguageService.sendSourcekitdRequest(
      skreq,
      fileContents: snapshot.text
    )
    guard let expansions = [RefactoringEdit](dict, snapshot, keys) else {
      throw SemanticRefactoringError.noEditsNeeded(snapshot.uri)
    }
    return expansions
  }

  /// Remove all cached macro expansions for the given primary file, eg. because the macro's plugin might have changed.
  func purge(primaryFile: DocumentURI) {
    cache.removeAll { $0.snapshotID.uri.primaryFile ?? $0.snapshotID.uri == primaryFile }
  }
}

extension SwiftLanguageService {
  /// Handles the `ExpandMacroCommand`.
  ///
  /// Makes a `PeekDocumentsRequest` or `ShowDocumentRequest`, containing the
  /// location of each macro expansion, to the client depending on whether the
  /// client supports the `experimental["workspace/peekDocuments"]` capability.
  ///
  /// - Parameters:
  ///   - expandMacroCommand: The `ExpandMacroCommand` that triggered this request.
  func expandMacro(
    _ expandMacroCommand: ExpandMacroCommand
  ) async throws {
    guard let sourceKitLSPServer else {
      // `SourceKitLSPServer` has been destructed. We are tearing down the
      // language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let parentFileDisplayName =
      switch try? ReferenceDocumentURL(from: expandMacroCommand.textDocument.uri) {
      case .macroExpansion(let data):
        data.bufferName
      case .generatedInterface(let data):
        data.displayName
      case nil:
        expandMacroCommand.textDocument.uri.fileURL?.lastPathComponent ?? expandMacroCommand.textDocument.uri.pseudoPath
      }

    let expansions = try await macroExpansionManager.macroExpansions(
      in: expandMacroCommand.textDocument.uri,
      at: expandMacroCommand.positionRange
    )

    var completeExpansionFileContent = ""
    var completeExpansionDirectoryName = ""

    var macroExpansionReferenceDocumentURLs: [ReferenceDocumentURL] = []
    for macroEdit in expansions {
      if let bufferName = macroEdit.bufferName {
        let macroExpansionReferenceDocumentURLData =
          ReferenceDocumentURL.macroExpansion(
            MacroExpansionReferenceDocumentURLData(
              macroExpansionEditRange: macroEdit.range,
              parent: expandMacroCommand.textDocument.uri,
              parentSelectionRange: expandMacroCommand.positionRange,
              bufferName: bufferName
            )
          )

        macroExpansionReferenceDocumentURLs.append(macroExpansionReferenceDocumentURLData)

        completeExpansionDirectoryName += "\(bufferName)-"

        let editContent =
          """
          // \(parentFileDisplayName) @ \(macroEdit.range.lowerBound.line + 1):\(macroEdit.range.lowerBound.utf16index + 1) - \(macroEdit.range.upperBound.line + 1):\(macroEdit.range.upperBound.utf16index + 1)
          \(macroEdit.newText)


          """
        completeExpansionFileContent += editContent
      } else if !macroEdit.newText.isEmpty {
        logger.fault("Unable to retrieve some parts of macro expansion")
      }
    }

    if case .dictionary(let experimentalCapabilities) = self.capabilityRegistry.clientCapabilities.experimental,
      case .bool(true) = experimentalCapabilities["workspace/peekDocuments"],
      case .bool(true) = experimentalCapabilities["workspace/getReferenceDocument"]
    {
      let expansionURIs = try macroExpansionReferenceDocumentURLs.map { try $0.uri }

      let uri = expandMacroCommand.textDocument.uri.primaryFile ?? expandMacroCommand.textDocument.uri

      let position =
        switch try? ReferenceDocumentURL(from: expandMacroCommand.textDocument.uri) {
        case .macroExpansion(let data):
          data.primaryFileSelectionRange.lowerBound
        case .generatedInterface, nil:
          expandMacroCommand.positionRange.lowerBound
        }

      Task {
        let req = PeekDocumentsRequest(
          uri: uri,
          position: position,
          locations: expansionURIs
        )

        let response = await orLog("Sending PeekDocumentsRequest to Client") {
          try await sourceKitLSPServer.sendRequestToClient(req)
        }

        if let response, !response.success {
          logger.error("client refused to peek macro")
        }
      }
    } else {
      // removes superfluous newline
      if completeExpansionFileContent.hasSuffix("\n\n") {
        completeExpansionFileContent.removeLast()
      }

      if completeExpansionDirectoryName.hasSuffix("-") {
        completeExpansionDirectoryName.removeLast()
      }

      var completeExpansionFilePath =
        self.generatedMacroExpansionsPath.appendingPathComponent(
          Insecure.MD5.hash(
            data: Data(completeExpansionDirectoryName.utf8)
          )
          .map { String(format: "%02hhx", $0) }  // maps each byte of the hash to its hex equivalent `String`
          .joined()
        )

      do {
        try FileManager.default.createDirectory(
          at: completeExpansionFilePath,
          withIntermediateDirectories: true
        )
      } catch {
        throw ResponseError.unknown(
          "Failed to create directory for complete macro expansion at \(completeExpansionFilePath.description)"
        )
      }

      completeExpansionFilePath =
        completeExpansionFilePath.appendingPathComponent(parentFileDisplayName)
      do {
        try completeExpansionFileContent.write(to: completeExpansionFilePath, atomically: true, encoding: .utf8)
      } catch {
        throw ResponseError.unknown(
          "Unable to write complete macro expansion to \"\(completeExpansionFilePath.description)\""
        )
      }

      let completeMacroExpansionFilePath = completeExpansionFilePath

      Task {
        let req = ShowDocumentRequest(uri: DocumentURI(completeMacroExpansionFilePath))

        let response = await orLog("Sending ShowDocumentRequest to Client") {
          try await sourceKitLSPServer.sendRequestToClient(req)
        }

        if let response, !response.success {
          logger.error("client refused to show document for macro expansion")
        }
      }
    }
  }
}
