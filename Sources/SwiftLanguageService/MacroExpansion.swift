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

private import Crypto
import Csourcekitd
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKUtilities
import SourceKitD
import SourceKitLSP
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Caches the contents of macro expansions that were recently requested by the user.
actor MacroExpansionManager {
  private struct CacheKey: Hashable {
    let snapshotID: DocumentSnapshot.ID
    let range: Range<Position>
    let buildSettings: SwiftCompileCommand?
    let actionUID: String
  }

  init(swiftLanguageService: SwiftLanguageService?) {
    self.swiftLanguageService = swiftLanguageService
  }

  private weak let swiftLanguageService: SwiftLanguageService?

  /// The cache that stores reportTasks for a combination of uri, range and build settings.
  ///
  /// - Note: The capacity of this cache should be bigger than the maximum expansion depth of macros a user might
  ///   do to avoid re-generating all parent macros to a nested macro expansion's buffer. 10 seems to be big enough
  ///   for that because it's unlikely that a macro will expand to more than 10 levels.
  private var cache = LRUCache<CacheKey, [RefactoringEdit]>(capacity: 10)

  /// The sourcekitd refactoring actions that produce peekable expansion buffers.
  ///
  /// A cursor position is only ever applicable to a single one of them. Expanding a
  /// macro requires the cursor to be on the macro, and expanding a derived conformance
  /// requires it to be on a protocol in the inheritance clause.
  private static let expansionActionUIDs = [
    ExpandMacroCommand.actionString,
    ExpandDerivedConformanceCommand.actionString,
  ]

  /// Return the text of the expansion referenced by `macroExpansionURLData`.
  func macroExpansion(
    for macroExpansionURLData: MacroExpansionReferenceDocumentURLData
  ) async throws -> String {
    for actionUID in Self.expansionActionUIDs {
      let edits: [RefactoringEdit]
      do {
        edits = try await expansions(
          in: macroExpansionURLData.parent,
          at: macroExpansionURLData.parentSelectionRange,
          actionUID: actionUID
        )
      } catch {
        logger.debug("Failed to run \(actionUID) for \(macroExpansionURLData.bufferName): \(error.forLogging)")
        continue
      }
      if let expansion = edits.filter({ $0.bufferName == macroExpansionURLData.bufferName }).only {
        return expansion.newText
      }
    }
    throw ResponseError.unknown("Failed to find macro expansion for \(macroExpansionURLData.bufferName).")
  }

  /// Run the sourcekitd refactoring action `actionUID` at `range` and return the buffers it expands to.
  ///
  /// `actionUID` is one of the expansion-producing refactorings, like
  /// `source.refactoring.kind.expand.macro` or
  /// `source.refactoring.kind.expand.derived_conformance`.
  func expansions(
    in uri: DocumentURI,
    at range: Range<Position>,
    actionUID: String
  ) async throws -> [RefactoringEdit] {
    guard let swiftLanguageService else {
      // `SwiftLanguageService` has been destructed. We are tearing down the language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let snapshot = try await swiftLanguageService.latestSnapshot(for: uri)
    let compileCommand = await swiftLanguageService.compileCommand(for: uri, fallbackAfterTimeout: false)

    let cacheKey = CacheKey(
      snapshotID: snapshot.id,
      range: range,
      buildSettings: compileCommand,
      actionUID: actionUID
    )
    if let valueFromCache = cache[cacheKey] {
      return valueFromCache
    }
    let edits = try await expansionsImpl(
      in: snapshot,
      at: range,
      buildSettings: compileCommand,
      actionUID: actionUID
    )
    cache[cacheKey] = edits
    return edits
  }

  private func expansionsImpl(
    in snapshot: DocumentSnapshot,
    at range: Range<Position>,
    buildSettings: SwiftCompileCommand?,
    actionUID: String
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
      keys.cancelOnSubsequentRequest: 0,
      // Preferred name for e.g. an extracted variable.
      // Empty string means sourcekitd chooses a name automatically.
      keys.name: "",
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      // LSP is zero based, but this request is 1 based.
      keys.line: line + 1,
      keys.column: utf8Column + 1,
      keys.length: length,
      keys.actionUID: swiftLanguageService.sourcekitd.api.uid_get_from_cstr(actionUID)!,
      keys.compilerArgs: buildSettings?.compilerArgs as [any SKDRequestValue]?,
    ])

    let dict = try await swiftLanguageService.send(sourcekitdRequest: \.semanticRefactoring, skreq, snapshot: snapshot)
    guard let expansions = [RefactoringEdit](dict, snapshot, keys) else {
      throw SemanticRefactoringError.noEditsNeeded(snapshot.uri)
    }
    return expansions
  }

  /// Remove all cached macro expansions for the given primary file, eg. because the macro's plugin might have changed.
  func purge(primaryFile: DocumentURI) {
    cache.removeAll {
      $0.snapshotID.uri.primaryFile ?? $0.snapshotID.uri == primaryFile
    }
  }
}

extension SwiftLanguageService {
  /// Handles the `ExpandMacroCommand` and `ExpandDerivedConformanceCommand`.
  ///
  /// Makes a `PeekDocumentsRequest` or `ShowDocumentRequest`, containing the
  /// location of each expansion, to the client depending on whether the
  /// client supports the `experimental["workspace/peekDocuments"]` capability.
  ///
  /// - Parameters:
  ///   - actionUID: The sourcekitd refactoring action that produces the expansions, like
  ///     `source.refactoring.kind.expand.macro`.
  ///   - positionRange: The range that was selected when the command was triggered.
  ///   - textDocument: The document in which the command was triggered.
  func expand(
    actionUID: String,
    positionRange: Range<Position>,
    textDocument: TextDocumentIdentifier
  ) async throws {
    guard let sourceKitLSPServer else {
      // `SourceKitLSPServer` has been destructed. We are tearing down the
      // language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let parentFileDisplayName =
      switch try? ReferenceDocumentURL(from: textDocument.uri) {
      case .macroExpansion(let data):
        data.bufferName
      case .generatedInterface(let data):
        data.displayName
      case nil:
        textDocument.uri.fileURL?.lastPathComponent ?? textDocument.uri.pseudoPath
      }

    let expansions = try await macroExpansionManager.expansions(
      in: textDocument.uri,
      at: positionRange,
      actionUID: actionUID
    )

    var completeExpansionFileContent = ""
    var completeExpansionDirectoryName = ""

    var expansionReferenceDocumentURLs: [ReferenceDocumentURL] = []
    for expansionEdit in expansions {
      if let bufferName = expansionEdit.bufferName {
        let expansionReferenceDocumentURL =
          ReferenceDocumentURL.macroExpansion(
            MacroExpansionReferenceDocumentURLData(
              macroExpansionEditRange: expansionEdit.range,
              parent: textDocument.uri,
              parentSelectionRange: positionRange,
              bufferName: bufferName
            )
          )

        expansionReferenceDocumentURLs.append(expansionReferenceDocumentURL)

        completeExpansionDirectoryName += "\(bufferName)-"

        let editContent =
          """
          // \(parentFileDisplayName) @ \(expansionEdit.range.lowerBound.line + 1):\(expansionEdit.range.lowerBound.utf16index + 1) - \(expansionEdit.range.upperBound.line + 1):\(expansionEdit.range.upperBound.utf16index + 1)
          \(expansionEdit.newText)


          """
        completeExpansionFileContent += editContent
      } else if !expansionEdit.newText.isEmpty {
        logger.fault("Unable to retrieve some parts of the expansion")
      }
    }

    if self.capabilityRegistry.clientHasExperimentalCapability(PeekDocumentsRequest.method),
      self.capabilityRegistry.clientHasWorkspaceGetReferenceDocumentSupport
    {
      let expansionURIs = try expansionReferenceDocumentURLs.map { try $0.uri }

      let uri = textDocument.uri.primaryFile ?? textDocument.uri

      let position =
        switch try? ReferenceDocumentURL(from: textDocument.uri) {
        case .macroExpansion(let data):
          data.primaryFileSelectionRange.lowerBound
        case .generatedInterface, nil:
          positionRange.lowerBound
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
          logger.error("client refused to peek expansion")
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
        self.generatedMacroExpansionsPath.appending(
          component:
            Insecure.MD5.hash(data: Data(completeExpansionDirectoryName.utf8))
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
        completeExpansionFilePath.appending(component: parentFileDisplayName)
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
