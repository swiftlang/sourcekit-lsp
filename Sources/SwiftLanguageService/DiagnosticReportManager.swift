//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@preconcurrency import IndexStoreDB
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKUtilities
import SemanticIndex
import SourceKitD
import SourceKitLSP
import SwiftDiagnostics
import SwiftExtensions
import SwiftParserDiagnostics
import SwiftSyntax
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct SourceKitLSP.Diagnostic

actor DiagnosticReportManager {
  /// A task to produce diagnostics, either from a diagnostics request to `sourcekitd` or by using the built-in swift-syntax.
  private typealias ReportTask = RefCountedCancellableTask<
    (report: RelatedFullDocumentDiagnosticReport, cachable: Bool)
  >

  private struct CacheKey: Hashable {
    let snapshotID: DocumentSnapshot.ID
    let buildSettings: SwiftCompileCommand?
  }

  private let sourcekitd: SourceKitD
  private let options: SourceKitLSPOptions
  private let syntaxTreeManager: SyntaxTreeManager
  private let documentManager: DocumentManager
  private let clientHasDiagnosticsCodeDescriptionSupport: Bool
  private let uncheckedIndexProvider: @Sendable () async -> UncheckedIndex?

  private nonisolated var keys: sourcekitd_api_keys { return sourcekitd.keys }
  private nonisolated var requests: sourcekitd_api_requests { return sourcekitd.requests }

  /// The cache that stores reportTasks for snapshot id and buildSettings
  ///
  /// - Note: The capacity has been chosen without scientific measurements.
  private var reportTaskCache = LRUCache<CacheKey, ReportTask>(capacity: 5)

  init(
    sourcekitd: SourceKitD,
    options: SourceKitLSPOptions,
    syntaxTreeManager: SyntaxTreeManager,
    documentManager: DocumentManager,
    clientHasDiagnosticsCodeDescriptionSupport: Bool,
    uncheckedIndexProvider: @escaping @Sendable () async -> UncheckedIndex?
  ) {
    self.sourcekitd = sourcekitd
    self.options = options
    self.syntaxTreeManager = syntaxTreeManager
    self.documentManager = documentManager
    self.clientHasDiagnosticsCodeDescriptionSupport = clientHasDiagnosticsCodeDescriptionSupport
    self.uncheckedIndexProvider = uncheckedIndexProvider
  }

  func diagnosticReport(
    for snapshot: DocumentSnapshot,
    buildSettings: SwiftCompileCommand?
  ) async throws -> RelatedFullDocumentDiagnosticReport {
    if let reportTask = reportTask(for: snapshot.id, buildSettings: buildSettings), await !reportTask.isCancelled {
      do {
        let cachedValue = try await reportTask.value
        if cachedValue.cachable {
          return cachedValue.report
        }
      } catch {
        // Do not cache failed requests
      }
    }
    let reportTask: ReportTask
    if let buildSettings, !buildSettings.isFallback {
      reportTask = ReportTask {
        return try await self.requestReport(with: snapshot, compilerArgs: buildSettings.compilerArgs)
      }
    } else {
      logger.log(
        "Producing syntactic diagnostics from the built-in swift-syntax because we \(buildSettings != nil ? "have fallback build settings" : "don't have build settings", privacy: .public))"
      )
      // If we don't have build settings or we only have fallback build settings,
      // sourcekitd won't be able to give us accurate semantic diagnostics.
      // Fall back to providing syntactic diagnostics from the built-in
      // swift-syntax. That's the best we can do for now.
      reportTask = ReportTask {
        return try await self.requestFallbackReport(with: snapshot)
      }
    }
    setReportTask(for: snapshot.id, buildSettings: buildSettings, reportTask: reportTask)
    return try await reportTask.value.report
  }

  func removeItemsFromCache(with uri: DocumentURI) async {
    reportTaskCache.removeAll(where: { $0.snapshotID.uri == uri })
  }

  private func requestReport(
    with snapshot: DocumentSnapshot,
    compilerArgs: [String]
  ) async throws -> (report: RelatedFullDocumentDiagnosticReport, cachable: Bool) {
    try Task.checkCancellation()

    let keys = self.keys

    let skreq = sourcekitd.dictionary([
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compilerArgs as [any SKDRequestValue],
    ])

    let dict: SKDResponseDictionary
    do {
      dict = try await self.sourcekitd.send(
        \.diagnostics,
        skreq,
        timeout: options.sourcekitdRequestTimeoutOrDefault,
        restartTimeout: options.semanticServiceRestartTimeoutOrDefault,
        documentUrl: snapshot.uri.arbitrarySchemeURL,
        fileContents: snapshot.text
      )
    } catch SKDError.requestFailed(let sourcekitdError) {
      var errorMessage = sourcekitdError
      if errorMessage.contains("semantic editor is disabled") {
        throw SKDError.requestFailed(sourcekitdError)
      }
      if errorMessage.hasPrefix("error response (Request Failed): error: ") {
        errorMessage = String(errorMessage.dropFirst(40))
      }
      let report = RelatedFullDocumentDiagnosticReport(items: [
        Diagnostic(
          range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
          severity: .error,
          source: "SourceKit",
          message: "Internal SourceKit error: \(errorMessage)"
        )
      ])
      // If generating the diagnostic report failed because of a sourcekitd problem, mark as as non-cachable because
      // executing the sourcekitd request again might succeed (eg. if sourcekitd has been restored after a crash).
      return (report, cachable: false)
    }

    try Task.checkCancellation()

    let rawDiagnostics: SKDResponseArray? = dict[keys.diagnostics]

    let hasMissingImportDiagnostic =
      rawDiagnostics?.compactMap { rawDiagnostic -> String? in
        guard let diagnosticID: String = rawDiagnostic[keys.id] else {
          return nil
        }

        return missingImportDiagnosticIDs.contains(diagnosticID) ? diagnosticID : nil
      }.isEmpty == false

    let checkedIndex: CheckedIndex?
    let syntaxTree: SourceFileSyntax?
    if hasMissingImportDiagnostic, let uncheckedIndex = await uncheckedIndex(timeout: .milliseconds(500)) {
      checkedIndex = uncheckedIndex.checked(for: .deletedFiles)
      syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    } else {
      checkedIndex = nil
      syntaxTree = nil
    }

    let diagnostics: [Diagnostic] =
      rawDiagnostics?.compactMap { rawDiagnostic in
        guard
          var diagnostic = Diagnostic(
            rawDiagnostic,
            in: snapshot,
            documentManager: documentManager,
            useEducationalNoteAsCode: self.clientHasDiagnosticsCodeDescriptionSupport
          )
        else {
          return nil
        }

        if let diagnosticID: String = rawDiagnostic[keys.id],
          missingImportDiagnosticIDs.contains(diagnosticID),
          let diagnosticDescription: String = rawDiagnostic[keys.description],
          let missingSymbol = missingSymbolName(from: diagnosticDescription),
          let checkedIndex,
          let syntaxTree,
          let codeAction = try? missingImportCodeAction(
            for: missingSymbol,
            index: checkedIndex,
            syntaxTree: syntaxTree,
            snapshot: snapshot
          )
        {
          diagnostic.codeActions = (diagnostic.codeActions ?? []) + [codeAction]
        }

        return diagnostic
      } ?? []

    let report = RelatedFullDocumentDiagnosticReport(items: diagnostics)
    return (report, cachable: true)
  }

  private func requestFallbackReport(
    with snapshot: DocumentSnapshot
  ) async throws -> (report: RelatedFullDocumentDiagnosticReport, cachable: Bool) {
    // If we don't have build settings or we only have fallback build settings,
    // sourcekitd won't be able to give us accurate semantic diagnostics.
    // Fall back to providing syntactic diagnostics from the built-in
    // swift-syntax. That's the best we can do for now.
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let swiftSyntaxDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntaxTree)
    let diagnostics = swiftSyntaxDiagnostics.compactMap { (diag) -> Diagnostic? in
      if diag.diagnosticID == StaticTokenError.editorPlaceholder.diagnosticID {
        // Ignore errors about editor placeholders in the source file, similar to how sourcekitd ignores them.
        return nil
      }
      return Diagnostic(diag, in: snapshot)
    }
    let report = RelatedFullDocumentDiagnosticReport(items: diagnostics)
    return (report, cachable: true)
  }

  /// The reportTask for the given document snapshot and buildSettings.
  private func reportTask(
    for snapshotID: DocumentSnapshot.ID,
    buildSettings: SwiftCompileCommand?
  ) -> ReportTask? {
    return reportTaskCache[CacheKey(snapshotID: snapshotID, buildSettings: buildSettings)]
  }

  /// Set the reportTask for the given document snapshot and buildSettings.
  private func setReportTask(
    for snapshotID: DocumentSnapshot.ID,
    buildSettings: SwiftCompileCommand?,
    reportTask: ReportTask
  ) {
    // Remove any reportTasks for old versions of this document.
    reportTaskCache.removeAll(where: { $0.snapshotID <= snapshotID })
    reportTaskCache[CacheKey(snapshotID: snapshotID, buildSettings: buildSettings)] = reportTask
  }

  private let missingImportDiagnosticIDs: Set<String> = [
    "cannot_find_type_in_scope",
    "cannot_find_in_scope",
    "use_of_unresolved_identifier",
  ]

  private func missingSymbolName(from diagnosticDescription: String) -> String? {
    let components = diagnosticDescription.split(separator: "'", omittingEmptySubsequences: false)
    guard components.count == 3 else {
      return nil
    }

    let symbolName = String(components[1])
    return symbolName.isEmpty ? nil : symbolName
  }

  private func missingImportCodeAction(
    for symbolName: String,
    index: CheckedIndex,
    syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot
  ) throws -> CodeAction? {
    guard let moduleName = try index.uniqueModuleProvidingSymbol(named: symbolName) else {
      return nil
    }

    let existingImports = syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
    let edit: TextEdit
    if let lastImport = existingImports.last {
      let insertionPosition = snapshot.position(of: lastImport.endPosition)
      edit = TextEdit(
        range: insertionPosition..<insertionPosition,
        newText: "\nimport \(moduleName)"
      )
    } else {
      let startOfFile = Position(line: 0, utf16index: 0)
      edit = TextEdit(
        range: startOfFile..<startOfFile,
        newText: "import \(moduleName)\n\n"
      )
    }

    return CodeAction(
      title: "Add import for '\(moduleName)'",
      kind: .quickFix,
      diagnostics: nil,
      edit: WorkspaceEdit(changes: [snapshot.uri: [edit]])
    )
  }

  private func uncheckedIndex(timeout: Duration) async -> UncheckedIndex? {
    let uncheckedIndexProvider = self.uncheckedIndexProvider

    do {
      return try await withTimeout(timeout) {
        await uncheckedIndexProvider()
      }
    } catch {
      return nil
    }
  }
}

fileprivate extension CheckedIndex {
  func uniqueModuleProvidingSymbol(named symbolName: String) throws -> String? {
    var moduleName: String?

    try forEachCanonicalSymbolOccurrence(byName: symbolName) { occurrence in
      guard occurrence.roles.contains(.definition) || occurrence.roles.contains(.declaration) else {
        return true
      }

      let occurrenceModuleName = occurrence.location.moduleName
      guard !occurrenceModuleName.isEmpty else {
        return true
      }

      guard moduleName == nil || moduleName == occurrenceModuleName else {
        moduleName = nil
        return false
      }

      moduleName = occurrenceModuleName
      return true
    }

    return moduleName
  }
}
